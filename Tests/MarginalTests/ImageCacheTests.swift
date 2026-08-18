import XCTest
import AppKit
@testable import Marginal

/// `ImageCache.image(at:)` must never permanently remember a failed decode -- the "click the
/// unavailable placeholder to grant folder access" flow (see `DocumentViewController
/// .markdownTextViewRequestImageAccess`) depends on a subsequent read of the SAME URL succeeding
/// once access is granted / the file appears, with nothing else needing to evict a cache entry
/// first.
@MainActor
final class ImageCacheTests: XCTestCase {

    func testImageAtReturnsNilForMissingFileThenLoadsOnceTheFileAppears() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("image-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("photo.png")

        XCTAssertNil(ImageCache.shared.image(at: url), "no file on disk yet -- must fail to decode, not crash")

        try ImageInsertionTests.onePixelPNG().write(to: url)

        let image = ImageCache.shared.image(at: url)
        XCTAssertNotNil(image, "once the file exists, a fresh call must decode it -- the earlier failure must not have been cached")
    }

    func testImageAtDecodesSuccessfullyOnFirstCall() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("image-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("photo.png")
        try ImageInsertionTests.onePixelPNG().write(to: url)

        XCTAssertNotNil(ImageCache.shared.image(at: url))
    }
}
