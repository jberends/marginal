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
    private func tempFile() throws -> URL {
        let dir = try tempFolder()
        let file = dir.appendingPathComponent("image.png")
        try Data().write(to: file)
        return file
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

    // MARK: - beginRetainedAccess / endRetainedAccess (read-path folder scope)

    func testBeginRetainedAccessFalseWithoutPromptingWhenNoBookmarkExists() throws {
        let folder = try tempFolder()
        var promptCount = 0
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in
            promptCount += 1
            return requested
        }
        XCTAssertFalse(access.beginRetainedAccess(toFolder: folder))
        XCTAssertEqual(promptCount, 0, "beginRetainedAccess must never prompt")
    }

    func testBeginRetainedAccessTrueAfterBookmarkGrantedAndIsIdempotent() throws {
        let folder = try tempFolder()
        var promptCount = 0
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in
            promptCount += 1
            return requested
        }
        _ = access.acquireAccess(toFolder: folder, reason: "grant")
        XCTAssertEqual(promptCount, 1)

        XCTAssertTrue(access.beginRetainedAccess(toFolder: folder))
        // Calling again for the same folder must not prompt or otherwise misbehave.
        XCTAssertTrue(access.beginRetainedAccess(toFolder: folder))
        XCTAssertEqual(promptCount, 1, "beginRetainedAccess must never prompt")
    }

    func testEndRetainedAccessClearsRetainedScopesAndIsSafeWhenNothingRetained() throws {
        let folder = try tempFolder()
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in requested }
        // Safe no-op with nothing retained yet.
        access.endRetainedAccess()

        _ = access.acquireAccess(toFolder: folder, reason: "grant")
        XCTAssertTrue(access.beginRetainedAccess(toFolder: folder))
        access.endRetainedAccess()

        // A bookmark still exists after ending retained access, so re-beginning (from the
        // bookmark, without a fresh prompt) still succeeds.
        XCTAssertTrue(access.beginRetainedAccess(toFolder: folder))
    }

    // MARK: - Per-file bookmarks (Finder-dragged linked images)

    func testStoreSecurityScopedBookmarkThenBeginRetainedAccessSucceedsAndEndClears() throws {
        let file = try tempFile()
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in requested }

        access.storeSecurityScopedBookmark(for: file)
        XCTAssertTrue(access.beginRetainedAccess(to: file))

        access.endRetainedAccess()
        // The bookmark/session-grant persists past endRetainedAccess, so re-beginning still
        // succeeds without a fresh grant.
        XCTAssertTrue(access.beginRetainedAccess(to: file))
    }

    func testBeginRetainedAccessToFileFalseWithoutPromptingWhenNoBookmarkExists() throws {
        let file = try tempFile()
        var promptCount = 0
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in
            promptCount += 1
            return requested
        }
        XCTAssertFalse(access.beginRetainedAccess(to: file))
        XCTAssertEqual(promptCount, 0, "beginRetainedAccess(to:) must never prompt")
    }

    // MARK: - Ancestor-folder reactivation (a Home/parent grant covers nested images)

    func testBeginRetainedAccessReactivatesViaAncestorFolderGrant() throws {
        let parent = try tempFolder()
        let nestedDir = parent.appendingPathComponent("sub/dir", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let nestedFile = nestedDir.appendingPathComponent("image.png")
        try Data().write(to: nestedFile)

        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in requested }
        // Grant only the parent folder -- no exact bookmark exists for the nested file.
        _ = access.acquireAccess(toFolder: parent, reason: "grant")

        XCTAssertTrue(access.beginRetainedAccess(to: nestedFile),
                       "a parent-folder grant must reactivate access to a nested file via ancestor walk")

        access.endRetainedAccess()
        // Re-beginning still succeeds after ending: the ancestor bookmark persists.
        XCTAssertTrue(access.beginRetainedAccess(to: nestedFile))
    }

    func testBeginRetainedAccessFalseWhenNoAncestorGrantExistsAnywhere() throws {
        let parent = try tempFolder()
        let nestedFile = parent.appendingPathComponent("sub/image.png")
        try FileManager.default.createDirectory(at: nestedFile.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Data().write(to: nestedFile)

        var promptCount = 0
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in
            promptCount += 1
            return requested
        }
        XCTAssertFalse(access.beginRetainedAccess(to: nestedFile))
        XCTAssertEqual(promptCount, 0, "beginRetainedAccess must never prompt, even walking ancestors")
    }
}
