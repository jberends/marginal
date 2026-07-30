import XCTest
@testable import Marginal

@MainActor
final class EditorModeControllerTests: XCTestCase {

    /// One ordered event log rather than separate chrome/render arrays, so the tests can pin
    /// the chrome-BEFORE-render contract the protocol documents -- two independent arrays can
    /// only show that both happened, and would pass just as well if the order were swapped.
    private final class HostSpy: EditorModeHost {
        var events: [String] = []
        func renderCode() { events.append("render:code") }
        func renderLive() { events.append("render:live") }
        func renderPreview() { events.append("render:preview") }
        func applyChrome(for mode: EditorMode) { events.append("chrome:\(mode.rawValue)") }
    }

    private func expectedSwitchEvents(to mode: EditorMode) -> [String] {
        ["chrome:\(mode.rawValue)", "render:\(mode.rawValue)"]
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
        XCTAssertTrue(host.events.isEmpty)
    }

    func testActivateAppliesChromeThenRendersOnce() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.activate()
        // Chrome first, then render -- asserted as one sequence, not as two facts.
        XCTAssertEqual(host.events, ["chrome:live", "render:live"])
    }

    // The reason this class exists: exactly one render path runs per event, from one call site.
    func testRenderDispatchesToExactlyOneSurface() {
        for mode in EditorMode.allCases {
            let host = HostSpy()
            let controller = EditorModeController(host: host, defaults: emptyDefaults())
            controller.setMode(mode)
            host.events.removeAll()
            controller.render()
            XCTAssertEqual(host.events, ["render:\(mode.rawValue)"], "\(mode) produced \(host.events)")
        }
    }

    func testSetModeAppliesChromeAndRendersTheNewMode() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.setMode(.preview)
        XCTAssertEqual(controller.mode, .preview)
        XCTAssertEqual(host.events, expectedSwitchEvents(to: .preview))
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
        let defaults = emptyDefaults()
        let controller = EditorModeController(host: host, defaults: defaults)
        controller.setMode(.live)
        XCTAssertTrue(host.events.isEmpty)
        // The no-op path must not persist either.
        XCTAssertNil(defaults.string(forKey: EditorMode.defaultsKey))
    }

    func testEveryOrderedPairOfModesTransitionsCleanly() {
        for from in EditorMode.allCases {
            for to in EditorMode.allCases where to != from {
                let host = HostSpy()
                let controller = EditorModeController(host: host, defaults: emptyDefaults())
                controller.setMode(from)
                host.events.removeAll()
                controller.setMode(to)
                XCTAssertEqual(controller.mode, to)
                XCTAssertEqual(host.events, expectedSwitchEvents(to: to), "\(from) -> \(to)")
            }
        }
    }
}
