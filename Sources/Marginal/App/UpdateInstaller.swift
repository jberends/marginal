import AppKit

/// Downloads a release's app archive and installs it over the running app.
///
/// The app is sandboxed, so it cannot overwrite its own bundle in /Applications.
/// Instead it downloads the zip into its container, writes a small `.command`
/// script, and opens that script with Terminal — which runs it outside the
/// sandbox with the user's normal permissions. The script waits for this process
/// to exit, swaps the app bundle, clears quarantine, relaunches, and deletes
/// itself. The app quits right after handing the script to Terminal.
@MainActor
enum UpdateInstaller {

    enum InstallError: LocalizedError {
        case noDownloadableAsset
        case downloadFailed(String)
        case appStoreInstall

        var errorDescription: String? {
            switch self {
            case .noDownloadableAsset:
                return "The latest release has no downloadable app archive."
            case .downloadFailed(let reason):
                return reason
            case .appStoreInstall:
                return "This copy of Marginal came from the App Store, which handles its own "
                    + "updates. Open the App Store to update."
            }
        }
    }

    /// Downloads the release's zip and hands off to the update script. On success the
    /// app terminates; the completion is only called on failure.
    static func downloadAndInstall(_ release: UpdateChecker.Release, onFailure: @escaping @MainActor (Error) -> Void) {
        // The menu item that reaches here is omitted on the App Store, so this is the
        // second line of defence rather than the first. It is worth having anyway: this is
        // the step that deletes the app bundle, and on an App Store install that also
        // destroys the receipt. Guard the destructive operation, not just the button.
        guard UpdateChecker.canSelfUpdate else {
            onFailure(InstallError.appStoreInstall)
            return
        }
        guard let asset = release.appZipAsset, let url = URL(string: asset.browserDownloadUrl) else {
            onFailure(InstallError.noDownloadableAsset)
            return
        }
        let assetName = asset.name
        URLSession.shared.downloadTask(with: url) { temporaryURL, response, error in
            // Everything up to and including the move must happen synchronously, here.
            // URLSession deletes the file at `temporaryURL` as soon as this closure returns,
            // so hopping to another actor first loses the download -- which surfaces as
            // "CFNetworkDownload_xxxxx.tmp couldn't be moved ... the former doesn't exist".
            if let error {
                Task { @MainActor in onFailure(InstallError.downloadFailed(error.localizedDescription)) }
                return
            }
            guard let temporaryURL else {
                Task { @MainActor in onFailure(InstallError.downloadFailed("The download produced no file.")) }
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // Without this a 404 body downloads "successfully" and fails later inside
                // ditto, where the error says nothing about what went wrong.
                Task { @MainActor in
                    onFailure(InstallError.downloadFailed("The download failed with HTTP \(http.statusCode)."))
                }
                return
            }

            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(assetName)
            do {
                try? FileManager.default.removeItem(at: zipURL)
                try FileManager.default.moveItem(at: temporaryURL, to: zipURL)
            } catch {
                Task { @MainActor in onFailure(error) }
                return
            }

            Task { @MainActor in
                do {
                    try launchUpdateScript(zipURL: zipURL, onFailure: onFailure)
                } catch {
                    onFailure(error)
                }
            }
        }.resume()
    }

    /// The shell script Terminal runs to perform the swap. Internal for testing.
    static func scriptContents(appPath: String, zipPath: String, pid: Int32) -> String {
        """
        #!/bin/zsh
        set -e
        echo "Updating Marginal…"
        # Wait for the app to fully quit.
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        STAGING=$(mktemp -d)
        /usr/bin/ditto -x -k "\(zipPath)" "$STAGING"
        NEW_APP=$(/bin/ls -d "$STAGING"/*.app | head -1)
        rm -rf "\(appPath)"
        /usr/bin/ditto "$NEW_APP" "\(appPath)"
        /usr/bin/xattr -dr com.apple.quarantine "\(appPath)" 2>/dev/null || true
        rm -rf "$STAGING" "\(zipPath)"
        /usr/bin/open "\(appPath)"
        echo "Done — Marginal is up to date. You can close this window."
        rm -- "$0"
        """
    }

    /// Strips `com.apple.quarantine` from a file this app just wrote.
    ///
    /// The handoff script is created by a sandboxed app, so macOS marks it quarantined. An
    /// unsigned quarantined `.command` is refused by Gatekeeper with "update-marginal.command
    /// is damaged and can't be opened" — which reads like a corrupt file and is nothing of the
    /// sort. The script also deletes itself once it has run, so the attribute buys no safety
    /// here; it only stops the update.
    ///
    /// Best effort on purpose: if the attribute is absent `removexattr` sets ENOATTR, and
    /// failing the whole update over that would be worse than trying to open the script.
    private static func clearQuarantine(at url: URL) {
        _ = url.withUnsafeFileSystemRepresentation { path in
            path.map { removexattr($0, "com.apple.quarantine", 0) }
        }
    }

    private static func launchUpdateScript(zipURL: URL, onFailure: @escaping @MainActor (Error) -> Void) throws {
        let script = scriptContents(
            appPath: Bundle.main.bundlePath,
            zipPath: zipURL.path,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("update-marginal.command")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        clearQuarantine(at: scriptURL)

        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [scriptURL],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            Task { @MainActor in
                if let error {
                    onFailure(error)
                } else {
                    // The script waits for this process to exit before swapping the bundle.
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
