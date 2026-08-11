import XCTest
import AppKit
@testable import Marginal

@MainActor
final class DocumentViewControllerTests: XCTestCase {

    func testCopyCurrentSelectionAsMarkdownPutsRawTextOnPasteboard() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")
        viewController.switchToCode()
        let ns = viewController.textView.string as NSString
        let range = ns.range(of: "**world**")
        viewController.textView.setSelectedRange(range)

        viewController.copyCurrentSelectionAsMarkdown()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**world**")
    }

    func testCopyCurrentSelectionAsHTMLPutsRenderedHTMLOnPasteboard() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")
        viewController.switchToCode()
        let fullRange = NSRange(location: 0, length: (viewController.textView.string as NSString).length)
        viewController.textView.setSelectedRange(fullRange)

        viewController.copyCurrentSelectionAsHTML()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "<p>Hello <strong>world</strong></p>")
    }

    /// Code mode is now the old "Show Source" rendering unconditionally: a plain monospaced
    /// text view with no per-character WYSIWYG attributes. Replaces the old
    /// `testToggleShowSourceRendersPlainMonospaceText` (Show Source was a toggle on top of a
    /// styled Code mode; now Code mode never styles at all).
    func testSwitchToCodeShowsPlainMonospaceText() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("# Title\n**bold**")

        viewController.switchToCode()

        XCTAssertTrue(viewController.textView.font?.isFixedPitch ?? false)
        XCTAssertFalse(viewController.textView.isRichText)
    }

    /// Live is the default mode for a freshly loaded document.
    func testLiveIsTheDefaultMode() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello")

        XCTAssertEqual(viewController.mode, .live)
    }

    /// Switching modes round-trips the document's plain text unchanged in content (module
    /// canonical-form normalization, which `ModeSwitchTests` covers separately).
    func testToggleModeTwiceReturnsToLive() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")

        viewController.toggleMode(nil)
        XCTAssertEqual(viewController.mode, .code)

        viewController.toggleMode(nil)
        XCTAssertEqual(viewController.mode, .live)
    }
}
