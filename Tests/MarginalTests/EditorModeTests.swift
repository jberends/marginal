import XCTest
@testable import Marginal

final class EditorModeTests: XCTestCase {

    private func emptyDefaults() -> UserDefaults {
        let suite = "EditorModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToLiveWhenNothingPersisted() {
        XCTAssertEqual(EditorMode.persisted(in: emptyDefaults()), .live)
    }

    func testPersistRoundTripsEveryMode() {
        for mode in EditorMode.allCases {
            let defaults = emptyDefaults()
            mode.persist(in: defaults)
            XCTAssertEqual(EditorMode.persisted(in: defaults), mode, "\(mode) did not round-trip")
        }
    }

    func testUnknownPersistedValueFallsBackToLive() {
        let defaults = emptyDefaults()
        defaults.set("split", forKey: "editorMode")
        XCTAssertEqual(EditorMode.persisted(in: defaults), .live)
    }

    func testDisplayMetadata() {
        XCTAssertEqual(EditorMode.code.title, "Code")
        XCTAssertEqual(EditorMode.live.title, "Live")
        XCTAssertEqual(EditorMode.preview.title, "Preview")
        XCTAssertEqual(EditorMode.code.symbolName, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(EditorMode.live.symbolName, "text.cursor")
        XCTAssertEqual(EditorMode.preview.symbolName, "eye")
        XCTAssertEqual(EditorMode.allCases.map(\.menuKeyEquivalent), ["1", "2", "3"])
    }
}
