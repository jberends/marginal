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
    /// Also guards the two other load-bearing parts of the round-trip: `onDocumentChange` must
    /// fire (the host app persists on this signal), and the selection must survive the
    /// `render(...)` call inside `didToggleStyle` -- `render` replaces the text storage
    /// wholesale, so this pins the ordering of `view.render(...)` then
    /// `view.setSelectedRange(...)` against a future accidental reorder.
    func testToggleStyleBoldOnSelectionTogglesModel() {
        let (vc, _) = makeEditor("ab")
        let blockID = vc.document.blocks[0].id
        vc.focusBlock(blockID, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.setSelectedRange(NSRange(location: 0, length: 1))

        var changeCount = 0
        vc.onDocumentChange = { _ in changeCount += 1 }

        tv?.toggleStyleBold(nil)

        guard case .paragraph(let text) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertTrue(text.runs.contains { $0.text == "a" && $0.style.contains(.bold) },
                      "expected a bold 'a' run, got \(text.runs)")
        XCTAssertEqual(changeCount, 1, "expected onDocumentChange to fire on toggle")
        XCTAssertEqual(tv?.selectedRange(), NSRange(location: 0, length: 1),
                       "expected the selection to survive the re-render")

        tv?.setSelectedRange(NSRange(location: 0, length: 1))
        tv?.toggleStyleBold(nil)

        guard case .paragraph(let text2) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertFalse(text2.runs.contains { $0.text.contains("a") && $0.style.contains(.bold) },
                       "expected bold removed, got \(text2.runs)")
        XCTAssertEqual(changeCount, 2, "expected onDocumentChange to fire again on the second toggle")
        XCTAssertEqual(tv?.selectedRange(), NSRange(location: 0, length: 1),
                       "expected the selection to survive the second re-render")
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

    // MARK: - Task 12: code block card

    func makeCodeEditor(_ code: String) -> (BlockEditorViewController, NSWindow) {
        let doc = BlockDocument(blocks: [Block(kind: .codeBlock(language: nil, code))])
        let vc = BlockEditorViewController(document: doc, baseFont: .systemFont(ofSize: 16))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 700, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()
        return (vc, window)
    }

    /// Enter inside a code block must insert a literal newline into the *same* block instead of
    /// splitting it (`BlockEditEngine.split` is for text blocks with an `InlineText` -- code
    /// blocks are raw strings and stay a single block across Enter).
    func testEnterInCodeBlockInsertsNewlineWithoutSplitting() {
        let (vc, _) = makeCodeEditor("a")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 1)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.insertNewline(nil)
        tv?.insertText("b", replacementRange: tv?.selectedRange() ?? NSRange(location: 0, length: 0))

        XCTAssertEqual(vc.document.blocks.count, 1)
        guard case .codeBlock(_, let code) = vc.document.blocks[0].kind else {
            return XCTFail("expected a codeBlock, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(code, "a\nb")
    }

    /// Backspace at offset 0 of a code block converts it in place to a `.paragraph` holding the
    /// code text -- it must not merge into the previous block the way a normal paragraph would.
    func testBackspaceAtStartOfCodeBlockConvertsToParagraph() {
        let (vc, _) = makeCodeEditor("a")
        vc.focusBlock(vc.document.blocks[0].id, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.deleteBackward(nil)

        XCTAssertEqual(vc.document.blocks.count, 1)
        XCTAssertEqual(vc.document.blocks[0].kind, .paragraph(InlineText("a")))
    }

    // MARK: - Task 13: in-place table editing

    func makeTableEditor() -> (BlockEditorViewController, NSWindow, UUID) {
        let doc = BlockDocument(blocks: [
            Block(kind: .table(
                alignments: [.left, .left],
                header: [InlineText("A"), InlineText("B")],
                rows: [[InlineText("1"), InlineText("2")]]
            ))
        ])
        let vc = BlockEditorViewController(document: doc, baseFont: .systemFont(ofSize: 16))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 700, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()
        return (vc, window, vc.document.blocks[0].id)
    }

    /// Tab from the header's first cell walks header columns before dropping into the body:
    /// header col 0 -> header col 1 -> body row 0, col 0. Verifies focus lands on the actual
    /// text view for that coordinate, not just some non-nil responder.
    func testTableTabNavigatesHeaderIntoBody() {
        let (vc, _, tableID) = makeTableEditor()
        vc.focusTableCell(tableID, TableEditEngine.Cell(row: nil, column: 0))
        XCTAssertNotNil(vc.view.window?.firstResponder as? BlockTextView)

        (vc.view.window?.firstResponder as? BlockTextView)?.insertTab(nil)
        (vc.view.window?.firstResponder as? BlockTextView)?.insertTab(nil)

        let tv = vc.view.window?.firstResponder as? BlockTextView
        guard let tableView = vc.tableView(for: tableID) else { return XCTFail("expected a BlockTableView") }
        let bodyCell = TableEditEngine.Cell(row: 0, column: 0)
        XCTAssertTrue(tv === tableView.textView(for: bodyCell), "expected focus on body cell (0,0)")
    }

    /// Typing into a cell must route `TableEditEngine.updateCell` through `onDocumentChange` --
    /// the document stays the single source of truth, the cell's own text storage is not the
    /// record of truth.
    func testTableCellEditUpdatesDocument() {
        let (vc, _, tableID) = makeTableEditor()
        vc.focusTableCell(tableID, TableEditEngine.Cell(row: 0, column: 1))
        let tv = vc.view.window?.firstResponder as? BlockTextView

        var changeCount = 0
        vc.onDocumentChange = { _ in changeCount += 1 }
        tv?.insertText("x", replacementRange: NSRange(location: 0, length: tv?.string.count ?? 0))

        guard case .table(_, _, let rows) = vc.document.blocks[0].kind else {
            return XCTFail("expected a table, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(rows[0][1].plainText, "x")
        XCTAssertGreaterThanOrEqual(changeCount, 1, "expected onDocumentChange to fire on cell edit")
    }

    /// Tab from the very last cell (last column of the last body row) appends a fresh, all-empty
    /// row to the document's table and moves focus into its first cell.
    func testTableTabFromLastCellAppendsRow() {
        let (vc, _, tableID) = makeTableEditor()
        vc.focusTableCell(tableID, TableEditEngine.Cell(row: 0, column: 1))
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.insertTab(nil)

        guard case .table(_, let header, let rows) = vc.document.blocks[0].kind else {
            return XCTFail("expected a table, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(rows.count, 2, "expected a new row to be appended")
        XCTAssertEqual(rows[1], Array(repeating: InlineText(""), count: header.count),
                       "expected the new row's cells to all be empty")

        guard let tableView = vc.tableView(for: tableID) else { return XCTFail("expected a BlockTableView") }
        let newCell = TableEditEngine.Cell(row: 1, column: 0)
        let focused = vc.view.window?.firstResponder as? BlockTextView
        XCTAssertTrue(focused === tableView.textView(for: newCell), "expected focus to move into the new row's first cell")
    }

    // MARK: - Task 14: whole-block selection escalation

    /// Shift+Down at the last (here, only) visual line of the focused block's text escalates
    /// text selection into whole-block selection spanning the focused block and its downward
    /// neighbor -- routed through `moveDownAndModifySelection` -> the `selectionEscapedBoundary`
    /// delegate hook -> `BlockSelectionController.beginSelection`.
    func testShiftDownAtLastVisualLineEscalatesToBlockSelection() {
        let (vc, _) = makeEditor("alpha\n\nbeta")
        let ids = vc.document.blocks.map(\.id)
        vc.focusBlock(ids[0], caretOffset: 3)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.moveDownAndModifySelection(nil)

        XCTAssertEqual(vc.selectionController.selectedBlockIDs, ids)
    }

    /// Shift+Up at the first visual line escalates upward, selecting the focused block and its
    /// upward neighbor.
    func testShiftUpAtFirstVisualLineEscalatesToBlockSelection() {
        let (vc, _) = makeEditor("alpha\n\nbeta")
        let ids = vc.document.blocks.map(\.id)
        vc.focusBlock(ids[1], caretOffset: 2)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.moveUpAndModifySelection(nil)

        XCTAssertEqual(vc.selectionController.selectedBlockIDs, ids)
    }

    /// Escape while a block's text view is focused selects that whole block (a single-block
    /// selection), routed through `BlockTextView.cancelOperation(_:)` ->
    /// `blockTextViewDidPressEscape`.
    func testEscapeSelectsWholeFocusedBlock() {
        let (vc, _) = makeEditor("alpha\n\nbeta")
        let firstID = vc.document.blocks[0].id
        vc.focusBlock(firstID, caretOffset: 3)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        tv?.cancelOperation(nil)

        XCTAssertEqual(vc.selectionController.selectedBlockIDs, [firstID])
    }

    /// Backspace at offset 0 whose merge target has no inline text (a divider here) cannot merge
    /// -- `BlockEditEngine.backspaceAtStart` carets onto the divider instead, and the controller
    /// must enter whole-block selection on it rather than calling `focusBlock` (there's no text
    /// view to focus).
    func testBackspaceOntoDividerEntersBlockSelectionInsteadOfFocusing() {
        let doc = BlockDocument(blocks: [Block(kind: .divider), Block(kind: .paragraph(InlineText("x")))])
        let vc = BlockEditorViewController(document: doc, baseFont: .systemFont(ofSize: 16))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 700, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()
        let dividerID = doc.blocks[0].id
        let paragraphID = doc.blocks[1].id

        vc.focusBlock(paragraphID, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.deleteBackward(nil)

        XCTAssertEqual(vc.selectionController.selectedBlockIDs, [dividerID])
        XCTAssertNil(vc.view.window?.firstResponder as? BlockTextView, "expected no text view focused")
    }

    /// With a block selection active, ⌫ (routed through `deleteBlockSelection()`) removes exactly
    /// the selected blocks from `document`, clears the selection, and focuses the surviving
    /// neighbor.
    func testDeleteBlockSelectionRemovesBlocksAndFocusesNeighbor() {
        let (vc, _) = makeEditor("alpha\n\nbeta\n\ngamma")
        let ids = vc.document.blocks.map(\.id)
        vc.beginBlockSelection(anchor: ids[1], extendingTo: ids[1])

        vc.deleteBlockSelection()

        XCTAssertEqual(vc.document.blocks.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(vc.selectionController.selectedBlockIDs, [])
        XCTAssertEqual(vc.focusedBlockID, ids[2])
    }

    /// With a block selection active, ⌘C (the `copy(_:)` responder action) puts the selection's
    /// canonical markdown -- exactly `markdownForSelection` -- onto the general pasteboard as
    /// plain text.
    func testCopyBlockSelectionPutsMarkdownOnPasteboard() {
        let (vc, _) = makeEditor("alpha\n\nbeta\n\ngamma")
        let ids = vc.document.blocks.map(\.id)
        vc.beginBlockSelection(anchor: ids[0], extendingTo: ids[1])
        let expected = vc.selectionController.markdownForSelection(in: vc.document)

        vc.copy(nil)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
    }

    /// Any click clears an active block selection and returns to normal text editing --
    /// `BlockTextView.mouseDown(_:)` reports the click to the delegate before falling through to
    /// `super.mouseDown`.
    ///
    /// This drives the delegate hook rather than dispatching a real `mouseDown`: `NSTextView`'s
    /// own `mouseDown` implementation enters AppKit's *modal* mouse-tracking loop, which sits in
    /// `nextEvent(matching:)` waiting for a mouse-up that never arrives in a headless test run --
    /// calling it here hangs the whole suite indefinitely (it did). The production override is a
    /// two-liner (`blockDelegate?.blockTextViewDidReceiveClick(self)` then `super.mouseDown`), so
    /// the only part that can regress is the delegate call this test pins.
    func testClickClearsBlockSelection() {
        let (vc, _) = makeEditor("alpha\n\nbeta")
        let ids = vc.document.blocks.map(\.id)
        vc.beginBlockSelection(anchor: ids[0], extendingTo: ids[1])
        XCTAssertEqual(vc.selectionController.selectedBlockIDs.count, 2)

        vc.focusBlock(ids[0], caretOffset: 0)
        guard let tv = vc.view.window?.firstResponder as? BlockTextView else {
            return XCTFail("expected a focused BlockTextView to click in")
        }
        vc.blockTextViewDidReceiveClick(tv)

        XCTAssertEqual(vc.selectionController.selectedBlockIDs, [])
    }

    /// A real typed keystroke -- dispatched as an actual `NSEvent` through the responder chain,
    /// not the delegate method called directly -- clears an active block selection and lands the
    /// character in the first selected block's text, rather than being silently dropped by
    /// `super.keyDown` (there is no `BlockTextView` in the chain while the controller itself is
    /// first responder during a block selection).
    func testTypingClearsBlockSelection() {
        let (vc, window) = makeEditor("alpha\n\nbeta")
        let ids = vc.document.blocks.map(\.id)
        vc.beginBlockSelection(anchor: ids[0], extendingTo: ids[1])
        XCTAssertEqual(vc.selectionController.selectedBlockIDs.count, 2)
        XCTAssertTrue(vc.view.window?.firstResponder === vc, "expected the controller itself to be first responder during block selection")

        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil,
                                      characters: "x", charactersIgnoringModifiers: "x",
                                      isARepeat: false, keyCode: 7)!
        window.firstResponder?.keyDown(with: event)

        XCTAssertEqual(vc.selectionController.selectedBlockIDs, [])
        guard case .paragraph(let text) = vc.document[ids[0]]?.kind else {
            return XCTFail("expected the first selected block to remain a paragraph")
        }
        XCTAssertEqual(text.plainText, "alphax")
    }

    // MARK: - Task 15: document-level undo

    /// Typing a burst of text into an empty paragraph, then splitting it with Enter, must undo
    /// back through the intermediate (pre-split, post-typing) state to the original empty
    /// document, and redo must replay the split. Drives undo/redo through the exact
    /// `NSUndoManager` the controller registers with (`vc.view.window?.undoManager`), matching
    /// how a real ⌘Z/⌘⇧Z keystroke would reach it -- not by calling any private restore API.
    ///
    /// `groupsByEvent = false` is required here: AppKit's default groups every undo registration
    /// made during one `NSEvent` dispatch into a single step, which would otherwise coalesce
    /// unrelated registrations made back-to-back outside a real run loop (as this test does) into
    /// one undo, making the two-step assertion below flaky. The controller itself sets this the
    /// first time it touches the window's undo manager (see `undoManager_`), so no extra setup is
    /// needed here beyond fetching the same manager instance.
    func testUndoRedoThroughTypingAndSplit() {
        let (vc, window) = makeEditor("")
        let firstID = vc.document.blocks[0].id
        vc.focusBlock(firstID, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView

        // One typing burst: "alpha" typed as a single insertText call, so it coalesces into one
        // undo step regardless of the 1s pause window (no real delay happens in a test).
        tv?.insertText("alpha", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("alpha"))])

        // Split "alpha" into "al" / "pha" with Enter at offset 2 -- a structural op, which always
        // pushes its own undo step regardless of the typing burst still notionally "in progress".
        vc.focusBlock(firstID, caretOffset: 2)
        (vc.view.window?.firstResponder as? BlockTextView)?.insertNewline(nil)
        XCTAssertEqual(vc.document.blocks.map(\.kind),
                       [.paragraph(InlineText("al")), .paragraph(InlineText("pha"))])
        XCTAssertEqual(vc.document.blocks.count, 2)

        let undoManager = window.undoManager
        XCTAssertNotNil(undoManager, "expected the controller to have registered undo steps on the window's undo manager")
        XCTAssertTrue(undoManager?.canUndo ?? false)

        // First undo: revert the split, landing back on the single "alpha" paragraph typed above.
        undoManager?.undo()
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("alpha"))])
        XCTAssertEqual(vc.document.blocks.count, 1)

        // Second undo: revert the whole typing burst, landing back on the original empty paragraph.
        undoManager?.undo()
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText(""))])
        XCTAssertEqual(vc.document.blocks.count, 1)

        // Redo replays the split (through the intermediate "alpha" state).
        XCTAssertTrue(undoManager?.canRedo ?? false)
        undoManager?.redo()
        XCTAssertEqual(vc.document.blocks.map(\.kind), [.paragraph(InlineText("alpha"))])

        undoManager?.redo()
        XCTAssertEqual(vc.document.blocks.map(\.kind),
                       [.paragraph(InlineText("al")), .paragraph(InlineText("pha"))])
        XCTAssertEqual(vc.document.blocks.count, 2)
    }

    /// A style toggle (⌘B) is its own discrete undo step, distinct from surrounding typing bursts
    /// -- undoing it must remove exactly the bold styling and nothing else, leaving the plain
    /// text untouched.
    func testUndoRevertsStyleToggle() {
        let (vc, window) = makeEditor("ab")
        let blockID = vc.document.blocks[0].id
        vc.focusBlock(blockID, caretOffset: 0)
        let tv = vc.view.window?.firstResponder as? BlockTextView
        tv?.setSelectedRange(NSRange(location: 0, length: 1))

        tv?.toggleStyleBold(nil)
        guard case .paragraph(let boldedText) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertTrue(boldedText.runs.contains { $0.text == "a" && $0.style.contains(.bold) })

        window.undoManager?.undo()

        guard case .paragraph(let revertedText) = vc.document.blocks[0].kind else {
            return XCTFail("expected paragraph, got \(vc.document.blocks[0].kind)")
        }
        XCTAssertEqual(revertedText.plainText, "ab")
        XCTAssertFalse(revertedText.runs.contains { $0.text.contains("a") && $0.style.contains(.bold) })
    }
}
