import XCTest
@testable import Marginal

final class CursorRevealControllerTests: XCTestCase {

    func testCursorOutsideSpanDoesNotRevealIt() {
        let text = "Hello **world** today"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.startIndex
        XCTAssertTrue(CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor).isEmpty)
    }

    func testCursorInsideSpanRevealsIt() {
        let text = "Hello **world** today"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 9) // inside "world"
        XCTAssertEqual(CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorAtOpeningDelimiterRevealsSpan() {
        let text = "Hello **world** today"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 6) // right at opening **
        XCTAssertEqual(CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorInHeaderLineRevealsHeaderMarker() {
        let text = "# Title\nBody"
        let model = MarkdownDocumentModel(headers: MarkdownParser.parseHeaders(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 3) // inside "Title"
        XCTAssertEqual(CursorRevealController.revealedHeaderSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOnOtherLineDoesNotRevealHeaderMarker() {
        let text = "# Title\nBody"
        let model = MarkdownDocumentModel(headers: MarkdownParser.parseHeaders(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 9) // inside "Body"
        XCTAssertTrue(CursorRevealController.revealedHeaderSpans(in: model, cursorLocation: cursor).isEmpty)
    }

    func testCursorAtSharedBoundaryOfAdjacentSpansRevealsOnlyOne() {
        let text = "**a****b**"
        // "**a**" spans indices 0..<5, "**b**" spans indices 5..<10 — index 5 is the exact
        // shared boundary between the first span's closing "**" and the second span's opening "**".
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 5)
        let revealed = CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor)
        XCTAssertEqual(revealed.count, 1, "Only one of the two touching spans should reveal at the shared boundary")
    }

    func testCursorOutsideLinkDoesNotRevealIt() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let cursor = text.startIndex
        XCTAssertTrue(CursorRevealController.revealedLinkSpans(in: model, cursorLocation: cursor).isEmpty)
    }

    func testCursorInsideLinkRevealsIt() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 10) // inside "this"
        XCTAssertEqual(CursorRevealController.revealedLinkSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorInBlockquoteLineRevealsItsMarker() {
        let text = "> Quoted\nNot quoted"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 3) // inside "Quoted"
        XCTAssertEqual(CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOnOtherLineDoesNotRevealBlockquoteMarker() {
        let text = "> Quoted\nNot quoted"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 12) // inside "Not quoted"
        XCTAssertTrue(CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: cursor).isEmpty)
    }

    func testCursorOnHorizontalRuleLineRevealsIt() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 7) // on the "---" line
        XCTAssertEqual(CursorRevealController.revealedHorizontalRuleSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOnOtherLineDoesNotRevealHorizontalRule() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 1) // on "Above"
        XCTAssertTrue(CursorRevealController.revealedHorizontalRuleSpans(in: model, cursorLocation: cursor).isEmpty)
    }
}
