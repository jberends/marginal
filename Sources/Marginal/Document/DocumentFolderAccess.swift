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
        // Live path: a directory NSOpenPanel pre-pointed at the folder. (Whether to also copy
        // externally-linked images is chosen in the Save panel's own accessory checkbox, not here,
        // so this panel is purely about granting folder write access.)
        self.init(defaults: defaults) { folder, reason in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = "Grant Access"
            panel.message = reason
            guard panel.runModal() == .OK else { return nil }
            return panel.url
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

    /// Resolves a stored bookmark for the given key into a usable URL, or nil if none/stale.
    /// `isDirectory` only affects the synthetic session-grant fallback URL (no filesystem probe
    /// happens either way) -- pass `true` for folders, `false` for individual files. The returned
    /// URL has NOT had security scope started; use `withAccess`/`beginRetainedAccess`.
    private func resolvedURL(forKey k: String, isDirectory: Bool) -> URL? {
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
            return URL(fileURLWithPath: k, isDirectory: isDirectory)
        }
        return nil
    }

    /// Resolves a stored bookmark for `folder` into a usable URL, or nil if none/stale.
    /// The returned URL has NOT had security scope started; use `withAccess`.
    func writableURL(forFolder folder: URL) -> URL? {
        resolvedURL(forKey: key(for: folder), isDirectory: true)
    }

    /// Creates a security-scoped bookmark for `url` -- a file the app currently has read access
    /// to, e.g. one just accepted via a Finder drag -- and persists it in the same store folder
    /// bookmarks use, keyed by its standardized path. Lets `beginRetainedAccess(to:)` reopen
    /// access to this exact file on a later launch/reopen, never prompting.
    func storeSecurityScopedBookmark(for url: URL) {
        let k = key(for: url)
        if let data = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil) {
            setBookmark(data, for: k)
        } else {
            // Mirrors acquireAccess's sessionGranted fallback: a real security-scoped bookmark
            // can't be made for every URL (e.g. a synthetic path in tests, or one outside any
            // active security-scoped grant), so remember the grant in-memory to keep
            // same-session reads working.
            sessionGranted.insert(k)
        }
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
        beginRetainedAccess(to: folder, isDirectory: true)
    }

    /// Generalized form of `beginRetainedAccess(toFolder:)`: opens (and holds open) a security
    /// scope for `url`'s stored bookmark -- a folder or an individual file (e.g. a Finder-dragged
    /// linked image bookmarked via `storeSecurityScopedBookmark`) -- for the life of the document.
    /// Never prompts: no stored bookmark for `url` simply returns `false`.
    @discardableResult
    func beginRetainedAccess(to url: URL) -> Bool {
        beginRetainedAccess(to: url, isDirectory: false)
    }

    private func beginRetainedAccess(to url: URL, isDirectory: Bool) -> Bool {
        let k = key(for: url)
        if retainedScopedURLs[k] != nil { return true }
        if let resolved = resolvedURL(forKey: k, isDirectory: isDirectory) {
            // As with `withAccess`, a `false` return here isn't a failure -- it just means this
            // URL didn't need a security scope opened (see the class-level doc). Either way it's
            // now usable, so it's retained.
            _ = resolved.startAccessingSecurityScopedResource()
            retainedScopedURLs[k] = resolved
            return true
        }
        // No bookmark for the exact path. A grant for an ANCESTOR folder (e.g. the user's Home,
        // or some parent directory) covers everything nested under it, but only an exact-path
        // bookmark was ever stored for that ancestor -- so walk up looking for one. Retain the
        // scope on the ancestor itself (not a synthetic bookmark for `url`, which was never
        // granted), keyed by `url`'s own key so a later `beginRetainedAccess`/`endRetainedAccess`
        // for this exact `url` still finds/clears it.
        //
        // Walk the absolute path STRING, not URL.deletingLastPathComponent(): that method never
        // reaches a fixpoint for a non-absolute URL (it prepends "../" forever), which pinned the
        // app at 100% CPU on open. `(NSString).deletingLastPathComponent` on an absolute path is a
        // strictly-shrinking sequence that always terminates at "/".
        var candidatePath = (url.standardizedFileURL.path as NSString).deletingLastPathComponent
        while candidatePath != "/" && !candidatePath.isEmpty {
            let candidate = URL(fileURLWithPath: candidatePath, isDirectory: true)
            if let resolvedAncestor = resolvedURL(forKey: key(for: candidate), isDirectory: true) {
                _ = resolvedAncestor.startAccessingSecurityScopedResource()
                retainedScopedURLs[k] = resolvedAncestor
                return true
            }
            let parentPath = (candidatePath as NSString).deletingLastPathComponent
            if parentPath == candidatePath { break }  // defensive fixpoint guard
            candidatePath = parentPath
        }
        return false  // reached root, no ancestor grant
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
