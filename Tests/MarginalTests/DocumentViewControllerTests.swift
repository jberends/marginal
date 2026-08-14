import XCTest
import AppKit
@testable import Marginal

@MainActor
final class DocumentViewControllerTests: XCTestCase {

    func testCopyCurrentSelectionAsMarkdownPutsRawTextOnPasteboard() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")
        viewController.textView.setSelectedRange(NSRange(location: 6, length: 9)) // "**world**"

        viewController.copyCurrentSelectionAsMarkdown()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**world**")
    }

    func testCopyCurrentSelectionAsHTMLPutsRenderedHTMLOnPasteboard() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")
        viewController.textView.setSelectedRange(NSRange(location: 0, length: 16))

        viewController.copyCurrentSelectionAsHTML()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "<p>Hello <strong>world</strong></p>")
    }

    func testCopyAsHTMLEmbedsImagesAsDataURIs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let imgURL = dir.appendingPathComponent("MyNote.assets", isDirectory: true).appendingPathComponent("p.png")
        try FileManager.default.createDirectory(at: imgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ImageInsertionTests.onePixelPNG().write(to: imgURL)

        let vc = DocumentViewController()
        let doc = MarkdownDocument()
        doc.fileURL = dir.appendingPathComponent("MyNote.md")
        vc.document = doc
        _ = vc.view
        vc.loadInitialText("![a](MyNote.assets/p.png)")
        vc.textView.setSelectedRange(NSRange(location: 0, length: (vc.textView.string as NSString).length))

        let html = vc.htmlForCopy(of: vc.textView.string)
        XCTAssertTrue(html.contains(#"src="data:image/png;base64,"#), html)
        XCTAssertFalse(html.contains(#"src="MyNote.assets"#), "local path must be replaced by a data URI")
        try? FileManager.default.removeItem(at: dir)
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
        XCTAssertEqual(contentFont?.pointSize, 16)
    }

    func testShowSourceSurvivesSelectionChange() {
        // Regression test: Show Source mode used to desync from the display, because
        // textViewDidChangeSelection() called restyle() unconditionally, silently flipping
        // the view back to styled WYSIWYG on the very next cursor move while isShowingSource
        // stayed true.
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("# Title\n**bold**")

        viewController.toggleShowSource()

        // Simulate a cursor move / selection change while still in Show Source mode.
        viewController.textView.setSelectedRange(NSRange(location: 2, length: 0))
        viewController.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: viewController.textView))

        let font = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false, "Show Source rendering should survive a selection change")
    }

    func testShowSourceSurvivesTextChange() {
        // Regression test: textDidChange() also called restyle() unconditionally, so typing
        // a character while in Show Source silently reverted to styled WYSIWYG rendering.
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("# Title\n**bold**")

        viewController.toggleShowSource()

        viewController.textView.string += "!"
        viewController.textDidChange(Notification(name: NSText.didChangeNotification, object: viewController.textView))

        let font = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false, "Show Source rendering should survive a text change")
    }
}
