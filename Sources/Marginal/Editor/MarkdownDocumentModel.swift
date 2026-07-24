import Foundation

enum InlineStyleKind: Equatable {
    case bold
    case italic
    case strikethrough
    case underline
    case code
}

struct InlineStyleSpan: Equatable {
    let kind: InlineStyleKind
    let contentRange: Range<String.Index>
    let openingDelimiterRange: Range<String.Index>
    let closingDelimiterRange: Range<String.Index>
}

struct HeaderSpan: Equatable {
    let level: Int
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
}

enum ListMarkerKind: Equatable {
    case unordered
    case ordered(number: Int)
}

struct ListItemSpan: Equatable {
    let kind: ListMarkerKind
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
}

struct LinkSpan: Equatable {
    let textRange: Range<String.Index>
    let urlRange: Range<String.Index>
    let fullRange: Range<String.Index>
    let url: String
}

struct MarkdownDocumentModel: Equatable {
    var inlineStyles: [InlineStyleSpan] = []
    var headers: [HeaderSpan] = []
    var listItems: [ListItemSpan] = []
    var links: [LinkSpan] = []
}
