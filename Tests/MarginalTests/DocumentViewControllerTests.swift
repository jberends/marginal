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

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "<p data-line=\"1\">Hello <strong>world</strong></p>")
    }

    // Superseded by testSettingCodeModeRendersMonospaceSourceAtOneSize, which asserts the same
    // thing (and more thoroughly) through the new mode API.

    func testSwitchingToCodeThenBackToLiveRestoresStyledRendering() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("**bold**")

        viewController.setEditorMode(.code)
        viewController.setEditorMode(.live)

        let delimiterFont = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(delimiterFont?.isFixedPitch ?? true)

        // Regression guard: the bold *content* (not a hidden delimiter) must be restored at
        // the real editor font size, not left at the near-invisible hidden-delimiter size a
        // prior bug could leak into the restored render.
        let contentFont = viewController.textView.textStorage?.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        XCTAssertEqual(contentFont?.pointSize, 16)
    }

    func testCodeModeSurvivesSelectionChange() {
        // Regression test: Code mode used to desync from the display, because
        // textViewDidChangeSelection() called restyle() unconditionally, silently flipping
        // the view back to styled WYSIWYG on the very next cursor move while the mode stayed
        // Code.
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("# Title\n**bold**")

        viewController.setEditorMode(.code)

        // Simulate a cursor move / selection change while still in Code mode.
        viewController.textView.setSelectedRange(NSRange(location: 2, length: 0))
        viewController.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: viewController.textView))

        let font = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false, "Code mode rendering should survive a selection change")
    }

    // Superseded by testEditingInCodeModeKeepsCodeRendering, which asserts the same thing (a
    // text change surviving in Code mode) through the new mode API.

    // MARK: - Editor modes

    /// A controller whose starting mode is always `.live`, whatever mode this Mac's real
    /// UserDefaults happens to hold — otherwise every assertion below depends on what the
    /// developer last clicked.
    private func loadedController(_ markdown: String = "# Title\n\nbody text\n") -> DocumentViewController {
        let controller = DocumentViewController()
        _ = controller.view          // force loadView()
        let suite = "DocumentViewControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        controller.editorModeDefaults = defaults
        controller.loadInitialText(markdown)
        return controller
    }

    func testSettingCodeModeRendersMonospaceSourceAtOneSize() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        XCTAssertEqual(controller.editorMode, .code)

        let storage = controller.textView.textStorage!
        var sizes: Set<CGFloat> = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let font = value as? NSFont else { return XCTFail("missing font") }
            XCTAssertTrue(font.isFixedPitch)
            sizes.insert(font.pointSize)
        }
        XCTAssertEqual(sizes.count, 1, "Code mode must not vary font size: \(sizes)")
    }

    func testSettingLiveModeRestoresWysiwygHeadingSize() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        controller.setEditorMode(.live)
        XCTAssertEqual(controller.editorMode, .live)

        let storage = controller.textView.textStorage!
        let headingFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let bodyFont = storage.attribute(.font, at: storage.length - 2, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        XCTAssertGreaterThan(headingFont!.pointSize, bodyFont!.pointSize)
    }

    // The source of truth never changes shape, whatever the mode.
    func testTextStorageStaysTheLiteralSourceInEveryMode() {
        let markdown = "# Title\n\none\ntwo\n"
        let controller = loadedController(markdown)
        for mode in EditorMode.allCases {
            controller.setEditorMode(mode)
            XCTAssertEqual(controller.textView.string, markdown, "\(mode) mutated the storage")
        }
    }

    func testPreviewModeShowsTheWebViewAndHidesTheGutter() {
        let controller = loadedController()
        controller.setEditorMode(.preview)
        XCTAssertEqual(controller.editorMode, .preview)
        XCTAssertFalse(controller.previewWebViewForTesting!.isHidden)
        XCTAssertTrue(controller.gutterViewForTesting.isHidden)
    }

    func testLeavingPreviewRestoresTheEditingSurface() {
        let controller = loadedController()
        controller.setEditorMode(.preview)
        controller.setEditorMode(.live)
        XCTAssertTrue(controller.previewWebViewForTesting!.isHidden)
        XCTAssertFalse(controller.gutterViewForTesting.isHidden)
    }

    // Preview is lazy: a document never previewed pays no web-process cost.
    func testWebViewIsNotCreatedUntilPreviewIsEntered() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        XCTAssertNil(controller.previewWebViewForTesting)
        controller.setEditorMode(.preview)
        XCTAssertNotNil(controller.previewWebViewForTesting)
    }

    func testSelectEditorModeMenuActionUsesTheSendersTag() {
        let controller = loadedController()
        let item = NSMenuItem(title: "Code", action: nil, keyEquivalent: "")
        item.tag = 0
        controller.selectEditorMode(item)
        XCTAssertEqual(controller.editorMode, .code)

        item.tag = 2
        controller.selectEditorMode(item)
        XCTAssertEqual(controller.editorMode, .preview)
    }

    // Switching into Preview triggers an asynchronous load, so the scroll has to be deferred
    // rather than evaluated against a DOM that does not exist yet.
    func testEnteringPreviewDefersTheScrollUntilTheDocumentLoads() {
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        webView.load(markdown: "# T\n\npara\n\n- item\n", title: "t", fontSize: 16, appearance: .light)
        // Still loading: the request must be parked, not dropped and not evaluated.
        webView.requestScrollToSourceLine(3)
        XCTAssertEqual(webView.pendingScrollLineForTesting, 3)
    }

    // A load that arrives after a parked request must invalidate it, so a stale scroll target
    // from the previous document can never land on the new one.
    func testLoadingAgainDiscardsAPendingScroll() {
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        webView.load(markdown: "# A\n\nfirst\n", title: "t", fontSize: 16, appearance: .light)
        webView.requestScrollToSourceLine(3)
        webView.load(markdown: "# B\n\nsecond\n", title: "t", fontSize: 16, appearance: .light)
        XCTAssertNil(webView.pendingScrollLineForTesting)
    }

    func testEditingInCodeModeKeepsCodeRendering() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        controller.textView.setSelectedRange(NSRange(location: controller.textView.string.count, length: 0))
        controller.textView.insertText("more", replacementRange: controller.textView.selectedRange())

        let storage = controller.textView.textStorage!
        let font = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.isFixedPitch, true, "typing must not knock Code mode back to Live")
    }
}
