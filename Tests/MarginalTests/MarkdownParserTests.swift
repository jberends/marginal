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

    /// Emphasis composes: bold wrapping a strikethrough must yield *both*, because bold claims
    /// the outer range first and rejecting everything inside it dropped the strikethrough
    /// entirely -- the tildes were hidden and no line was ever drawn.
    func testStrikethroughNestedInsideBoldYieldsBothSpans() {
        let text = "Strikethrough and bold: **~~bold deleted text~~**"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 2, "expected a bold span and a strikethrough span, got \(spans.map(\.kind))")
        XCTAssertTrue(spans.contains { $0.kind == .bold })
        XCTAssertTrue(spans.contains { $0.kind == .strikethrough })
        let struck = spans.first { $0.kind == .strikethrough }
        XCTAssertEqual(struck.map { String(text[$0.contentRange]) }, "bold deleted text")
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

    // Regression: an underscore-containing emoji shortcode alias (very common -- gemoji aliases
    // routinely use snake_case) must not have its underscores misdetected as italic, since this
    // parser doesn't implement CommonMark's intraword-emphasis flanking rules.
    func testEmojiShortcodeUnderscoresAreNotMisdetectedAsItalic() {
        let text = "Done :white_check_mark: today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertTrue(spans.isEmpty, "The shortcode's underscores must not produce a spurious italic span")
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

    func testIncompleteTaskCheckboxIsDetected() {
        let text = "- [ ] Incomplete task"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items[0].taskState, .incomplete)
        XCTAssertEqual(String(text[items[0].taskMarkerRange!]), "[ ] ")
    }

    func testCompletedTaskCheckboxIsDetectedLowercaseAndUppercase() {
        let lower = MarkdownParser.parseListItems(in: "- [x] Done")
        XCTAssertEqual(lower[0].taskState, .complete)
        let upper = MarkdownParser.parseListItems(in: "- [X] Done")
        XCTAssertEqual(upper[0].taskState, .complete)
    }

    func testPlainListItemHasNoTaskState() {
        let items = MarkdownParser.parseListItems(in: "- just a normal item")
        XCTAssertNil(items[0].taskState)
        XCTAssertNil(items[0].taskMarkerRange)
    }

    func testOrderedListItemsNeverGetTaskState() {
        let items = MarkdownParser.parseListItems(in: "1. [ ] not a task, ordered lists don't support checkboxes")
        XCTAssertNil(items[0].taskState)
    }

    func testNestedTaskItemUnderAParentTaskIsDetected() {
        let text = "- [ ] Parent task\n  - [x] Completed child task"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].taskState, .incomplete)
        XCTAssertEqual(items[1].taskState, .complete)
        XCTAssertEqual(items[1].level, 1)
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

    /// Nesting is detected now. This test previously documented the opposite as a known v1
    /// limitation: the whole marker run was not consumed, so ">> nested" came out as one level
    /// whose content literally began with the second ">" -- one bar, and a stray marker sitting
    /// in the text.
    func testNestedMarkersCountAsDepth() {
        let text = ">> nested"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 1)
        XCTAssertEqual(blockquotes[0].depth, 2)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "nested")
    }

    func testSingleMarkerIsDepthOne() {
        let text = "> quoted"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.first?.depth, 1)
        XCTAssertEqual(blockquotes.first.map { String(text[$0.contentRange]) }, "quoted")
    }

    func testThreeLevelsOfNesting() {
        let text = ">>> deep"
        XCTAssertEqual(MarkdownParser.parseBlockquotes(in: text).first?.depth, 3)
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

final class MarkdownParserTableTests: XCTestCase {

    func testBasicTableIsDetected() {
        let text = "| Feature | Supported |\n|---|---|\n| Headings | Yes |"
        let tables = MarkdownParser.parseTables(in: text)
        XCTAssertEqual(tables.count, 1)
        XCTAssertEqual(tables[0].headerRow.pipeRanges.count, 3, "3 pipes bound 2 cells")
        XCTAssertEqual(tables[0].bodyRows.count, 1)
    }

    func testAlignmentMarkersAreParsedPerColumn() {
        let text = "| L | C | R |\n|:---|:---:|---:|\n| a | b | c |"
        let tables = MarkdownParser.parseTables(in: text)
        XCTAssertEqual(tables[0].columnAlignments, [.left, .center, .right])
    }

    func testPlainTextWithPipesButNoSeparatorIsNotATable() {
        let text = "| not | a | table |\nsome other line"
        XCTAssertTrue(MarkdownParser.parseTables(in: text).isEmpty)
    }

    // The user's exact reported case: an escaped pipe inside a cell must not split it into two.
    func testEscapedPipeDoesNotSplitACell() {
        let text = "| Expression | Meaning |\n|---|---|\n| A \\| B | A literal pipe between A and B |"
        let tables = MarkdownParser.parseTables(in: text)
        XCTAssertEqual(tables[0].bodyRows[0].pipeRanges.count, 3, "the escaped pipe must not count as a 4th real pipe")
    }

    // The user's exact reported case: empty cells must not break parsing.
    func testEmptyCellsAreParsedAsZeroWidthCells() {
        let text = "| Column A | Column B | Column C |\n|---|---|---|\n| Value | | Value |\n| | Value | |\n| | | |"
        let tables = MarkdownParser.parseTables(in: text)
        XCTAssertEqual(tables[0].bodyRows.count, 3)
        for row in tables[0].bodyRows {
            XCTAssertEqual(row.pipeRanges.count, 4, "still 3 cells even when some are empty")
        }
    }

    func testTableStopsAtTheFirstNonRowLine() {
        let text = "| a | b |\n|---|---|\n| 1 | 2 |\nplain paragraph, not part of the table"
        let tables = MarkdownParser.parseTables(in: text)
        XCTAssertEqual(tables[0].bodyRows.count, 1)
    }

    func testTwoSeparateTablesAreNotMerged() {
        let text = "| a |\n|---|\n| 1 |\n\n| b |\n|---|\n| 2 |"
        let tables = MarkdownParser.parseTables(in: text)
        XCTAssertEqual(tables.count, 2)
    }
}

final class MarkdownParserEmojiShortcodeTests: XCTestCase {

    func testKnownShortcodeIsRecognized() {
        let text = "Hello :smile: world"
        let spans = MarkdownParser.parseEmojiShortcodes(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].emoji, "😄")
        XCTAssertEqual(String(text[spans[0].fullRange]), ":smile:")
    }

    func testPlusOneShortcodeWithSymbolCharacterIsRecognized() {
        let spans = MarkdownParser.parseEmojiShortcodes(in: "Nice :+1: work")
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].emoji, "👍")
    }

    // The user's exact reported case: an underscore-containing shortcode alias.
    func testUnderscoreContainingShortcodeIsRecognized() {
        let spans = MarkdownParser.parseEmojiShortcodes(in: "Done :white_check_mark:")
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].emoji, "✅")
    }

    func testUnrecognizedColonWrappedTextIsIgnored() {
        let spans = MarkdownParser.parseEmojiShortcodes(in: "This is :not_a_real_emoji_alias: here")
        XCTAssertTrue(spans.isEmpty)
    }

    func testMultipleShortcodesInOneLineAreAllFound() {
        let spans = MarkdownParser.parseEmojiShortcodes(in: ":smile: :rocket: :heart:")
        XCTAssertEqual(spans.map(\.emoji), ["😄", "🚀", "❤️"])
    }
}
