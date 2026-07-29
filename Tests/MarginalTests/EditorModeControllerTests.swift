import XCTest
@testable import Marginal

@MainActor
final class EditorModeControllerTests: XCTestCase {

    private final class HostSpy: EditorModeHost {
        var calls: [String] = []
        var chromeModes: [EditorMode] = []
        func renderCode() { calls.append("code") }
        func renderLive() { calls.append("live") }
        func renderPreview() { calls.append("preview") }
        func applyChrome(for mode: EditorMode) { chromeModes.append(mode) }
    }

    private func emptyDefaults() -> UserDefaults {
        let suite = "EditorModeControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testStartsInThePersistedMode() {
        let defaults = emptyDefaults()
        EditorMode.code.persist(in: defaults)
        let controller = EditorModeController(host: HostSpy(), defaults: defaults)
        XCTAssertEqual(controller.mode, .code)
    }

    func testInitDoesNotRenderUntilActivated() {
        let host = HostSpy()
        _ = EditorModeController(host: host, defaults: emptyDefaults())
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertTrue(host.chromeModes.isEmpty)
    }

    func testActivateAppliesChromeThenRendersOnce() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.activate()
        XCTAssertEqual(host.chromeModes, [.live])
        XCTAssertEqual(host.calls, ["live"])
    }

    // The reason this class exists: exactly one render path runs per event, from one call site.
    func testRenderDispatchesToExactlyOneSurface() {
        for (mode, expected) in [(EditorMode.code, "code"), (.live, "live"), (.preview, "preview")] {
            let host = HostSpy()
            let controller = EditorModeController(host: host, defaults: emptyDefaults())
            controller.setMode(mode)
            host.calls.removeAll()
            controller.render()
            XCTAssertEqual(host.calls, [expected], "\(mode) rendered \(host.calls)")
        }
    }

    func testSetModeAppliesChromeAndRendersTheNewMode() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.setMode(.preview)
        XCTAssertEqual(controller.mode, .preview)
        XCTAssertEqual(host.chromeModes, [.preview])
        XCTAssertEqual(host.calls, ["preview"])
    }

    func testSetModePersistsTheChoice() {
        let defaults = emptyDefaults()
        let controller = EditorModeController(host: HostSpy(), defaults: defaults)
        controller.setMode(.code)
        XCTAssertEqual(EditorMode.persisted(in: defaults), .code)
    }

    // Re-selecting the active mode must not reload Preview or restyle the whole document.
    func testSetModeToTheCurrentModeIsANoOp() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.setMode(.live)
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertTrue(host.chromeModes.isEmpty)
    }

    func testEveryOrderedPairOfModesTransitionsCleanly() {
        for from in EditorMode.allCases {
            for to in EditorMode.allCases where to != from {
                let host = HostSpy()
                let controller = EditorModeController(host: host, defaults: emptyDefaults())
                controller.setMode(from)
                host.calls.removeAll()
                host.chromeModes.removeAll()
                controller.setMode(to)
                XCTAssertEqual(controller.mode, to)
                XCTAssertEqual(host.chromeModes, [to], "\(from) -> \(to)")
                XCTAssertEqual(host.calls.count, 1, "\(from) -> \(to) rendered \(host.calls)")
            }
        }
    }
}
