import XCTest
import AppKit
@testable import Marginal

final class DocumentViewControllerTests: XCTestCase {

    func testCopyCurrentSelectionAsMarkdownPutsRawTextOnPasteboard() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")
        viewController.textView.setSelectedRange(NSRange(location: 6, length: 9)) // "**world**"

        viewController.copyCurrentSelectionAsMarkdown()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**world**")
    }

    func testToggleShowSourceRendersPlainMonospaceText() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("# Title\n**bold**")

        viewController.toggleShowSource()

        let font = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
    }

    func testToggleShowSourceTwiceRestoresStyledRendering() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("**bold**")

        viewController.toggleShowSource()
        viewController.toggleShowSource()

        let delimiterFont = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(delimiterFont?.isFixedPitch ?? true)

        // Regression guard: the bold *content* (not a hidden delimiter) must be restored at
        // the real editor font size, not left at the near-invisible hidden-delimiter size a
        // prior bug could leak into the restored render.
        let contentFont = viewController.textView.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(contentFont?.pointSize, 15)
    }
}
