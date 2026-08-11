import XCTest
@testable import Marginal

final class MarkdownSerializerTests: XCTestCase {
    func testCanonicalOutputAndLineMap() {
        let doc = BlockDocument(blocks: [
            Block(kind: .heading(level: 2, InlineText("H"))),
            Block(kind: .listItem(style: .ordered, indent: 0, InlineText("a"))),
            Block(kind: .listItem(style: .ordered, indent: 0, InlineText("b"))),
        ])
        let (md, map) = MarkdownSerializer.serialize(doc)
        XCTAssertEqual(md, "## H\n\n1. a\n2. b\n")
        XCTAssertEqual(map[doc.blocks[0].id], 1...1)
        XCTAssertEqual(map[doc.blocks[1].id], 3...3)
        XCTAssertEqual(map[doc.blocks[2].id], 4...4)
    }
    func testConsecutiveListItemsGetNoBlankLineBetween() {
        let doc = BlockDocument(blocks: [
            Block(kind: .listItem(style: .bullet, indent: 0, InlineText("a"))),
            Block(kind: .listItem(style: .bullet, indent: 1, InlineText("b"))),
        ])
        XCTAssertEqual(MarkdownSerializer.serialize(doc).markdown, "- a\n  - b\n")
    }
    func testTableSerializesWithAlignmentRow() {
        let doc = BlockDocument(blocks: [Block(kind: .table(
            alignments: [.left, .right], header: [InlineText("A"), InlineText("B")],
            rows: [[InlineText("1"), InlineText("2")]]))])
        XCTAssertEqual(MarkdownSerializer.serialize(doc).markdown, "| A | B |\n|---|---:|\n| 1 | 2 |\n")
    }
    // The two round-trip laws from the spec:
    func testSerializeParseIsIdentityOnDocuments() {
        let md = "# T\n\nBody **b**.\n\n- one\n- [ ] task\n\n> q\n\n```swift\nlet x = 1\n```\n\n---\n\n| A |\n|---|\n| 1 |\n"
        let doc = MarkdownBlockParser.parse(md)
        XCTAssertEqual(MarkdownBlockParser.parse(MarkdownSerializer.serialize(doc).markdown).blocks.map(\.kind),
                       doc.blocks.map(\.kind))
    }
    /// Blocking-2 regression: a table cell containing a literal `|` must survive a full
    /// parse -> serialize -> parse round trip with the same cell contents and column count.
    /// Before the fix, `rowLine` emitted the cell's `|` verbatim, so re-parsing saw it as an
    /// extra column separator; the parser then clamps body cells to the header's column count,
    /// silently dropping the last cell ("z" in the repro below).
    func testTableCellContainingPipeSurvivesRoundTrip() {
        let source = "| a | b |\n|---|---|\n| x \\| y | z |\n"
        let doc = MarkdownBlockParser.parse(source)
        guard case .table(_, _, let rows) = doc.blocks[0].kind else {
            return XCTFail("expected a table, got \(doc.blocks[0].kind)")
        }
        XCTAssertEqual(rows[0].map(\.plainText), ["x | y", "z"], "expected the escaped pipe to unescape into the cell's plain text")

        let reserialized = MarkdownSerializer.serialize(doc).markdown
        let reparsed = MarkdownBlockParser.parse(reserialized)
        guard case .table(_, _, let roundTrippedRows) = reparsed.blocks[0].kind else {
            return XCTFail("expected a table after round-tripping, got \(reparsed.blocks[0].kind)")
        }
        XCTAssertEqual(roundTrippedRows.count, 1)
        XCTAssertEqual(roundTrippedRows[0].count, 2, "column count must survive the round trip -- \"z\" must not be dropped")
        XCTAssertEqual(roundTrippedRows[0].map(\.plainText), ["x | y", "z"])
    }

    func testParseSerializeIsIdempotentAfterOnePass() {
        let messy = "1) weird\n*  spaced\n#TitleNoSpace\nplain"
        let once = MarkdownSerializer.serialize(MarkdownBlockParser.parse(messy)).markdown
        let twice = MarkdownSerializer.serialize(MarkdownBlockParser.parse(once)).markdown
        XCTAssertEqual(once, twice)
    }
}
