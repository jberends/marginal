import XCTest
@testable import Marginal

@MainActor
final class AppDelegateMenuTests: XCTestCase {

    private func viewMenu() -> NSMenu {
        let delegate = AppDelegate()
        let mainMenu = AppDelegate.buildMainMenuForTesting(target: delegate)
        guard let menu = mainMenu.items.compactMap(\.submenu).first(where: { $0.title == "View" }) else {
            XCTFail("no View menu")
            return NSMenu()
        }
        return menu
    }

    func testViewMenuCarriesAllThreeModesWithCommandOptionDigits() {
        let items = viewMenu().items.filter { $0.action == #selector(DocumentViewController.selectEditorMode(_:)) }
        XCTAssertEqual(items.map(\.title), ["Code", "Live", "Preview"])
        XCTAssertEqual(items.map(\.keyEquivalent), ["1", "2", "3"])
        XCTAssertEqual(items.map(\.tag), [0, 1, 2])
        for item in items {
            XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option], item.title)
        }
    }

    // ⌘1–⌘9 must stay with tab switching — the mode items must never claim a bare ⌘digit.
    // Scoped to 1...9 (not "any digit"): ⌘0 is intentionally claimed by View > Actual Size,
    // the standard macOS zoom-reset shortcut, and was never a tab shortcut to begin with
    // (tabs are numbered 1-9), so it must not trip this check.
    func testTabShortcutsAreNotStolen() {
        let delegate = AppDelegate()
        let mainMenu = AppDelegate.buildMainMenuForTesting(target: delegate)
        let bareCommandDigits = mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .filter { item in
                guard item.keyEquivalentModifierMask == [.command], let digit = Int(item.keyEquivalent) else { return false }
                return (1...9).contains(digit)
            }
        XCTAssertEqual(bareCommandDigits.count, 9)
        for item in bareCommandDigits {
            XCTAssertTrue(item.title.hasPrefix("Select Tab"), item.title)
        }
    }

    func testViewMenuCarriesZoomItems() {
        let titles = viewMenu().items.map(\.title)
        XCTAssertTrue(titles.contains("Zoom In"), "\(titles)")
        XCTAssertTrue(titles.contains("Zoom Out"), "\(titles)")
        XCTAssertTrue(titles.contains("Actual Size"), "\(titles)")
    }
}
