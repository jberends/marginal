import XCTest
import AppKit
@testable import Marginal

@MainActor
final class BlockEditorSmokeTests: XCTestCase {
    func makeEditor(_ md: String) -> (BlockEditorViewController, NSWindow) {
        let vc = BlockEditorViewController(document: MarkdownBlockParser.parse(md), baseFont: .systemFont(ofSize: 16))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 700, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()
        return (vc, window)
    }
    func testEnterMidParagraphSplitsAndFocusMoves() {
        let (vc, _) = makeEditor("alphabeta")
        let firstID = vc.document.blocks[0].id
        vc.focusBlock(firstID, caretOffset: 5)
        (vc.view.window?.firstResponder as? BlockTextView)?.insertNewline(nil)
        XCTAssertEqual(vc.document.blocks.map(\.kind),
                       [.paragraph(InlineText("alpha")), .paragraph(InlineText("beta"))])
        XCTAssertEqual(vc.focusedBlockID, vc.document.blocks[1].id)
    }
    func testTypingShorthandConvertsBlock() {
        let (vc, _) = makeEditor("")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
        guard case .heading(1, _) = vc.document.blocks[0].kind else { return XCTFail("\(vc.document.blocks[0].kind)") }
    }
    func testBackspaceAtStartMerges() {
        let (vc, _) = makeEditor("one\n\ntwo")
        vc.focusBlock(vc.document.blocks[1].id, caretOffset: 0)
        (vc.view.window?.firstResponder as? BlockTextView)?.deleteBackward(nil)
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("onetwo"))])
    }
}
