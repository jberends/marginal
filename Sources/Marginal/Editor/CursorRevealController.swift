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

    static func revealedLinkSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [LinkSpan] {
        model.links.filter { link in
            cursorLocation >= link.fullRange.lowerBound && cursorLocation <= link.fullRange.upperBound
        }
    }

    /// Task items whose line contains the cursor: their checkbox renders as the literal
    /// "[ ]"/"[x]" source while editing that line, matching every other marker's behavior.
    static func revealedTaskListSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [ListItemSpan] {
        model.listItems.filter { item in
            item.taskState != nil
                && cursorLocation >= item.lineRange.lowerBound && cursorLocation <= item.lineRange.upperBound
        }
    }

    static func revealedBlockquoteSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [BlockquoteSpan] {
        model.blockquotes.filter { blockquote in
            cursorLocation >= blockquote.lineRange.lowerBound && cursorLocation <= blockquote.lineRange.upperBound
        }
    }

    static func revealedHorizontalRuleSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [HorizontalRuleSpan] {
        model.horizontalRules.filter { rule in
            cursorLocation >= rule.lineRange.lowerBound && cursorLocation <= rule.lineRange.upperBound
        }
    }

    static func revealedCodeBlockSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [CodeBlockSpan] {
        model.codeBlocks.filter { block in
            let fullRange = block.openingFenceRange.lowerBound..<block.closingFenceRange.upperBound
            return cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound
        }
    }

    static func revealedImageSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [ImageSpan] {
        model.images.filter { image in
            cursorLocation >= image.fullRange.lowerBound && cursorLocation <= image.fullRange.upperBound
        }
    }
}
