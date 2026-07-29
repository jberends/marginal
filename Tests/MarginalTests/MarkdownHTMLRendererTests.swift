import XCTest
@testable import Marginal

final class MarkdownHTMLRendererTests: XCTestCase {

    func testBoldRendersAsStrong() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Hello **world**")
        XCTAssertEqual(html, "<p data-line=\"1\">Hello <strong>world</strong></p>")
    }

    func testItalicRendersAsEm() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Hello *world*")
        XCTAssertEqual(html, "<p data-line=\"1\">Hello <em>world</em></p>")
    }

    func testInlineCodeRendersAsCode() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Use `npm install`")
        XCTAssertEqual(html, "<p data-line=\"1\">Use <code>npm install</code></p>")
    }

    func testStrikethroughAndUnderline() {
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "~~gone~~"), "<p data-line=\"1\"><del>gone</del></p>")
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "<u>under</u>"), "<p data-line=\"1\"><u>under</u></p>")
    }

    func testBoldSpanContainingNestedInlineCodeRendersBothCorrectly() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "**Repos & branches (both from `dev-gis`):**")
        XCTAssertEqual(html, "<p data-line=\"1\"><strong>Repos &amp; branches (both from <code>dev-gis</code>):</strong></p>")
    }

    func testLinkRendersAsAnchor() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Check [this](https://example.com) out")
        XCTAssertEqual(html, "<p data-line=\"1\">Check <a href=\"https://example.com\">this</a> out</p>")
    }

    func testHeaderRendersWithCorrectLevel() {
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "# Title"), "<h1 data-line=\"1\">Title</h1>")
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "### Sub"), "<h3 data-line=\"1\">Sub</h3>")
    }

    func testHorizontalRuleRendersAsHr() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Above\n\n---\n\nBelow")
        XCTAssertEqual(html, "<p data-line=\"1\">Above</p>\n<hr data-line=\"3\">\n<p data-line=\"5\">Below</p>")
    }

    func testBlockquoteRendersWithParagraph() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "> quoted text")
        XCTAssertEqual(html, "<blockquote data-line=\"1\"><p>quoted text</p></blockquote>")
    }

    func testUnorderedListRendersAsUl() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "- one\n- two")
        XCTAssertEqual(html, "<ul data-line=\"1\"><li>one</li><li>two</li></ul>")
    }

    func testOrderedListRendersAsOl() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "1. one\n2. two")
        XCTAssertEqual(html, "<ol data-line=\"1\"><li>one</li><li>two</li></ol>")
    }

    func testListItemLazyContinuationJoinsIntoSameListItem() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "- one\ncontinued text")
        XCTAssertEqual(html, "<ul data-line=\"1\"><li>one continued text</li></ul>")
    }

    func testFencedCodeBlockEscapesAndPreservesLiteralContent() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "```swift\nlet x = 1 < 2 && true\n```")
        XCTAssertEqual(html, "<pre data-line=\"1\"><code class=\"language-swift\">let x = 1 &lt; 2 &amp;&amp; true\n</code></pre>")
    }

    func testPlainParagraphLinesGroupTogether() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "line one\nline two\n\nline three")
        XCTAssertEqual(html, "<p data-line=\"1\">line one line two</p>\n<p data-line=\"4\">line three</p>")
    }

    func testEmptyStringProducesEmptyHTML() {
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: ""), "")
    }

    // MARK: - data-line anchors

    func testEveryBlockKindCarriesItsSourceLine() {
        let markdown = """
        # Title

        A paragraph.

        - one
        - two

        > quoted

        ---

        ```swift
        let x = 1
        ```
        """
        let html = MarkdownHTMLRenderer.html(fromMarkdown: markdown)
        XCTAssertTrue(html.contains("<h1 data-line=\"1\">"), html)
        XCTAssertTrue(html.contains("<p data-line=\"3\">"), html)
        XCTAssertTrue(html.contains("<ul data-line=\"5\">"), html)
        XCTAssertTrue(html.contains("<blockquote data-line=\"8\">"), html)
        XCTAssertTrue(html.contains("<hr data-line=\"10\">"), html)
        XCTAssertTrue(html.contains("<pre data-line=\"12\">"), html)
    }

    // A paragraph's soft newlines collapse into one <p>, so the anchor is the FIRST line.
    func testMultiLineParagraphAnchorsToItsFirstLine() {
        let markdown = "# T\n\nline one\nline two\nline three\n\n## Next"
        let html = MarkdownHTMLRenderer.html(fromMarkdown: markdown)
        XCTAssertTrue(html.contains("<p data-line=\"3\">line one line two line three</p>"), html)
        XCTAssertTrue(html.contains("<h2 data-line=\"7\">"), html)
    }

    func testBlockSourceLinesInDocumentOrder() {
        let markdown = "# T\n\npara\n\n- item\n"
        XCTAssertEqual(MarkdownHTMLRenderer.blockSourceLines(fromMarkdown: markdown), [1, 3, 5])
    }

    func testBlockSourceLinesIsEmptyForEmptyDocument() {
        XCTAssertEqual(MarkdownHTMLRenderer.blockSourceLines(fromMarkdown: ""), [])
    }

    // MARK: - caret line -> block mapping

    func testBlockLineMapsToTheBlockContainingTheCaret() {
        let blocks = [1, 3, 7]
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 1, in: blocks), 1)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 2, in: blocks), 1)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 5, in: blocks), 3)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 7, in: blocks), 7)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 99, in: blocks), 7)
    }

    // A caret above the first block (e.g. leading blank lines) still lands somewhere sensible.
    func testCaretBeforeFirstBlockMapsToFirstBlock() {
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 1, in: [4, 9]), 4)
    }

    func testNoBlocksMapsToNil() {
        XCTAssertNil(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 3, in: []))
    }
}
