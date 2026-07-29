import XCTest
@testable import Marginal

final class CursorStatusTests: XCTestCase {

    private func model(for text: String) -> MarkdownDocumentModel {
        MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text),
            tables: MarkdownParser.parseTables(in: text),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text)
        )
    }

    private func status(_ text: String, at needle: String) -> CursorStatus {
        let cursor = text.range(of: needle)!.lowerBound
        return CursorStatus.status(for: text, model: model(for: text), cursor: cursor)
    }

    func testLineAndColumnAreOneBased() {
        let text = "first\nsecond line"
        let s = status(text, at: "second")
        XCTAssertEqual(s.line, 2)
        XCTAssertEqual(s.column, 1)

        let s2 = status(text, at: "line")
        XCTAssertEqual(s2.line, 2)
        XCTAssertEqual(s2.column, 8)
    }

    func testHeaderWithBoldBreadcrumb() {
        let text = "# A **bold** title"
        XCTAssertEqual(status(text, at: "bold").path, ["h1", "bold"])
        XCTAssertEqual(status(text, at: "title").path, ["h1"])
    }

    func testPlainParagraphIsText() {
        XCTAssertEqual(status("Just words.", at: "words").path, ["text"])
    }

    func testCodeBlockWithLanguage() {
        let text = "```swift\nlet x = 1\n```\n"
        XCTAssertEqual(status(text, at: "let x").path, ["code (swift)"])
    }

    func testTaskListItem() {
        let text = "- [x] Done thing\n"
        XCTAssertEqual(status(text, at: "Done").path, ["task"])
    }

    func testBlockquote() {
        let text = "> quoted words\n"
        XCTAssertEqual(status(text, at: "quoted").path, ["quote"])
    }

    func testLinkInsideParagraph() {
        let text = "See [the site](https://example.com) now."
        XCTAssertEqual(status(text, at: "the site").path, ["text", "link"])
    }
}
