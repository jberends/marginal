import XCTest
@testable import Marginal

@MainActor
final class DocumentImageStoreTests: XCTestCase {
    func testWriteToTempThenIsManaged() throws {
        let store = DocumentImageStore()
        let now = Date(timeIntervalSince1970: 1_755_000_000) // fixed
        let url = try store.writeToTemp(data: Data([1, 2, 3]), ext: "png", now: now)
        XCTAssertTrue(store.isManagedTemp(url))
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("pasted-"))
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
        store.cleanupTemp()
    }

    func testUniqueFilenameCollision() throws {
        let store = DocumentImageStore()
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let dir = store.tempDirectory
        let first = store.uniqueFilename(ext: "png", now: now, in: dir)
        try Data().write(to: dir.appendingPathComponent(first))
        let second = store.uniqueFilename(ext: "png", now: now, in: dir)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.contains("-2."))
        store.cleanupTemp()
    }

    func testRelocateTempFilesIntoAssets() throws {
        let store = DocumentImageStore()
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let img = try store.writeToTemp(data: Data([9]), ext: "png", now: now)
        let assets = FileManager.default.temporaryDirectory
            .appendingPathComponent("assets-\(UUID().uuidString)")
        let map = try store.relocateTempFiles([img], into: assets, now: now)
        let moved = try XCTUnwrap(map[img])
        XCTAssertEqual(moved.deletingLastPathComponent().standardizedFileURL, assets.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: img.path))
        XCTAssertEqual(try Data(contentsOf: moved), Data([9]))
        try? FileManager.default.removeItem(at: assets)
        store.cleanupTemp()
    }

    func testRelocateSkipsNonManaged() throws {
        let store = DocumentImageStore()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside.png")
        try Data([5]).write(to: outside)
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent("a-\(UUID().uuidString)")
        let map = try store.relocateTempFiles([outside], into: assets, now: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(map.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path)) // untouched
        try? FileManager.default.removeItem(at: outside)
        store.cleanupTemp()
    }
}
