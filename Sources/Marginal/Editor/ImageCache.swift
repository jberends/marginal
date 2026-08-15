import AppKit

/// Decodes and caches images drawn inline by `MarkdownLayoutManager`. Keyed by the resolved file
/// path plus its modification date, so replacing or editing the file on disk (which bumps the
/// modification date) invalidates the stale entry and forces a fresh decode -- an edited image
/// shows its new contents rather than the old cached bitmap.
///
/// `@MainActor` because it is only ever touched from `drawBackground(forGlyphRange:at:)`, which
/// runs on the main thread; this keeps the dictionary access free of locking.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private struct Key: Hashable {
        let path: String
        let mtime: TimeInterval
    }

    private var cache: [Key: NSImage] = [:]

    /// Returns a decoded image for `url`, decoding (and caching) on first use. Returns nil when the
    /// file is missing or cannot be decoded, so callers can simply draw nothing.
    func image(at url: URL) -> NSImage? {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let key = Key(path: url.standardizedFileURL.path, mtime: mtime)
        if let hit = cache[key] { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[key] = image
        return image
    }
}
