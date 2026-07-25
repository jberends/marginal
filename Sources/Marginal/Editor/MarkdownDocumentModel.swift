import Foundation

enum InlineStyleKind: Equatable {
    case bold
    case italic
    case boldItalic
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

enum TaskState: Equatable {
    case incomplete
    case complete
}

struct ListItemSpan: Equatable {
    let kind: ListMarkerKind
    /// Nesting depth, 0 = top level. Derived from leading-space indentation (2 spaces per level).
    let level: Int
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
    /// Non-nil when the content starts with a GFM task-list checkbox ("[ ]"/"[x]"/"[X] ").
    let taskState: TaskState?
    /// The full "[ ] "/"[x] " checkbox match (brackets, state character, trailing space), so the
    /// styler can hide it and know exactly where the real task text begins. nil iff taskState is.
    let taskMarkerRange: Range<String.Index>?
}

struct LinkSpan: Equatable {
    let textRange: Range<String.Index>
    let urlRange: Range<String.Index>
    let fullRange: Range<String.Index>
    let url: String
}

struct BlockquoteSpan: Equatable {
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
}

struct HorizontalRuleSpan: Equatable {
    let lineRange: Range<String.Index>
}

struct CodeBlockSpan: Equatable {
    let openingFenceRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let closingFenceRange: Range<String.Index>
    let language: String?
}

enum CodeTokenKind: Equatable {
    case string
    case comment
    case number
}

struct CodeHighlightToken: Equatable {
    let kind: CodeTokenKind
    let range: Range<String.Index>
}

enum TableAlignment: Equatable {
    case left
    case center
    case right
}

struct TableRowSpan: Equatable {
    let lineRange: Range<String.Index>
    /// Every real (non-escaped) "|" in the row, including the leading and trailing pipes.
    /// N pipes bound N-1 cells: cell c is pipeRanges[c].upperBound..<pipeRanges[c+1].lowerBound.
    let pipeRanges: [Range<String.Index>]
}

struct TableSpan: Equatable {
    let headerRow: TableRowSpan
    /// The "| --- |:---:|---: |" alignment row -- pure syntax, always hidden, never shown.
    let separatorRowRange: Range<String.Index>
    let bodyRows: [TableRowSpan]
    let columnAlignments: [TableAlignment]
}

/// A ":shortcode:" that matches a known GFM/gemoji alias (e.g. ":smile:", ":+1:",
/// ":white_check_mark:") -- unrecognized ":word:" text is left alone.
struct EmojiShortcodeSpan: Equatable {
    let fullRange: Range<String.Index>
    let emoji: String
}

struct MarkdownDocumentModel: Equatable {
    var inlineStyles: [InlineStyleSpan] = []
    var headers: [HeaderSpan] = []
    var listItems: [ListItemSpan] = []
    var links: [LinkSpan] = []
    var blockquotes: [BlockquoteSpan] = []
    var horizontalRules: [HorizontalRuleSpan] = []
    var codeBlocks: [CodeBlockSpan] = []
    var tables: [TableSpan] = []
    var emojiShortcodes: [EmojiShortcodeSpan] = []
}
