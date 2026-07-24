import Foundation

struct CursorRevealController {

    static func revealedInlineStyleSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [InlineStyleSpan] {
        let candidates = model.inlineStyles.filter { span in
            let fullRange = span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound
            return cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound
        }
        guard candidates.count > 1 else { return candidates }
        // When the cursor sits exactly on a shared boundary between two adjacent spans (one's
        // closing edge equals another's opening edge), prefer the span that STARTS there over
        // the one that ENDS there, so touching spans don't both reveal at once.
        return candidates.filter { span in
            let fullRange = span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound
            let endsExactlyAtCursor = fullRange.upperBound == cursorLocation
            let anotherStartsAtCursor = candidates.contains { other in
                other != span && other.openingDelimiterRange.lowerBound == cursorLocation
            }
            return !(endsExactlyAtCursor && anotherStartsAtCursor)
        }
    }

    static func revealedHeaderSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [HeaderSpan] {
        model.headers.filter { header in
            cursorLocation >= header.lineRange.lowerBound && cursorLocation <= header.lineRange.upperBound
        }
    }
}
