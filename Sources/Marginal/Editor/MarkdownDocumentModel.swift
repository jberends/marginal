import Foundation

enum InlineStyleKind: Equatable {
    case bold
    case italic
    case strikethrough
    case underline
}

struct InlineStyleSpan: Equatable {
    let kind: InlineStyleKind
    let contentRange: Range<String.Index>
    let openingDelimiterRange: Range<String.Index>
    let closingDelimiterRange: Range<String.Index>
}

struct MarkdownDocumentModel: Equatable {
    var inlineStyles: [InlineStyleSpan] = []
}
