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
        let viewController = loadedController("**bold**")

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
        let viewController = loadedController("# Title\n**bold**")

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

    // MARK: - Fix round 1 (review findings)

    // List continuation (Return inside a list item) is an editing-surface convenience, not a
    // Live-only one: Code mode restructures the source on Return exactly the same way, and only
    // Preview is read-only. Exercises the real NSTextViewDelegate method, not just the pure
    // ListContinuation.action(forLine:) helper those cases are built on.
    private func assertReturnInsideAListContinuesIt(mode: EditorMode) {
        let controller = loadedController("- first")
        controller.setEditorMode(mode)
        let endOfText = NSRange(location: (controller.textView.string as NSString).length, length: 0)
        controller.textView.setSelectedRange(endOfText)

        let handled = controller.textView(controller.textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertTrue(handled, "\(mode) must handle Return inside a list item")
        XCTAssertEqual(controller.textView.string, "- first\n- ", "\(mode) must continue the list the same way")
    }

    func testListContinuationWorksInLiveMode() {
        assertReturnInsideAListContinuesIt(mode: .live)
    }

    // Regression test for Fix round 1, Finding 1: this guard used to be `editorMode == .live`,
    // silently making Code mode a strictly worse editor for list-writing with no stated design
    // reason -- Code and Live are both "editing surfaces," contrasted with read-only Preview.
    func testListContinuationWorksInCodeModeToo() {
        assertReturnInsideAListContinuesIt(mode: .code)
    }

    // Preview is read-only: if the text view stays first responder after Preview activates,
    // keystrokes keep routing to it via the responder chain even though it's now hidden --
    // silently mutating the document and re-triggering a full webView reload on every keystroke.
    // Needs a real NSWindow: a bare loadView() has no window, so makeFirstResponder calls are
    // no-ops against nil. The window is never shown -- far offscreen, borderless, never ordered
    // front -- the same technique VisualRenderHarnessTests uses so this never touches the real
    // display.
    func testEnteringPreviewResignsFirstResponderFromTheHiddenTextView() {
        let controller = loadedController()
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        XCTAssertTrue(window.makeFirstResponder(controller.textView))
        XCTAssertTrue(window.firstResponder === controller.textView)

        controller.setEditorMode(.preview)

        // Note: hiding scrollView's ancestor chain alone already makes AppKit resign the text
        // view back to the *window* -- so asserting only "not textView" would pass even without
        // the explicit makeFirstResponder(previewWebView) call below, and wouldn't actually prove
        // this fix does anything. The discriminating assertion is that focus specifically landed
        // on the (visible, interactive) web view, not merely off of the hidden text view.
        XCTAssertTrue(
            window.firstResponder === controller.previewWebViewForTesting,
            "Preview must take first responder explicitly, not just rely on the hidden text view falling back to the window"
        )
    }

    // Guards against a stale async completion: leaving Preview kicks off an asynchronous
    // topmostVisibleSourceLine JS round-trip whose completion moves the caret once it resolves.
    // If the user switches Preview -> Live -> Preview -> Live again faster than the first
    // round-trip resolves, that first completion's captured generation must no longer match
    // modeSwitchGeneration by the time it fires, so its answer gets discarded instead of moving
    // the caret based on a switch that's no longer current. A true end-to-end race (two real
    // WKWebView loads/JS round-trips actually overlapping) isn't something this suite can force
    // deterministically -- so this proves the counter mechanism the discard check depends on:
    // every real switch bumps it, so an earlier switch's captured snapshot is provably stale by
    // the time a later switch has run.
    func testRapidModeSwitchesAdvanceTheGenerationCounterPastAnEarlierSwitch() {
        let controller = loadedController()

        controller.setEditorMode(.preview)
        // Leaving Preview is what schedules a topmostVisibleSourceLine query, capturing
        // modeSwitchGeneration's value at this exact point -- reading it right after this call
        // returns the same value that query's closure captured, since nothing else can bump the
        // counter in between.
        controller.setEditorMode(.live)
        let generationCapturedByFirstLeavePreviewQuery = controller.modeSwitchGenerationForTesting

        // Switch away and back fast enough that, in the real scenario this guards against, the
        // first query's JS round-trip has not resolved yet.
        controller.setEditorMode(.preview)
        controller.setEditorMode(.live)

        XCTAssertGreaterThan(
            controller.modeSwitchGenerationForTesting,
            generationCapturedByFirstLeavePreviewQuery,
            "a later switch must advance the counter past what an earlier switch's in-flight completion captured"
        )
    }

    // MARK: - Fix round 2 (Task 10 review findings)

    /// A document ending in "\n" has one more blank visual line with no character index of its
    /// own -- TextKit represents it only as `extraLineFragmentRect` -- so Code mode's
    /// visible-range walk in `updateGutterLines` never reached it, silently dropping the last
    /// line's number for the common case of any trailing-newline file. Needs a real (offscreen,
    /// never-shown) NSWindow: without one, `view.window` is nil, so `updateCursorChrome`'s
    /// `cursorInText` check is always false and the gutter never populates at all.
    func testCodeModeGutterNumbersTheTrailingBlankLineAfterATrailingNewline() {
        let controller = loadedController("a\nb\n")
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        // Auto Layout constraints are never resolved into real subview frames without an actual
        // display/layout pass -- without this, textView.visibleRect stays a degenerate zero
        // rect and the whole gutter walk below silently produces nothing.
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.makeFirstResponder(controller.textView))

        controller.setEditorMode(.code)
        // End of the trailing "\n" -- the caret sits on the blank third line.
        controller.textView.setSelectedRange(NSRange(location: 4, length: 0))
        controller.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: controller.textView)
        )

        let gutter = controller.gutterViewForTesting as! LineNumberGutterView
        guard let trailingLine = gutter.lines.first(where: { $0.number == 3 }) else {
            return XCTFail("the trailing blank line after a trailing newline must still get a gutter number")
        }
        XCTAssertTrue(trailingLine.isCurrent, "the caret sits on the trailing blank line, so it should read as current")

        var expectedRect = controller.textView.layoutManager!.extraLineFragmentRect
        expectedRect.origin.y += controller.textView.textContainerInset.height
        let expectedCenterY = controller.textView.convert(expectedRect, to: gutter).midY
        XCTAssertEqual(trailingLine.centerY, expectedCenterY, accuracy: 0.01)
    }

    /// Closing the loop on the fix above: a document with no trailing newline must not gain a
    /// phantom extra line just because `extraLineFragmentRect` happens to exist.
    func testCodeModeGutterDoesNotInventATrailingLineWithoutATrailingNewline() {
        let controller = loadedController("a\nb")
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.makeFirstResponder(controller.textView))

        controller.setEditorMode(.code)
        // End of "b" -- no trailing newline, so there is no third line to number.
        controller.textView.setSelectedRange(NSRange(location: 3, length: 0))
        controller.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: controller.textView)
        )

        let gutter = controller.gutterViewForTesting as! LineNumberGutterView
        XCTAssertEqual(gutter.lines.map(\.number), [1, 2], "no trailing newline means no phantom third line")
    }
}
