import Foundation

/// Converts markdown source into HTML, reusing the same block/inline parsers MarkdownStyler uses
/// for on-screen rendering -- one parsing model, two consumers. Covers exactly the constructs this
/// app supports (single-level lists/blockquotes, pipe tables, no nested lists), matching
/// MarkdownParser's own "pragmatic single-pass, not full CommonMark" scope.
struct MarkdownHTMLRenderer {

    static func html(fromMarkdown text: String) -> String {
        blocks(fromMarkdown: text).map(\.html).joined(separator: "\n")
    }

    /// The 1-based source line each emitted block starts at, in document order. Paired with the
    /// `data-line` attributes in the HTML, this lets the editor map a caret line to a rendered
    /// block and back.
    static func blockSourceLines(fromMarkdown text: String) -> [Int] {
        blocks(fromMarkdown: text).map(\.line)
    }

    /// The greatest block line not exceeding `caretLine` -- i.e. the block the caret sits in.
    /// Falls back to the first block when the caret precedes all of them, and to nil when the
    /// document renders no blocks at all.
    static func blockLine(nearestAtOrBefore caretLine: Int, in blockLines: [Int]) -> Int? {
        guard let first = blockLines.first else { return nil }
        return blockLines.last { $0 <= caretLine } ?? first
    }

    private static func blocks(fromMarkdown text: String) -> [(line: Int, html: String)] {
        guard !text.isEmpty else { return [] }

        let headers = MarkdownParser.parseHeaders(in: text)
        let listItems = MarkdownParser.parseListItems(in: text)
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        let horizontalRules = MarkdownParser.parseHorizontalRules(in: text)
        let codeBlocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        let tables = MarkdownParser.parseTables(in: text)
        let starts = lineStarts(in: text)

        var blocks: [(line: Int, html: String)] = []
        var index = text.startIndex

        while index < text.endIndex {
            let line = lineNumber(at: index, lineStarts: starts)

            if let codeBlock = codeBlocks.first(where: { $0.openingFenceRange.lowerBound == index }) {
                let languageAttribute = codeBlock.language.map { " class=\"language-\(htmlEscape($0))\"" } ?? ""
                blocks.append((line, "<pre data-line=\"\(line)\"><code\(languageAttribute)>\(htmlEscape(String(text[codeBlock.contentRange])))</code></pre>"))
                index = advance(past: codeBlock.openingFenceRange.lowerBound..<codeBlock.closingFenceRange.upperBound, in: text)
                continue
            }
            if let table = tables.first(where: { $0.headerRow.lineRange.lowerBound == index }) {
                blocks.append((line, tableHTML(for: table, in: text, line: line)))
                let lastRowRange = table.bodyRows.last?.lineRange ?? table.separatorRowRange
                index = advance(past: lastRowRange, in: text)
                continue
            }
            if let header = headers.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append((line, "<h\(header.level) data-line=\"\(line)\">\(inlineHTML(for: String(text[header.contentRange])))</h\(header.level)>"))
                index = advance(past: header.lineRange, in: text)
                continue
            }
            if let rule = horizontalRules.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append((line, "<hr data-line=\"\(line)\">"))
                index = advance(past: rule.lineRange, in: text)
                continue
            }
            if let item = listItems.first(where: { $0.lineRange.lowerBound == index }) {
                var groupItems = [item]
                var cursor = advance(past: item.lineRange, in: text)
                while let next = listItems.first(where: { $0.lineRange.lowerBound == cursor }), sameListKind(next.kind, item.kind) {
                    groupItems.append(next)
                    cursor = advance(past: next.lineRange, in: text)
                }
                let tag = isOrdered(item.kind) ? "ol" : "ul"
                let items = groupItems.map { "<li>\(inlineHTML(for: listItemText($0, in: text)))</li>" }.joined()
                blocks.append((line, "<\(tag) data-line=\"\(line)\">\(items)</\(tag)>"))
                index = cursor
                continue
            }
            if let quote = blockquotes.first(where: { $0.lineRange.lowerBound == index }) {
                var groupLines = [String(text[quote.contentRange])]
                var cursor = advance(past: quote.lineRange, in: text)
                while let next = blockquotes.first(where: { $0.lineRange.lowerBound == cursor }) {
                    groupLines.append(String(text[next.contentRange]))
                    cursor = advance(past: next.lineRange, in: text)
                }
                blocks.append((line, "<blockquote data-line=\"\(line)\"><p>\(inlineHTML(for: groupLines.joined(separator: " ")))</p></blockquote>"))
                index = cursor
                continue
            }

            let firstLineRange = lineRange(at: index, in: text)
            let firstLine = String(text[firstLineRange])
            if firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
                index = advance(past: firstLineRange, in: text)
                continue
            }

            var paragraphLines = [firstLine]
            var cursor = advance(past: firstLineRange, in: text)
            while cursor < text.endIndex, !isBlockStart(at: cursor, headers: headers, listItems: listItems, blockquotes: blockquotes, horizontalRules: horizontalRules, codeBlocks: codeBlocks, tables: tables) {
                let range = lineRange(at: cursor, in: text)
                let lineText = String(text[range])
                if lineText.trimmingCharacters(in: .whitespaces).isEmpty { break }
                paragraphLines.append(lineText)
                cursor = advance(past: range, in: text)
            }
            blocks.append((line, "<p data-line=\"\(line)\">\(inlineHTML(for: paragraphLines.joined(separator: " ")))</p>"))
            index = cursor
        }

        return blocks
    }

    /// Every line's start index, so a block's start index can be turned into a 1-based line
    /// number with a binary search rather than a rescan per block.
    private static func lineStarts(in text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\n" {
                starts.append(text.index(after: index))
            }
            index = text.index(after: index)
        }
        return starts
    }

    /// The 1-based line number containing `index`.
    private static func lineNumber(at index: String.Index, lineStarts: [String.Index]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= index {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    private static func lineRange(at start: String.Index, in text: String) -> Range<String.Index> {
        let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
        return start..<end
    }

    private static func advance(past range: Range<String.Index>, in text: String) -> String.Index {
        range.upperBound < text.endIndex ? text.index(after: range.upperBound) : text.endIndex
    }

    private static func isBlockStart(
        at index: String.Index,
        headers: [HeaderSpan],
        listItems: [ListItemSpan],
        blockquotes: [BlockquoteSpan],
        horizontalRules: [HorizontalRuleSpan],
        codeBlocks: [CodeBlockSpan],
        tables: [TableSpan]
    ) -> Bool {
        headers.contains { $0.lineRange.lowerBound == index }
            || listItems.contains { $0.lineRange.lowerBound == index }
            || blockquotes.contains { $0.lineRange.lowerBound == index }
            || horizontalRules.contains { $0.lineRange.lowerBound == index }
            || codeBlocks.contains { $0.openingFenceRange.lowerBound == index }
            || tables.contains { $0.headerRow.lineRange.lowerBound == index }
    }

    /// Header cells become <th> (with a text-align style for center/right columns), body rows
    /// <td>; cell content goes through the same inline renderer as any other fragment, and an
    /// escaped "\|" (a literal pipe, not a column boundary) unescapes to "|".
    private static func tableHTML(for table: TableSpan, in text: String, line: Int) -> String {
        func alignAttribute(_ column: Int) -> String {
            guard table.columnAlignments.indices.contains(column) else { return "" }
            switch table.columnAlignments[column] {
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            case .left: return ""
            }
        }
        func cells(of row: TableRowSpan) -> [String] {
            guard row.pipeRanges.count >= 2 else { return [] }
            return (0..<(row.pipeRanges.count - 1)).map { c in
                String(text[row.pipeRanges[c].upperBound..<row.pipeRanges[c + 1].lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\\|", with: "|")
            }
        }
        let headerCells = cells(of: table.headerRow).enumerated()
            .map { "<th\(alignAttribute($0.offset))>\(inlineHTML(for: $0.element))</th>" }
            .joined()
        let bodyRows = table.bodyRows
            .map { row in
                "<tr>" + cells(of: row).enumerated()
                    .map { "<td\(alignAttribute($0.offset))>\(inlineHTML(for: $0.element))</td>" }
                    .joined() + "</tr>"
            }
            .joined()
        return "<table data-line=\"\(line)\"><thead><tr>\(headerCells)</tr></thead><tbody>\(bodyRows)</tbody></table>"
    }

    private static func sameListKind(_ a: ListMarkerKind, _ b: ListMarkerKind) -> Bool {
        switch (a, b) {
        case (.unordered, .unordered): return true
        case (.ordered, .ordered): return true
        default: return false
        }
    }

    private static func isOrdered(_ kind: ListMarkerKind) -> Bool {
        if case .ordered = kind { return true }
        return false
    }

    private static func listItemText(_ item: ListItemSpan, in text: String) -> String {
        String(text[item.contentRange.lowerBound..<item.lineRange.upperBound])
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    /// Renders one paragraph-sized fragment's inline markup, re-parsing styles/links in this
    /// fragment's own local coordinate space (each block above hands this a fresh, independent
    /// string, not an offset into the original document).
    private static func inlineHTML(for line: String) -> String {
        guard !line.isEmpty else { return "" }

        struct TagInsertion {
            let index: String.Index
            let isClosing: Bool
            let tag: String
        }

        var insertions: [TagInsertion] = []
        var skipRanges: [Range<String.Index>] = []

        for style in MarkdownParser.parseInlineStyles(in: line) {
            let (openTag, closeTag): (String, String)
            switch style.kind {
            case .bold: (openTag, closeTag) = ("<strong>", "</strong>")
            case .italic: (openTag, closeTag) = ("<em>", "</em>")
            case .boldItalic: (openTag, closeTag) = ("<strong><em>", "</em></strong>")
            case .strikethrough: (openTag, closeTag) = ("<del>", "</del>")
            case .underline: (openTag, closeTag) = ("<u>", "</u>")
            case .code: (openTag, closeTag) = ("<code>", "</code>")
            }
            insertions.append(TagInsertion(index: style.contentRange.lowerBound, isClosing: false, tag: openTag))
            insertions.append(TagInsertion(index: style.contentRange.upperBound, isClosing: true, tag: closeTag))
            skipRanges.append(style.openingDelimiterRange)
            skipRanges.append(style.closingDelimiterRange)
        }

        for link in MarkdownParser.parseLinks(in: line) {
            insertions.append(TagInsertion(index: link.textRange.lowerBound, isClosing: false, tag: "<a href=\"\(htmlAttributeEscape(link.url))\">"))
            insertions.append(TagInsertion(index: link.textRange.upperBound, isClosing: true, tag: "</a>"))
            skipRanges.append(link.fullRange.lowerBound..<link.textRange.lowerBound)
            skipRanges.append(link.textRange.upperBound..<link.fullRange.upperBound)
        }

        func isSkipped(_ i: String.Index) -> Bool {
            skipRanges.contains { $0.contains(i) }
        }

        var insertionsByIndex: [String.Index: [TagInsertion]] = [:]
        for insertion in insertions {
            insertionsByIndex[insertion.index, default: []].append(insertion)
        }

        var output = ""
        var i = line.startIndex
        while i <= line.endIndex {
            if let atIndex = insertionsByIndex[i] {
                for insertion in atIndex.sorted(by: { $0.isClosing && !$1.isClosing }) {
                    output += insertion.tag
                }
            }
            guard i < line.endIndex else { break }
            if !isSkipped(i) {
                output += htmlEscape(String(line[i]))
            }
            i = line.index(after: i)
        }
        return output
    }

    private static func htmlEscape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for char in string {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(char)
            }
        }
        return out
    }

    private static func htmlAttributeEscape(_ string: String) -> String {
        htmlEscape(string).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
