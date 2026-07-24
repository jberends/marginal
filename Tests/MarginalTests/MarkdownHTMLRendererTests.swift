import XCTest
@testable import Marginal

final class MarkdownHTMLRendererTests: XCTestCase {

    func testBoldRendersAsStrong() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Hello **world**")
        XCTAssertEqual(html, "<p>Hello <strong>world</strong></p>")
    }

    func testItalicRendersAsEm() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Hello *world*")
        XCTAssertEqual(html, "<p>Hello <em>world</em></p>")
    }

    func testInlineCodeRendersAsCode() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Use `npm install`")
        XCTAssertEqual(html, "<p>Use <code>npm install</code></p>")
    }

    func testStrikethroughAndUnderline() {
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "~~gone~~"), "<p><del>gone</del></p>")
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "<u>under</u>"), "<p><u>under</u></p>")
    }

    func testBoldSpanContainingNestedInlineCodeRendersBothCorrectly() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "**Repos & branches (both from `dev-gis`):**")
        XCTAssertEqual(html, "<p><strong>Repos &amp; branches (both from <code>dev-gis</code>):</strong></p>")
    }

    func testLinkRendersAsAnchor() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Check [this](https://example.com) out")
        XCTAssertEqual(html, "<p>Check <a href=\"https://example.com\">this</a> out</p>")
    }

    func testHeaderRendersWithCorrectLevel() {
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "# Title"), "<h1>Title</h1>")
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: "### Sub"), "<h3>Sub</h3>")
    }

    func testHorizontalRuleRendersAsHr() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Above\n\n---\n\nBelow")
        XCTAssertEqual(html, "<p>Above</p>\n<hr>\n<p>Below</p>")
    }

    func testBlockquoteRendersWithParagraph() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "> quoted text")
        XCTAssertEqual(html, "<blockquote><p>quoted text</p></blockquote>")
    }

    func testUnorderedListRendersAsUl() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "- one\n- two")
        XCTAssertEqual(html, "<ul><li>one</li><li>two</li></ul>")
    }

    func testOrderedListRendersAsOl() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "1. one\n2. two")
        XCTAssertEqual(html, "<ol><li>one</li><li>two</li></ol>")
    }

    func testListItemLazyContinuationJoinsIntoSameListItem() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "- one\ncontinued text")
        XCTAssertEqual(html, "<ul><li>one continued text</li></ul>")
    }

    func testFencedCodeBlockEscapesAndPreservesLiteralContent() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "```swift\nlet x = 1 < 2 && true\n```")
        XCTAssertEqual(html, "<pre><code class=\"language-swift\">let x = 1 &lt; 2 &amp;&amp; true\n</code></pre>")
    }

    func testPlainParagraphLinesGroupTogether() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "line one\nline two\n\nline three")
        XCTAssertEqual(html, "<p>line one line two</p>\n<p>line three</p>")
    }

    func testEmptyStringProducesEmptyHTML() {
        XCTAssertEqual(MarkdownHTMLRenderer.html(fromMarkdown: ""), "")
    }
}
