import XCTest
@testable import Marginal

final class MarkdownParserInlineStyleTests: XCTestCase {

    func testParsesBoldWithAsterisks() {
        let text = "Hello **world** today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .bold)
        XCTAssertEqual(String(text[spans[0].contentRange]), "world")
    }

    func testParsesBoldWithUnderscores() {
        let text = "Hello __world__ today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .bold)
    }

    func testParsesItalicWithSingleAsterisk() {
        let text = "Hello *world* today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .italic)
        XCTAssertEqual(String(text[spans[0].contentRange]), "world")
    }

    func testParsesItalicWithSingleUnderscore() {
        let text = "Hello _world_ today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .italic)
    }

    func testBoldTakesPrecedenceAndTripleDelimiterStillYieldsABoldSpan() {
        let text = "Hello ***world*** today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertTrue(spans.contains { $0.kind == .bold })
    }

    func testParsesStrikethrough() {
        let text = "This is ~~wrong~~ right"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .strikethrough)
    }

    func testParsesUnderlineHTMLTag() {
        let text = "This is <u>underlined</u> text"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .underline)
        XCTAssertEqual(String(text[spans[0].contentRange]), "underlined")
    }

    func testPlainTextHasNoSpans() {
        let text = "Just a normal sentence."
        XCTAssertTrue(MarkdownParser.parseInlineStyles(in: text).isEmpty)
    }

    func testMultipleNonOverlappingSpansAreAllFound() {
        let text = "**one** and *two* and ~~three~~"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 3)
    }
}
