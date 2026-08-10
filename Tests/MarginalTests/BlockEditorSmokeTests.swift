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
    /// Uses a real `deleteBackward(nil)` with the caret positioned after "x" (not at the block
    /// start) to remove it -- now that fix round 2 has removed `BlockTextView`'s
    /// doCommand/deleteBackward recursion (see `testMidBlockBackspaceDeletesDefaultCharacter`),
    /// this is safe and more honestly exercises the real deletion path than the
    /// `insertText("", replacementRange:)` workaround fix round 1 used while that bug was still
    /// unfixed.
    func testShorthandNotAppliedWhenTriggerTextReachedByDeletion() {
        let (vc, _) = makeEditor("")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.insertText("x- ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(vc.document.blocks[0].kind, .paragraph(InlineText("x- ")))

        tv?.setSelectedRange(NSRange(location: 1, length: 0))
        tv?.deleteBackward(nil)

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

    // MARK: - Fix round 2

    /// Fix round 2 regression test for the recursion crash: `deleteBackward(nil)` with the caret
    /// away from the block's start (offset 3 in "abc") must fall through to `super.deleteBackward`
    /// -- NSTextView's real character-deletion behavior -- instead of recursing through
    /// `doCommand(by:)` forever. Asserts both that this does not crash and that the default
    /// delete actually happened (view text shrinks by one character) without any structural
    /// change to the document (still a single paragraph).
    func testMidBlockBackspaceDeletesDefaultCharacter() {
        let (vc, _) = makeEditor("abc")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 3)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.deleteBackward(nil)

        XCTAssertEqual(tv?.string, "ab")
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("ab"))])
    }

    /// Fix round 2: backspace-at-start (caret at offset 0) must still route to
    /// `blockTextViewDidBackspaceAtStart` -- the block-merge delegate path -- and not fall
    /// through to the default character-delete behavior. Same assertion as
    /// `testBackspaceAtStartMerges`, kept here as an explicit round-2 regression check
    /// alongside `testMidBlockBackspaceDeletesDefaultCharacter`.
    func testBackspaceAtStartStillMergesAfterRecursionFix() {
        let (vc, _) = makeEditor("one\n\ntwo")
        vc.focusBlock(vc.document.blocks[1].id, caretOffset: 0)
        (vc.view.window?.firstResponder as? BlockTextView)?.deleteBackward(nil)
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("onetwo"))])
    }

    // MARK: - Task 11: style shortcuts + autoformat wiring

    /// ⌘B (`toggleStyleBold(_:)`) over a selected range must apply `.bold` to the model's
    /// inline text for that range, and pressing it again over the same selection must remove
    /// it -- the toggle routes through `InlineAutoformat.toggling` on the model, then
    /// re-renders through `BlockViewFactory` so the document stays the single source of truth.
    func testToggleStyleBoldOnSelectionTogglesModel() {
        let (vc, _) = makeEditor("ab")
        let blockID = vc.document.blocks[0].id
        vc.focusBlock(blockID, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.setSelectedRange(NSRange(location: 0, length: 1))

        tv?.toggleStyleBold(nil)

        guard case .paragraph(let text) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertTrue(text.runs.contains { $0.text == "a" && $0.style.contains(.bold) },
                      "expected a bold 'a' run, got \(text.runs)")

        tv?.setSelectedRange(NSRange(location: 0, length: 1))
        tv?.toggleStyleBold(nil)

        guard case .paragraph(let text2) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertFalse(text2.runs.contains { $0.text.contains("a") && $0.style.contains(.bold) },
                       "expected bold removed, got \(text2.runs)")
        XCTAssertEqual(text2.plainText, "ab")
    }

    /// Pins the already-wired live inline autoformat (Task 8's `convertCompletedPattern`,
    /// wired into `didEditInlineText` in Task 10): typing `*i*` character-by-character in an
    /// empty paragraph must convert to an italic "i" run with the delimiters removed, and
    /// leave the caret positioned right after the styled content.
    func testLiveAutoformatItalicConvertsCharByChar() {
        let (vc, _) = makeEditor("")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.insertText("*", replacementRange: NSRange(location: 0, length: 0))
        tv?.insertText("i", replacementRange: NSRange(location: 1, length: 0))
        tv?.insertText("*", replacementRange: NSRange(location: 2, length: 0))

        guard case .paragraph(let text) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(text.plainText, "i")
        XCTAssertTrue(text.runs.contains { $0.text == "i" && $0.style.contains(.italic) },
                      "expected an italic 'i' run, got \(text.runs)")
        XCTAssertEqual(tv?.caretOffset, 1)
    }
}
