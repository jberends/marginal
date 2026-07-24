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

    func testTripleAsteriskDelimiterYieldsBoldItalicSpan() {
        let text = "Hello ***world*** today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .boldItalic)
        XCTAssertEqual(String(text[spans[0].contentRange]), "world")
    }

    func testTripleUnderscoreDelimiterYieldsBoldItalicSpan() {
        let text = "Hello ___world___ today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .boldItalic)
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

    // Regression: a bold span whose range fully contains an already-claimed inline-code
    // span was being rejected entirely (isClaimed treated legitimate nesting as a conflict),
    // so the whole bold span silently disappeared. Repro string is the user's exact report.
    func testBoldSpanCanContainNestedInlineCode() {
        let text = "**Repos & branches (both from `dev-gis`):**"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertTrue(spans.contains { $0.kind == .bold }, "Bold span must survive nesting an inline code span")
        XCTAssertTrue(spans.contains { $0.kind == .code })
    }

    // A backslash immediately before a backtick escapes it -- CommonMark's "Escaped Markdown
    // characters" case. The escaped backticks must not be treated as code-span delimiters.
    func testBackslashEscapedBacktickIsNotTreatedAsCodeDelimiter() {
        let text = "\\`This should not be inline code.\\`"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertTrue(spans.isEmpty, "Escaped backticks must not produce a code span")
    }

    // CommonMark: a code span may be delimited by a run of 2+ backticks so its content can
    // contain a shorter (e.g. single) backtick run without ending the span early.
    func testDoubleBacktickCodeSpanCanContainALiteralSingleBacktick() {
        let text = "A code span containing a backtick: ``Use the ` character.``"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .code)
        XCTAssertEqual(String(text[spans[0].contentRange]), "Use the ` character.")
    }

    func testSingleBacktickCodeSpanStillWorks() {
        let text = "Use `npm install` now"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .code)
        XCTAssertEqual(String(text[spans[0].contentRange]), "npm install")
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

    // CommonMark "lazy continuation": a plain line immediately following a list item line (no
    // blank line between them) is part of that item's paragraph, not a separate top-level
    // paragraph -- matches how Notion (and other CommonMark renderers) render the same source.
    func testListItemLazilyContinuesOntoNonBlankFollowingLine() {
        let text = "- one\ncontinued text"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(String(text[items[0].lineRange]), text)
    }

    func testListItemDoesNotContinueAcrossABlankLine() {
        let text = "- one\n\nseparate paragraph"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(String(text[items[0].lineRange]), "- one")
    }

    func testListItemContinuationStopsAtTheNextListMarker() {
        let text = "- one\n- two"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(String(text[items[0].lineRange]), "- one")
        XCTAssertEqual(String(text[items[1].lineRange]), "- two")
    }

    // A marker with no trailing space and no content (just "-" alone on the line) is still a
    // valid, empty list item -- it must not be silently dropped to plain unstyled text.
    func testBareMarkerWithNoTrailingSpaceIsAnEmptyListItem() {
        let text = "- item before\n-\n- item after"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[1].kind, .unordered)
        XCTAssertEqual(String(text[items[1].contentRange]), "")
    }

    func testBareOrderedMarkerWithNoTrailingSpaceIsAnEmptyListItem() {
        let text = "1. item before\n2.\n3. item after"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[1].kind, .ordered(number: 2))
        XCTAssertEqual(String(text[items[1].contentRange]), "")
    }

    func testTopLevelItemHasLevelZero() {
        let items = MarkdownParser.parseListItems(in: "- top level")
        XCTAssertEqual(items[0].level, 0)
    }

    func testTwoSpaceIndentIsLevelOne() {
        let items = MarkdownParser.parseListItems(in: "- one\n  - nested")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].level, 0)
        XCTAssertEqual(items[1].level, 1)
    }

    func testFourSpaceIndentIsLevelTwo() {
        let items = MarkdownParser.parseListItems(in: "- one\n    - double nested")
        XCTAssertEqual(items[1].level, 2)
    }

    func testIndentedMarkerContentRangeExcludesTheIndentation() {
        let text = "  - nested item"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(String(text[items[0].contentRange]), "nested item")
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

final class MarkdownParserBlockquoteTests: XCTestCase {

    func testParsesSingleLineBlockquote() {
        let text = "> This is a quote"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 1)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "This is a quote")
    }

    func testParsesMultiLineBlockquoteAsOneSpanPerLine() {
        let text = "> Line one\n> Line two"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 2)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "Line one")
        XCTAssertEqual(String(text[blockquotes[1].contentRange]), "Line two")
    }

    func testPlainLineIsNotABlockquote() {
        XCTAssertTrue(MarkdownParser.parseBlockquotes(in: "Just a normal sentence.").isEmpty)
    }

    func testNestedMarkerIsNotSpeciallyDetected() {
        // Known v1 limitation: ">> nested" is parsed as ONE blockquote level whose content
        // literally starts with the second ">" -- not detected as a nested level.
        let text = ">> nested"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 1)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "> nested")
    }
}

final class MarkdownParserHorizontalRuleTests: XCTestCase {

    func testParsesThreeHyphens() {
        XCTAssertEqual(MarkdownParser.parseHorizontalRules(in: "---").count, 1)
    }

    func testParsesThreeAsterisks() {
        XCTAssertEqual(MarkdownParser.parseHorizontalRules(in: "***").count, 1)
    }

    func testParsesThreeUnderscores() {
        XCTAssertEqual(MarkdownParser.parseHorizontalRules(in: "___").count, 1)
    }

    func testPlainLineIsNotAHorizontalRule() {
        XCTAssertTrue(MarkdownParser.parseHorizontalRules(in: "Just a normal sentence.").isEmpty)
    }

    func testTwoHyphensIsNotAHorizontalRule() {
        XCTAssertTrue(MarkdownParser.parseHorizontalRules(in: "--").isEmpty)
    }

    func testHorizontalRuleAmongOtherLines() {
        let text = "Above\n---\nBelow"
        let rules = MarkdownParser.parseHorizontalRules(in: text)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(String(text[rules[0].lineRange]), "---")
    }
}

final class MarkdownParserFencedCodeBlockTests: XCTestCase {

    func testParsesPlainFencedCodeBlock() {
        let text = "```\nplain content\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(String(text[blocks[0].contentRange]), "plain content\n")
        XCTAssertNil(blocks[0].language)
    }

    func testParsesFencedCodeBlockWithLanguageTag() {
        let text = "```swift\nlet x = 1\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "swift")
        XCTAssertEqual(String(text[blocks[0].contentRange]), "let x = 1\n")
    }

    func testMarkdownInsideFencedCodeBlockIsNotParsedAsOtherSpans() {
        // This test only proves parseFencedCodeBlocks correctly identifies the block's
        // content range -- MarkdownStyler (a later step) is responsible for not re-parsing
        // that content range as headers/lists/etc.
        let text = "```markdown\n# Not a real heading\n- Not a real list\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(String(text[blocks[0].contentRange]).contains("# Not a real heading"))
    }

    func testUnclosedFenceProducesNoSpan() {
        let text = "```swift\nlet x = 1"
        XCTAssertTrue(MarkdownParser.parseFencedCodeBlocks(in: text).isEmpty)
    }

    func testTextWithoutFencesReturnsEmpty() {
        XCTAssertTrue(MarkdownParser.parseFencedCodeBlocks(in: "Just a normal paragraph.").isEmpty)
    }

    func testMultipleFencedCodeBlocks() {
        let text = "```\nfirst\n```\n\nSome text\n\n```\nsecond\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 2)
    }

    func testLongerOuterFenceIsNotClosedByShorterNestedInnerFence() {
        // A 4-backtick outer fence nesting a complete 3-backtick example: the inner
        // ``` lines must be treated as literal content of the outer block, not as
        // the outer block's close (regression test for premature-close bug).
        let text = "````markdown\n```javascript\nconsole.log(\"x\")\n```\n````\nAfter"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1, "Expected exactly one code block for the outer fence, got \(blocks.count)")
        guard let block = blocks.first else { return }

        let content = String(text[block.contentRange])
        XCTAssertTrue(content.contains("```javascript"), "Inner 3-backtick fence lines must be literal content of the outer block")
        XCTAssertTrue(content.contains("console.log(\"x\")"))
        XCTAssertTrue(content.contains("```"))
        XCTAssertEqual(block.language, "markdown")

        // The closing fence must be the 4-backtick line, not the inner 3-backtick line.
        XCTAssertEqual(String(text[block.closingFenceRange]), "````")

        // Text after the real closing fence must not be swallowed into the block.
        guard let afterRange = text.range(of: "After") else {
            XCTFail("Could not find 'After' in text")
            return
        }
        XCTAssertFalse(block.contentRange.contains(afterRange.lowerBound), "'After' must be outside the code block's content range")
        XCTAssertTrue(afterRange.lowerBound >= block.closingFenceRange.upperBound, "'After' must come after the closing fence")
    }
}

final class MarkdownParserCodeHighlightTests: XCTestCase {

    func testParsesStringLiteral() {
        let code = "let greeting = \"hello\""
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .string })
        let stringToken = tokens.first { $0.kind == .string }!
        XCTAssertEqual(String(code[stringToken.range]), "\"hello\"")
    }

    func testParsesLineCommentWithDoubleSlash() {
        let code = "let x = 1 // a comment"
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
    }

    func testParsesLineCommentWithHash() {
        let code = "x = 1  # a comment"
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
    }

    func testParsesNumber() {
        let code = "let x = 42"
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .number })
    }

    func testHashInsideStringIsNotMistakenForAComment() {
        let code = "let s = \"contains # not a comment\""
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
        XCTAssertTrue(tokens.filter { $0.kind == .comment }.isEmpty, "The # is inside the string, already claimed -- must not also match as a comment")
    }

    func testPlainCodeWithNoTokensReturnsEmpty() {
        XCTAssertTrue(MarkdownParser.parseCodeHighlightTokens(in: "print(x)").isEmpty)
    }
}
