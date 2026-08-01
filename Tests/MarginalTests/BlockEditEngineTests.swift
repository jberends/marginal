import XCTest
@testable import Marginal

final class BlockEditEngineTests: XCTestCase {
    func para(_ s: String) -> Block { Block(kind: .paragraph(InlineMarkdown.parse(s))) }

    func testRow1_EnterMidParagraphSplitsSameKind() {
        let b = para("alphabeta")
        let out = BlockEditEngine.split(BlockDocument(blocks: [b]), at: Caret(blockID: b.id, offset: 5))
        XCTAssertEqual(out.document.blocks.map(\.kind),
                       [.paragraph(InlineText("alpha")), .paragraph(InlineText("beta"))])
        XCTAssertEqual(out.caret, Caret(blockID: out.document.blocks[1].id, offset: 0))
    }
    func testRow4_EnterInsideHeadingYieldsParagraphRemainder() {
        let h = Block(kind: .heading(level: 2, InlineText("ab")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [h]), at: Caret(blockID: h.id, offset: 1))
        XCTAssertEqual(out.document.blocks.map(\.kind),
                       [.heading(level: 2, InlineText("a")), .paragraph(InlineText("b"))])
    }
    func testRow2_BackspaceAtParagraphStartMergesIntoPrevious() {
        let a = para("one"), b = para("two")
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [a, b]), in: b.id)
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText("onetwo"))])
        XCTAssertEqual(out.caret, Caret(blockID: a.id, offset: 3))
    }
    func testRow9_BackspaceAtHeadingStartMergesIntoPrevious() {
        let a = para("p"), h = Block(kind: .heading(level: 1, InlineText("H")))
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [a, h]), in: h.id)
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText("pH"))])
    }
    func testRow10_BackspaceAtListItemStartConvertsInPlace() {
        let a = para("p"), li = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("x")))
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [a, li]), in: li.id)
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText("p")), .paragraph(InlineText("x"))])
        XCTAssertEqual(out.caret, Caret(blockID: li.id, offset: 0))
    }
    func testRow2Edge_BackspaceAfterDividerSelectsNotMerges() {
        let d = Block(kind: .divider), b = para("x")
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [d, b]), in: b.id)
        XCTAssertEqual(out.document.blocks.count, 2, "No merge into a divider")
        XCTAssertEqual(out.caret.blockID, d.id, "Caret target signals the divider is selected")
    }
    func testRow3_ShorthandConversions() {
        for (typed, expected) in [
            ("# ", BlockKind.heading(level: 1, InlineText(""))),
            ("### ", .heading(level: 3, InlineText(""))),
            ("- ", .listItem(style: .bullet, indent: 0, InlineText(""))),
            ("1. ", .listItem(style: .ordered, indent: 0, InlineText(""))),
            ("[] ", .listItem(style: .task(done: false), indent: 0, InlineText(""))),
            ("> ", .quote(InlineText(""))),
            ("```swift", .codeBlock(language: "swift", "")),
            ("---", .divider),
        ] {
            let b = para(typed)
            let out = BlockEditEngine.applyShorthand(BlockDocument(blocks: [b]), in: b.id)
            XCTAssertEqual(out?.document.blocks.first?.kind, expected, typed)
        }
        let noMatch = para("no ")
        XCTAssertNil(BlockEditEngine.applyShorthand(BlockDocument(blocks: [noMatch]), in: noMatch.id))
    }
    func testBackspaceAtDocumentStartIsNoOp() {
        let b = para("x")
        let out = BlockEditEngine.backspaceAtStart(BlockDocument(blocks: [b]), in: b.id)
        XCTAssertEqual(out.document.blocks, [b])
    }
    func testRow5_EnterOnListItemWithContentContinuesList() {
        let li = Block(kind: .listItem(style: .task(done: true), indent: 1, InlineText("ab")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [li]), at: Caret(blockID: li.id, offset: 2))
        XCTAssertEqual(out.document.blocks[1].kind,
                       .listItem(style: .task(done: false), indent: 1, InlineText("")),
                       "New task item is unchecked; style and indent carry over")
    }
    func testRow7_EnterOnEmptyNestedItemOutdents() {
        let li = Block(kind: .listItem(style: .bullet, indent: 2, InlineText("")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [li]), at: Caret(blockID: li.id, offset: 0))
        XCTAssertEqual(out.document.blocks.map(\.kind), [.listItem(style: .bullet, indent: 1, InlineText(""))])
    }
    func testRow7_EnterOnEmptyTopLevelItemBecomesParagraph() {
        let li = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("")))
        let out = BlockEditEngine.split(BlockDocument(blocks: [li]), at: Caret(blockID: li.id, offset: 0))
        XCTAssertEqual(out.document.blocks.map(\.kind), [.paragraph(InlineText(""))])
    }
    func testRow6_IndentCapsAtOneDeeperThanPreviousItem() {
        let a = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("a")))
        let b = Block(kind: .listItem(style: .bullet, indent: 0, InlineText("b")))
        let once = BlockEditEngine.indent(BlockDocument(blocks: [a, b]), blockID: b.id, by: 1)
        XCTAssertEqual(once.document.blocks[1].kind, .listItem(style: .bullet, indent: 1, InlineText("b")))
        let twice = BlockEditEngine.indent(once.document, blockID: b.id, by: 1)
        XCTAssertEqual(twice.document.blocks[1].kind, .listItem(style: .bullet, indent: 1, InlineText("b")),
                       "Cannot indent deeper than previous item + 1")
        let out = BlockEditEngine.indent(twice.document, blockID: b.id, by: -1)
        XCTAssertEqual(out.document.blocks[1].kind, .listItem(style: .bullet, indent: 0, InlineText("b")))
    }
}
