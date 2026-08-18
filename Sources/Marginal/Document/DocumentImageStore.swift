import Foundation

/// Manages the on-disk lifecycle of images inserted into a document: pasted/dropped image
/// bytes are buffered in a per-document temp directory while the document is untitled, then
/// relocated into a sibling `<doc>.assets/` folder once the document is saved.
@MainActor
final class DocumentImageStore {
    /// Per-document temp buffer for managed images while the document is untitled.
    /// The URL is reserved at init, but the directory itself is only created on disk
    /// the first time a file is actually written into it (see `ensureTemp()`).
    let tempDirectory: URL
    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
        self.tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("marginal-images-\(UUID().uuidString)", isDirectory: true)
    }

    private func ensureTemp() throws {
        if !fm.fileExists(atPath: tempDirectory.path) {
            try fm.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        }
    }

    /// `pasted-YYYYMMDD-HHMMSS.<ext>`, uniquified within `directory` by appending -2, -3, …
    func uniqueFilename(ext: String, now: Date, in directory: URL) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let stamp = fmt.string(from: now)
        let base = "pasted-\(stamp)"
        var candidate = "\(base).\(ext)"
        var n = 2
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(n).\(ext)"
            n += 1
        }
        return candidate
    }

    /// Writes managed bytes into `tempDirectory`, returns the file URL. `ext` already chosen by caller.
    func writeToTemp(data: Data, ext: String, now: Date) throws -> URL {
        try ensureTemp()
        let name = uniqueFilename(ext: ext, now: now, in: tempDirectory)
        let url = tempDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    /// True when `url` lives inside this store's tempDirectory (i.e. a managed temp file).
    func isManagedTemp(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(tempDirectory.standardizedFileURL.path + "/")
    }

    /// Moves each managed temp file into `assetsDir` (created if needed). Returns old→new URL map.
    /// Skips URLs not under tempDirectory. On name clash in assetsDir, uniquifies.
    func relocateTempFiles(_ urls: [URL], into assetsDir: URL, now: Date) throws -> [URL: URL] {
        let managed = urls.filter(isManagedTemp)
        guard !managed.isEmpty else { return [:] }
        if !fm.fileExists(atPath: assetsDir.path) {
            try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        var map: [URL: URL] = [:]
        for url in managed {
            let name = uniqueFilename(ext: url.pathExtension, now: now, in: assetsDir)
            let dest = assetsDir.appendingPathComponent(name)
            try fm.moveItem(at: url, to: dest)
            map[url] = dest
        }
        return map
    }

    /// Copies an externally-linked source file (not a managed temp file) into `assetsDir`
    /// (created if needed), uniquifying the destination name the same way managed relocations
    /// do. The source is left untouched -- unlike `relocateTempFiles`, this is a copy, not a
    /// move, since the original linked file may still be referenced elsewhere.
    func copyExternalFile(at source: URL, into assetsDir: URL, now: Date) throws -> URL {
        if !fm.fileExists(atPath: assetsDir.path) {
            try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        let name = uniqueFilename(ext: source.pathExtension, now: now, in: assetsDir)
        let dest = assetsDir.appendingPathComponent(name)
        try fm.copyItem(at: source, to: dest)
        return dest
    }

    /// Removes tempDirectory. Call when the document closes.
    func cleanupTemp() {
        try? fm.removeItem(at: tempDirectory)
    }
}
