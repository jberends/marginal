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

        var errorDescription: String? {
            switch self {
            case .noDownloadableAsset:
                return "The latest release has no downloadable app archive."
            case .downloadFailed(let reason):
                return reason
            }
        }
    }

    /// Downloads the release's zip and hands off to the update script. On success the
    /// app terminates; the completion is only called on failure.
    static func downloadAndInstall(_ release: UpdateChecker.Release, onFailure: @escaping @MainActor (Error) -> Void) {
        guard let asset = release.appZipAsset, let url = URL(string: asset.browserDownloadUrl) else {
            onFailure(InstallError.noDownloadableAsset)
            return
        }
        let assetName = asset.name
        URLSession.shared.downloadTask(with: url) { temporaryURL, _, error in
            Task { @MainActor in
                if let error {
                    onFailure(InstallError.downloadFailed(error.localizedDescription))
                    return
                }
                guard let temporaryURL else {
                    onFailure(InstallError.downloadFailed("The download produced no file."))
                    return
                }
                do {
                    let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(assetName)
                    try? FileManager.default.removeItem(at: zipURL)
                    try FileManager.default.moveItem(at: temporaryURL, to: zipURL)
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

    private static func launchUpdateScript(zipURL: URL, onFailure: @escaping @MainActor (Error) -> Void) throws {
        let script = scriptContents(
            appPath: Bundle.main.bundlePath,
            zipPath: zipURL.path,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("update-marginal.command")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

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
