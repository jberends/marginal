import AppKit

/// Stores security-scoped folder bookmarks so Marginal can write image sidecar files next to a
/// document without re-prompting the user every launch. Bookmarks are persisted in `UserDefaults`,
/// keyed by the folder's standardized path.
///
/// Note on "access": `acquireAccess`/`withAccess` gate on whether a usable folder URL could be
/// obtained (via a stored bookmark or a fresh prompt) — not on whether that URL required opening a
/// security scope. Plenty of writable folders (the app's own container, plain temp directories in
/// tests, folders the sandbox already permits) need no scope at all, so
/// `startAccessingSecurityScopedResource()` legitimately returns `false` for them; that is not a
/// permission failure. A genuine permission failure on a folder that *does* need a scope surfaces
/// later as a failed/thrown file write, which callers (e.g. `prepareForSave`) handle themselves.
@MainActor
final class DocumentFolderAccess {
    private let defaults: UserDefaults
    private let promptForFolder: (_ folder: URL, _ reason: String) -> URL?
    private static let bookmarksKey = "imageFolderBookmarks"

    /// In-memory record of folders granted this session. `bookmarkData(options: .withSecurityScope)`
    /// can return nil for URLs that never went through a real security-scoped NSOpenPanel grant
    /// (e.g. plain temp URLs injected by tests), which would otherwise make a fresh grant
    /// unrecoverable without re-prompting. This keeps the live security-scope path intact while
    /// making "grant once, reuse without prompting" deterministic in tests.
    private var sessionGranted: Set<String> = []

    /// Folders whose security scope is being held open for the document's lifetime (read path),
    /// keyed the same way as the bookmark store. Populated by `beginRetainedAccess`, drained by
    /// `endRetainedAccess`.
    private var retainedScopedURLs: [String: URL] = [:]

    init(defaults: UserDefaults = .standard,
         promptForFolder: @escaping (_ folder: URL, _ reason: String) -> URL?) {
        self.defaults = defaults
        self.promptForFolder = promptForFolder
    }

    convenience init(defaults: UserDefaults = .standard) {
        // Live path: a directory NSOpenPanel pre-pointed at the folder.
        self.init(defaults: defaults) { folder, reason in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = "Grant Access"
            panel.message = reason
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    private func bookmarks() -> [String: Data] {
        defaults.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
    }
    private func setBookmark(_ data: Data, for key: String) {
        var b = bookmarks(); b[key] = data; defaults.set(b, forKey: Self.bookmarksKey)
    }
    private func removeBookmark(for key: String) {
        var b = bookmarks(); b.removeValue(forKey: key); defaults.set(b, forKey: Self.bookmarksKey)
    }
    private func key(for folder: URL) -> String { folder.standardizedFileURL.path }

    /// Resolves a stored bookmark for `folder` into a usable URL, or nil if none/stale.
    /// The returned URL has NOT had security scope started; use `withAccess`.
    func writableURL(forFolder folder: URL) -> URL? {
        let k = key(for: folder)
        if let data = bookmarks()[k] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                   options: [.withSecurityScope],
                                   relativeTo: nil,
                                   bookmarkDataIsStale: &stale), !stale {
                return url
            }
            removeBookmark(for: k)
        }
        if sessionGranted.contains(k) {
            return URL(fileURLWithPath: k, isDirectory: true)
        }
        return nil
    }

    /// Resolve-or-prompt. On a fresh grant, stores a bookmark. Returns the folder URL to use,
    /// or nil if the user declined. Security scope is NOT started here.
    func acquireAccess(toFolder folder: URL, reason: String) -> URL? {
        if let existing = writableURL(forFolder: folder) { return existing }
        guard let granted = promptForFolder(folder, reason) else { return nil }
        let grantedKey = key(for: granted)
        sessionGranted.insert(grantedKey)
        if let data = try? granted.bookmarkData(options: [.withSecurityScope],
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) {
            setBookmark(data, for: grantedKey)
        }
        return granted
    }

    /// Brackets start/stopAccessingSecurityScopedResource around `body`, passing the resolved URL.
    /// Returns nil (without calling `body`) only when a usable folder URL could not be *acquired*
    /// (the user declined the prompt, or no bookmark/session grant exists yet). Once a URL is
    /// acquired, `body` always runs — `started` is not a gate, it only records whether a security
    /// scope was actually opened, e.g. it is expected to be `false` for folders that don't need
    /// scoping. See the class-level doc for why that isn't a permission failure.
    func withAccess<T>(toFolder folder: URL, reason: String, _ body: (URL) throws -> T) rethrows -> T? {
        guard let url = acquireAccess(toFolder: folder, reason: reason) else { return nil }
        // `started` is false for URLs that never needed a security scope (e.g. non-bookmarked
        // folders the app can already write to, or plain temp URLs in tests) — that is not a
        // failure, so `body` must still run. Only its value being true governs whether we must
        // later balance it with `stopAccessingSecurityScopedResource()`.
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// Opens (and holds open) a security scope for `folder`'s stored bookmark, for the life of
    /// the document -- covers reads that happen outside any single `withAccess` bracket, e.g.
    /// `ImageCache.image(at:)` decoding a relocated sidecar image after save or on reopen. Under
    /// the sandbox, opening a document only grants access to that one file, never to sibling
    /// files in its folder, so a read of `<doc>.assets/foo.png` needs its own scope.
    ///
    /// Never prompts: if no bookmark exists yet for `folder` (e.g. this machine never granted
    /// access, or the document has never been saved), returns `false` and reads simply degrade
    /// (the image fails to decode) rather than interrupting the user with a folder picker just to
    /// open a document. Idempotent -- calling again for a folder already retained is a no-op that
    /// still returns `true`.
    @discardableResult
    func beginRetainedAccess(toFolder folder: URL) -> Bool {
        let k = key(for: folder)
        if retainedScopedURLs[k] != nil { return true }
        guard let url = writableURL(forFolder: folder) else { return false }
        // As with `withAccess`, a `false` return here isn't a failure -- it just means this URL
        // didn't need a security scope opened (see the class-level doc). Either way the folder is
        // now usable, so it's retained.
        _ = url.startAccessingSecurityScopedResource()
        retainedScopedURLs[k] = url
        return true
    }

    /// Stops accessing every folder scope opened via `beginRetainedAccess` and clears them. Call
    /// once when the document truly closes (see `DocumentViewController.deinit`).
    func endRetainedAccess() {
        for url in retainedScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        retainedScopedURLs.removeAll()
    }
}
