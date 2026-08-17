import AppKit

/// Stores security-scoped folder bookmarks so Marginal can write image sidecar files next to a
/// document without re-prompting the user every launch. Bookmarks are persisted in `UserDefaults`,
/// keyed by the folder's standardized path.
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

    /// Brackets start/stopAccessingSecurityScopedResource around `body`, passing the scoped URL.
    /// Returns nil (without calling `body`) if access can't be acquired.
    func withAccess<T>(toFolder folder: URL, reason: String, _ body: (URL) throws -> T) rethrows -> T? {
        guard let url = acquireAccess(toFolder: folder, reason: reason) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
