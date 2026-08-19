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

    func testImageRendersAsImgTag() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "![a cat](MyNote.assets/cat.png)")
        XCTAssertTrue(html.contains(#"<img src="MyNote.assets/cat.png" alt="a cat">"#), html)
        XCTAssertFalse(html.contains("<a "), "image must not also render as a link")
    }

    func testImageAltIsEscaped() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: #"![a "b" & c](x.png)"#)
        XCTAssertTrue(html.contains(#"alt="a &quot;b&quot; &amp; c""#), html)
    }

    func testImagePathWithSpacesIsPercentEncoded() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "![](My Note.assets/pic 1.png)")
        XCTAssertTrue(html.contains(#"src="My%20Note.assets/pic%201.png""#), html)
    }

    func testImagePathAmpersandIsEscaped() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "![](a&b.png)")
        XCTAssertTrue(html.contains(#"src="a&amp;b.png""#), html)
    }

    func testUnderscoreInImagePathDoesNotLeakOrHijackRealEmphasis() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "![a](x_y.png) plain _italic_ text")
        XCTAssertEqual(html, "<p><img src=\"x_y.png\" alt=\"a\"> plain <em>italic</em> text</p>")
    }

    func testUnderscoreOnlyImagePathProducesNoStrayEmphasisTag() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "![a cat](Screenshot_2026_08_14.png)")
        XCTAssertTrue(html.contains(#"<img src="Screenshot_2026_08_14.png" alt="a cat">"#), html)
        XCTAssertFalse(html.contains("<em>"), html)
        XCTAssertFalse(html.contains("</em>"), html)
    }
}

/// Tables render on screen but used to fall through this renderer's paragraph branch, so exporting
/// a document to PDF (or copying it as HTML) turned every table into a run of literal "| a | b |"
/// text. These pin the <table> emission that closes that gap.
final class MarkdownHTMLRendererTableTests: XCTestCase {

    func testTableRendersAsRealTableMarkup() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(html, "<table><thead><tr><th>A</th><th>B</th></tr></thead>"
                           + "<tbody><tr><td>1</td><td>2</td></tr></tbody></table>")
    }

    func testNoPipeCharacterSurvivesIntoTheOutput() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertFalse(html.contains("|"), "Table syntax must not leak into the rendered output: \(html)")
        XCTAssertFalse(html.contains("<p>"), "A table must not fall through to the paragraph branch: \(html)")
    }

    func testInlineMarkupInsideCellsIsRendered() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| Capability | Detail |\n|---|---|\n| **Deploy** | set to `present` |")
        XCTAssertTrue(html.contains("<th>Capability</th>"), html)
        XCTAssertTrue(html.contains("<td><strong>Deploy</strong></td>"), html)
        XCTAssertTrue(html.contains("<td>set to <code>present</code></td>"), html)
    }

    func testColumnAlignmentBecomesTextAlignStyle() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| L | C | R |\n|:---|:---:|---:|\n| a | b | c |")
        XCTAssertTrue(html.contains("<th>L</th>"), "A left column needs no style attribute: \(html)")
        XCTAssertTrue(html.contains("<th style=\"text-align:center\">C</th>"), html)
        XCTAssertTrue(html.contains("<th style=\"text-align:right\">R</th>"), html)
        XCTAssertTrue(html.contains("<td style=\"text-align:center\">b</td>"), html)
        XCTAssertTrue(html.contains("<td style=\"text-align:right\">c</td>"), html)
    }

    func testEscapedPipeBecomesALiteralPipeInsideItsCell() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| Expression |\n|---|\n| A \\| B |")
        XCTAssertTrue(html.contains("<td>A | B</td>"), "The backslash is syntax; only the pipe is content: \(html)")
    }

    func testShortAndLongBodyRowsArePaddedAndTruncatedToTheHeaderWidth() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| A | B |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |")
        XCTAssertTrue(html.contains("<tr><td>1</td><td></td></tr>"), "A short row gets an empty trailing cell: \(html)")
        XCTAssertTrue(html.contains("<tr><td>1</td><td>2</td></tr>"), "A long row is truncated to the header width: \(html)")
        XCTAssertFalse(html.contains("<td>3</td>"), html)
    }

    func testParagraphImmediatelyBeforeATableIsNotSwallowedByIt() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "Intro line\n| A |\n|---|\n| 1 |")
        XCTAssertEqual(html, "<p>Intro line</p>\n<table><thead><tr><th>A</th></tr></thead>"
                           + "<tbody><tr><td>1</td></tr></tbody></table>")
    }

    func testTableInsideAFencedCodeBlockStaysLiteral() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "```markdown\n| A |\n|---|\n| 1 |\n```")
        XCTAssertTrue(html.hasPrefix("<pre><code"), html)
        XCTAssertFalse(html.contains("<table>"), "A table shown as sample code must not become a real table: \(html)")
    }

    func testTableFollowedByAParagraphEndsAtTheBlankLine() {
        let html = MarkdownHTMLRenderer.html(fromMarkdown: "| A |\n|---|\n| 1 |\n\nAfter")
        XCTAssertTrue(html.hasSuffix("<p>After</p>"), html)
    }
}
