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

final class MarkdownParserHeaderAndListTests: XCTestCase {

    func testParsesH1Header() {
        let text = "# Title\nBody text"
        let headers = MarkdownParser.parseHeaders(in: text)
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers[0].level, 1)
        XCTAssertEqual(String(text[headers[0].contentRange]), "Title")
    }

    func testParsesH2ThroughH6() {
        for level in 2...6 {
            let marker = String(repeating: "#", count: level)
            let text = "\(marker) Heading\nmore"
            let headers = MarkdownParser.parseHeaders(in: text)
            XCTAssertEqual(headers.count, 1, "level \(level)")
            XCTAssertEqual(headers.first?.level, level)
        }
    }

    func testSevenHashesIsNotAHeader() {
        XCTAssertTrue(MarkdownParser.parseHeaders(in: "####### Not a header").isEmpty)
    }

    func testHashWithoutSpaceIsNotAHeader() {
        XCTAssertTrue(MarkdownParser.parseHeaders(in: "#NotAHeader").isEmpty)
    }

    func testParsesUnorderedListWithHyphen() {
        let text = "- first item\n- second item"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].kind, .unordered)
        XCTAssertEqual(String(text[items[0].contentRange]), "first item")
    }

    func testParsesUnorderedListWithAsteriskAndPlus() {
        let items = MarkdownParser.parseListItems(in: "* one\n+ two")
        XCTAssertEqual(items.count, 2)
    }

    func testParsesOrderedList() {
        let text = "1. first\n2. second\n10. tenth"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].kind, .ordered(number: 1))
        XCTAssertEqual(items[2].kind, .ordered(number: 10))
    }

    func testPlainLineIsNotAListItem() {
        XCTAssertTrue(MarkdownParser.parseListItems(in: "Just a normal sentence.").isEmpty)
    }
}

final class MarkdownParserLinkTests: XCTestCase {

    func testParsesSingleLink() {
        let text = "Check [this site](https://example.com) out"
        let links = MarkdownParser.parseLinks(in: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(String(text[links[0].textRange]), "this site")
        XCTAssertEqual(links[0].url, "https://example.com")
    }

    func testParsesMultipleLinks() {
        let text = "[one](https://a.com) and [two](https://b.com)"
        XCTAssertEqual(MarkdownParser.parseLinks(in: text).count, 2)
    }

    func testTextWithoutLinksReturnsEmpty() {
        XCTAssertTrue(MarkdownParser.parseLinks(in: "No links here.").isEmpty)
    }
}

final class MarkdownParserInlineCodeTests: XCTestCase {

    func testParsesInlineCode() {
        let text = "Use `npm install` to install"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .code)
        XCTAssertEqual(String(text[spans[0].contentRange]), "npm install")
    }

    func testMarkdownInsideInlineCodeDoesNotAlsoMatchAsOtherStyles() {
        let text = "`**not bold** and *not italic*`"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1, "The whole backtick span should win; asterisks inside must not also parse as bold/italic")
        XCTAssertEqual(spans[0].kind, .code)
    }
}
