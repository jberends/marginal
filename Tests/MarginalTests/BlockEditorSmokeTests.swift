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

    // MARK: - Fix round 1

    /// Positive control for Finding 1: typing "- " fresh into an empty paragraph still converts
    /// it to a bullet list item -- shorthand gating must not break the happy path.
    func testTypingBulletShorthandConvertsBlock() {
        let (vc, _) = makeEditor("")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("- ", replacementRange: NSRange(location: 0, length: 0))
        guard case .listItem(.bullet, 0, _) = vc.document.blocks[0].kind else {
            return XCTFail("\(vc.document.blocks[0].kind)")
        }
    }

    /// Finding 1: `applyShorthand` must only fire on an insertion that ends with a shorthand
    /// trigger character, not on a deletion that happens to leave the block's text in a
    /// shorthand-shaped state. Typing "x- " then deleting the "x" leaves the plain text at
    /// "- " via a *deletion*, which must NOT convert the block to a bullet list.
    ///
    /// The deletion is driven via `insertText("", replacementRange:)` rather than
    /// `deleteBackward(_:)` with a non-zero caret: `BlockTextView.doCommand(by:)` has a
    /// pre-existing (unrelated to this fix round) infinite-recursion bug when `deleteBackward`
    /// is invoked with the caret away from the block start -- it falls through to
    /// `super.doCommand(by:)`, which redispatches to the overridden `deleteBackward(_:)`, which
    /// calls `doCommand(by:)` again, forever. `insertText("", replacementRange:)` produces the
    /// same net effect (a real character deletion, routed through `textDidChange` exactly like
    /// `deleteBackward` would) without touching that broken path.
    func testShorthandNotAppliedWhenTriggerTextReachedByDeletion() {
        let (vc, _) = makeEditor("")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("x- ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(vc.document.blocks[0].kind, .paragraph(InlineText("x- ")))

        tv?.insertText("", replacementRange: NSRange(location: 0, length: 1))

        XCTAssertEqual(vc.document.blocks[0].kind, .paragraph(InlineText("- ")))
    }

    /// Finding 2: typing inside a code block must persist into `document`, not be silently
    /// dropped (`BlockKind.replacingInlineText` is a no-op for `.codeBlock`, so the controller
    /// must special-case it and rebuild the case from the text view's raw string).
    func testTypingInCodeBlockPersistsEdit() {
        let (vc, _) = makeEditor("```swift\nx\n```")
        guard case .codeBlock(let language, let code) = vc.document.blocks[0].kind else {
            return XCTFail("expected a codeBlock, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code.trimmingCharacters(in: .whitespacesAndNewlines), "x")

        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 1)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("y", replacementRange: NSRange(location: 1, length: 0))

        guard case .codeBlock(let newLanguage, let newCode) = vc.document.blocks[0].kind else {
            return XCTFail("expected a codeBlock, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(newLanguage, "swift")
        XCTAssertTrue(newCode.contains("y"), "expected inserted 'y' to persist, got \(newCode)")
    }
}
