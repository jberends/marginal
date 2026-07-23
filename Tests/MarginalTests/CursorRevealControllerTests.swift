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
}
