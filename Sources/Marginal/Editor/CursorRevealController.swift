import Foundation

struct CursorRevealController {

    static func revealedInlineStyleSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [InlineStyleSpan] {
        model.inlineStyles.filter { span in
            let fullRange = span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound
            return cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound
        }
    }

    static func revealedHeaderSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [HeaderSpan] {
        model.headers.filter { header in
            cursorLocation >= header.lineRange.lowerBound && cursorLocation <= header.lineRange.upperBound
        }
    }
}
