import XCTest
import AppKit
@testable import Marginal

/// Task 16: the two-way Live/Code mode switch and canonical document I/O.
@MainActor
final class ModeSwitchTests: XCTestCase {

    private func makeVC(_ markdown: String) -> (DocumentViewController, NSWindow) {
        let vc = DocumentViewController()
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 700, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()
        vc.loadInitialText(markdown)
        return (vc, window)
    }

    /// 1-based line number containing `location` (a UTF-16/NSString character offset), matching
    /// `MarkdownSerializer`'s line-map convention -- computed independently here rather than via
    /// any internal helper, so this test exercises the observable contract only.
    private func lineNumber(atLocation location: Int, in text: String) -> Int {
        let ns = text as NSString
        var line = 1
        var i = 0
        let clamped = min(location, ns.length)
        while i < clamped {
            if ns.character(at: i) == 10 { line += 1 } // "\n"
            i += 1
        }
        return line
    }

    // MARK: - Live -> Code

    func testLiveToCodePutsCaretOnFocusedBlockLine() {
        let (vc, _) = makeVC("# T\n\npara")
        // Blocks: [0] heading "T", [1] paragraph "para".
        let paragraphID = vc.blockEditor.document.blocks[1].id
        vc.blockEditor.focusBlock(paragraphID, caretOffset: 0)

        vc.switchToCode()

        XCTAssertEqual(vc.mode, .code)
        XCTAssertEqual(vc.textView.string, "# T\n\npara\n")
        let caretLine = lineNumber(atLocation: vc.textView.selectedRange().location, in: vc.textView.string)
        XCTAssertEqual(caretLine, 3)
    }

    // MARK: - Code -> Live

    func testCodeToLiveFocusesBlockAtCaretLine() {
        let (vc, _) = makeVC("# T\n\npara")
        vc.switchToCode()
        XCTAssertEqual(vc.textView.string, "# T\n\npara\n")

        // Put the caret inside "para" (line 3).
        let paraLocation = (vc.textView.string as NSString).range(of: "para").location
        vc.textView.setSelectedRange(NSRange(location: paraLocation, length: 0))

        vc.switchToLive()

        XCTAssertEqual(vc.mode, .live)
        guard let focusedID = vc.blockEditor.focusedBlockID else {
            return XCTFail("expected a focused block after switching to live")
        }
        guard case .paragraph(let text) = vc.blockEditor.document[focusedID]?.kind else {
            return XCTFail("expected the focused block to be the paragraph, got \(String(describing: vc.blockEditor.document[focusedID]?.kind))")
        }
        XCTAssertEqual(text.plainText, "para")
    }

    /// The inverse direction's boundary case: caret on line 1 (inside the heading) must focus the
    /// heading block, not the paragraph.
    func testCodeToLiveFocusesHeadingWhenCaretOnFirstLine() {
        let (vc, _) = makeVC("# T\n\npara")
        vc.switchToCode()
        vc.textView.setSelectedRange(NSRange(location: 0, length: 0))

        vc.switchToLive()

        guard let focusedID = vc.blockEditor.focusedBlockID else {
            return XCTFail("expected a focused block after switching to live")
        }
        guard case .heading(1, let text) = vc.blockEditor.document[focusedID]?.kind else {
            return XCTFail("expected the focused block to be the heading, got \(String(describing: vc.blockEditor.document[focusedID]?.kind))")
        }
        XCTAssertEqual(text.plainText, "T")
    }

    // MARK: - Undo resets across a mode switch

    func testUndoStackResetsOnModeSwitch() {
        let (vc, window) = makeVC("alpha")
        let blockID = vc.blockEditor.document.blocks[0].id
        vc.blockEditor.focusBlock(blockID, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(window.undoManager?.canUndo ?? false, "expected a pending undo step before switching modes")

        vc.switchToCode()

        XCTAssertFalse(window.undoManager?.canUndo ?? true, "expected the undo stack to be cleared by the mode switch")
    }

    // MARK: - Document I/O canonicalizes on save

    func testSaveSerializesCanonicalMarkdown() throws {
        let document = MarkdownDocument()
        try document.read(from: "1) x".data(using: .utf8)!, ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        defer { document.windowControllers.first?.window?.close() }

        let data = try document.data(ofType: "net.daringfireball.markdown")

        XCTAssertEqual(String(data: data, encoding: .utf8), "1. x\n")
    }

    /// Saving while in Code mode serializes whatever's currently in the code text view (not a
    /// re-parse-then-reserialize of it) -- Code mode's own text is already the document's source
    /// of truth while active.
    func testSaveInCodeModeUsesCodeTextViewContent() {
        let (vc, _) = makeVC("hello")
        let document = MarkdownDocument()
        document.text = "hello"
        vc.document = document

        vc.switchToCode()
        vc.textView.string = "edited in code mode"
        vc.textDidChange(Notification(name: NSText.didChangeNotification, object: vc.textView))

        XCTAssertEqual(document.text, "edited in code mode")
    }
}
