import XCTest
@testable import Marginal

@MainActor
final class DocumentFolderAccessTests: XCTestCase {
    private func tempFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func isolatedDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "fa-test-\(UUID().uuidString)")!
        return d
    }

    func testAcquirePromptsWhenNoBookmarkThenReusesWithoutPrompting() throws {
        let folder = try tempFolder()
        var promptCount = 0
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in
            promptCount += 1
            return requested   // user grants the requested folder
        }
        let first = access.acquireAccess(toFolder: folder, reason: "test")
        XCTAssertEqual(first?.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(promptCount, 1)

        // Second acquire for the same folder must resolve the stored bookmark, not prompt again.
        let second = access.acquireAccess(toFolder: folder, reason: "test")
        XCTAssertEqual(second?.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(promptCount, 1, "a stored bookmark must be reused without re-prompting")
    }

    func testAcquireReturnsNilWhenUserDeclines() throws {
        let folder = try tempFolder()
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { _, _ in nil }
        XCTAssertNil(access.acquireAccess(toFolder: folder, reason: "test"))
    }

    func testWithAccessRunsBodyWhenGrantedAndSkipsWhenDeclined() throws {
        let folder = try tempFolder()
        let granting = DocumentFolderAccess(defaults: isolatedDefaults()) { req, _ in req }
        var ran = false
        let result = granting.withAccess(toFolder: folder, reason: "r") { url -> String in
            ran = true
            return url.lastPathComponent
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(result, folder.lastPathComponent)

        let declining = DocumentFolderAccess(defaults: isolatedDefaults()) { _, _ in nil }
        var ranB = false
        let r2 = declining.withAccess(toFolder: folder, reason: "r") { _ in ranB = true; return 1 }
        XCTAssertFalse(ranB)
        XCTAssertNil(r2)
    }
}
