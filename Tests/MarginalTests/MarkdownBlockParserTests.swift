import XCTest
@testable import Marginal

final class MarkdownBlockParserTests: XCTestCase {
    func kinds(_ md: String) -> [BlockKind] { MarkdownBlockParser.parse(md).blocks.map(\.kind) }

    func testEveryBlockKind() {
        let md = """
        # Title

        Body text.

        - one
          - nested
        1. first
        - [x] done task

        > quoted

        ```swift
        let x = 1
        ```

        ---

        | A | B |
        |---|:--:|
        | 1 | 2 |
        """
        let k = kinds(md)
        XCTAssertEqual(k[0], .heading(level: 1, InlineMarkdown.parse("Title")))
        XCTAssertEqual(k[1], .paragraph(InlineMarkdown.parse("Body text.")))
        XCTAssertEqual(k[2], .listItem(style: .bullet, indent: 0, InlineMarkdown.parse("one")))
        XCTAssertEqual(k[3], .listItem(style: .bullet, indent: 1, InlineMarkdown.parse("nested")))
        XCTAssertEqual(k[4], .listItem(style: .ordered, indent: 0, InlineMarkdown.parse("first")))
        XCTAssertEqual(k[5], .listItem(style: .task(done: true), indent: 0, InlineMarkdown.parse("done task")))
        XCTAssertEqual(k[6], .quote(InlineMarkdown.parse("quoted")))
        XCTAssertEqual(k[7], .codeBlock(language: "swift", "let x = 1\n"))
        XCTAssertEqual(k[8], .divider)
        XCTAssertEqual(k[9], .table(alignments: [.left, .center],
                                    header: [InlineMarkdown.parse("A"), InlineMarkdown.parse("B")],
                                    rows: [[InlineMarkdown.parse("1"), InlineMarkdown.parse("2")]]))
    }
    func testUnrecognizedContentSurvivesAsLiteralParagraph() {
        XCTAssertEqual(kinds("<video src=\"x\">"), [.paragraph(InlineMarkdown.parse("<video src=\"x\">"))])
    }
    func testAdjacentPlainLinesJoinIntoOneParagraph() {
        XCTAssertEqual(kinds("line one\nline two"), [.paragraph(InlineMarkdown.parse("line one line two"))])
    }
    func testEmptyDocumentParsesToOneEmptyParagraph() {
        XCTAssertEqual(kinds(""), [.paragraph(InlineText(""))])  // an editor always has a block to type into
    }
}
