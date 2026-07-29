import Foundation

/// Where the cursor is, for the status bar: 1-based line/column plus a breadcrumb of the
/// markdown constructs at the cursor (block first, then inline), e.g. ["h1", "bold"].
struct CursorStatus: Equatable {
    let line: Int
    let column: Int
    let path: [String]

    static func status(for text: String, model: MarkdownDocumentModel, cursor: String.Index) -> CursorStatus {
        var line = 1
        var lastLineStart = text.startIndex
        var i = text.startIndex
        while i < cursor {
            if text[i] == "\n" {
                line += 1
                lastLineStart = text.index(after: i)
            }
            i = text.index(after: i)
        }
        let column = text.distance(from: lastLineStart, to: cursor) + 1

        var path: [String] = []

        if let codeBlock = model.codeBlocks.first(where: { ($0.openingFenceRange.lowerBound..<$0.closingFenceRange.upperBound).contains(cursor) }) {
            path.append(codeBlock.language.map { "code (\($0))" } ?? "code")
        } else if let header = model.headers.first(where: { $0.lineRange.contains(cursor) }) {
            path.append("h\(header.level)")
        } else if let item = model.listItems.first(where: { $0.lineRange.contains(cursor) }) {
            if item.taskState != nil {
                path.append("task")
            } else if case .ordered = item.kind {
                path.append("list (ordered)")
            } else {
                path.append("list")
            }
        } else if model.blockquotes.contains(where: { $0.lineRange.contains(cursor) }) {
            path.append("quote")
        } else if model.tables.contains(where: { table in
            let fullRange = table.headerRow.lineRange.lowerBound..<(table.bodyRows.last?.lineRange.upperBound ?? table.separatorRowRange.upperBound)
            return fullRange.contains(cursor)
        }) {
            path.append("table")
        } else {
            path.append("text")
        }

        for span in model.inlineStyles where (span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound).contains(cursor) {
            switch span.kind {
            case .bold: path.append("bold")
            case .italic: path.append("italic")
            case .boldItalic: path.append("bold italic")
            case .strikethrough: path.append("strikethrough")
            case .underline: path.append("underline")
            case .code: path.append("code")
            }
        }
        if model.links.contains(where: { $0.fullRange.contains(cursor) }) {
            path.append("link")
        }

        return CursorStatus(line: line, column: column, path: path)
    }
}
