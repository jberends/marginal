// Tests/MarginalTests/MainMenuTests.swift
import XCTest
import AppKit
@testable import Marginal

@MainActor
final class MainMenuTests: XCTestCase {

    private func viewMenu() throws -> NSMenu {
        let menu = AppDelegate.buildMainMenu(target: AppDelegate())
        let item = try XCTUnwrap(menu.items.first { $0.submenu?.title == "View" })
        return try XCTUnwrap(item.submenu)
    }

    func testViewMenuSitsBetweenEditAndWindow() {
        let menu = AppDelegate.buildMainMenu(target: AppDelegate())
        let titles = menu.items.map { $0.submenu?.title ?? "" }
        guard let edit = titles.firstIndex(of: "Edit"),
              let view = titles.firstIndex(of: "View"),
              let window = titles.firstIndex(of: "Window") else {
            return XCTFail("expected Edit, View and Window menus, got \(titles)")
        }
        XCTAssertEqual(view, edit + 1)
        XCTAssertEqual(window, view + 1)
    }

    func testZoomItemsCarryAsciiKeyEquivalentsAndCommandOnly() throws {
        let view = try viewMenu()

        let zoomIn = try XCTUnwrap(view.items.first { $0.title == "Zoom In" })
        XCTAssertEqual(zoomIn.keyEquivalent, "+")
        XCTAssertEqual(zoomIn.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(zoomIn.action, #selector(DocumentViewController.zoomIn(_:)))
        XCTAssertNil(zoomIn.target, "must route through the responder chain")

        let zoomOut = try XCTUnwrap(view.items.first { $0.title == "Zoom Out" })
        // U+002D hyphen-minus, NOT U+2212. keyEquivalent: "−" compiles and never matches.
        XCTAssertEqual(zoomOut.keyEquivalent, "\u{002D}")
        XCTAssertEqual(zoomOut.keyEquivalentModifierMask, [.command])
        XCTAssertEqual(zoomOut.action, #selector(DocumentViewController.zoomOut(_:)))
        XCTAssertNil(zoomOut.target, "must route through the responder chain")

        let actual = try XCTUnwrap(view.items.first { $0.title == "Actual Size" })
        XCTAssertEqual(actual.keyEquivalent, "0")
        XCTAssertEqual(actual.action, #selector(DocumentViewController.actualSize(_:)))
        XCTAssertNil(actual.target, "must route through the responder chain")
    }

    func testActualSizeMatchesTheDocumentedDefaultFontSize() {
        XCTAssertEqual(FontSizing.defaultPointSize, 16)
    }

    func testShowSourceItemIsWiredWithItsExistingShortcut() throws {
        let view = try viewMenu()
        let item = try XCTUnwrap(view.items.first { $0.title == "Show Source" })
        XCTAssertEqual(item.keyEquivalent, "P", "uppercase P is how AppKit spells ⌘⇧P")
        XCTAssertEqual(item.action, #selector(DocumentViewController.toggleShowSource(_:)))
        XCTAssertNil(item.target)
    }

    func testShowSourceCheckmarkFollowsTheControllersState() {
        let controller = DocumentViewController()
        _ = controller.view   // force loadView so textView/statusBar exist
        let item = NSMenuItem(title: "Show Source", action: #selector(DocumentViewController.toggleShowSource(_:)), keyEquivalent: "P")

        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)

        controller.toggleShowSource()
        _ = controller.validateMenuItem(item)
        XCTAssertEqual(item.state, .on)
    }

    func testCharacterAndWordCountItemIsWired() throws {
        let view = try viewMenu()
        let item = try XCTUnwrap(view.items.first { $0.title == "Show Character & Word Count" })
        XCTAssertEqual(item.keyEquivalent, "", "no shortcut was asked for")
        XCTAssertEqual(item.action, #selector(DocumentViewController.toggleCharacterAndWordCount(_:)))
        XCTAssertNil(item.target)
    }

    func testCharacterAndWordCountCheckmarkFollowsTheFocusedWindow() {
        let controller = DocumentViewController()
        _ = controller.view
        let item = NSMenuItem(title: "Show Character & Word Count", action: #selector(DocumentViewController.toggleCharacterAndWordCount(_:)), keyEquivalent: "")

        XCTAssertTrue(controller.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)

        controller.toggleCharacterAndWordCount(nil)
        _ = controller.validateMenuItem(item)
        XCTAssertEqual(item.state, .on)
    }

    private func gesture(_ characters: String, _ flags: NSEvent.ModifierFlags, _ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    /// Which path claims which gesture. The menu and `MarkdownTextView.keyDown` are mutually
    /// exclusive — AppKit offers a key event to the menu first, and `keyDown` only ever sees what
    /// the menu declines — so this is also the no-double-fire guarantee.
    func testTheMenuClaimsEveryGestureExceptCommandEquals() {
        let menu = AppDelegate.buildMainMenu(target: AppDelegate())

        // ⌘⇧= — the "+" the shifted "=" key produces. The visible Zoom In equivalent.
        XCTAssertTrue(menu.performKeyEquivalent(with: gesture("+", [.command, .shift], 24)))
        // ⌘ + numpad "+". AppKit masks out .numericPad before comparing modifier flags, so the
        // plain [.command] item claims it too — measured in the spike, not assumed.
        XCTAssertTrue(menu.performKeyEquivalent(with: gesture("+", [.command, .numericPad], 69)))
        // ⌘- (U+002D hyphen-minus).
        XCTAssertTrue(menu.performKeyEquivalent(with: gesture("\u{002D}", [.command], 27)))
        // ⌘⇧P.
        XCTAssertTrue(menu.performKeyEquivalent(with: gesture("P", [.command, .shift], 35)))

        // ⌘= must NOT be claimed: no menu item holds "=", by choice, so it falls through to
        // MarkdownTextView.keyDown. If this ever starts returning true, someone added an alias
        // item and keyDown's "=" case became dead — which is a decision, not an accident.
        XCTAssertFalse(menu.performKeyEquivalent(with: gesture("=", [.command], 24)))

        // Negative control: ⌘⇧- produces "_" and must match nothing.
        XCTAssertFalse(menu.performKeyEquivalent(with: gesture("_", [.command, .shift], 27)))
    }
}
