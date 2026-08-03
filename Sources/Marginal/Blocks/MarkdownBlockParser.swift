import Foundation

/// Converts markdown source into a `BlockDocument`, mirroring `MarkdownHTMLRenderer.html(fromMarkdown:)`'s
/// line-walk and dispatch order (code fence, table, header, rule, list item, quote, then paragraph
/// fallback) but reusing Task 1/2's `Block`/`BlockKind`/`InlineText` model instead of emitting HTML.
///
/// Total function: never throws, never drops content. Unrecognized lines become literal paragraph
/// blocks; blank lines produce no blocks; an empty document still produces one empty paragraph block
/// (an editor always needs a block to type into).
enum MarkdownBlockParser {

    static func parse(_ markdown: String) -> BlockDocument {
        let text = markdown

        guard !text.isEmpty else {
            return BlockDocument(blocks: [Block(kind: .paragraph(InlineText("")))])
        }

        let headers = MarkdownParser.parseHeaders(in: text)
        let listItems = MarkdownParser.parseListItems(in: text)
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        let horizontalRules = MarkdownParser.parseHorizontalRules(in: text)
        let codeBlocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        let tables = MarkdownParser.parseTables(in: text)

        var blocks: [Block] = []
        var index = text.startIndex

        while index < text.endIndex {
            if let codeBlock = codeBlocks.first(where: { $0.openingFenceRange.lowerBound == index }) {
                blocks.append(Block(kind: .codeBlock(language: codeBlock.language, String(text[codeBlock.contentRange]))))
                index = advance(past: codeBlock.openingFenceRange.lowerBound..<codeBlock.closingFenceRange.upperBound, in: text)
                continue
            }
            if let table = tables.first(where: { $0.headerRow.lineRange.lowerBound == index }) {
                blocks.append(Block(kind: tableBlockKind(table, in: text)))
                index = advance(past: tableRange(table), in: text)
                continue
            }
            if let header = headers.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append(Block(kind: .heading(level: header.level, InlineMarkdown.parse(String(text[header.contentRange])))))
                index = advance(past: header.lineRange, in: text)
                continue
            }
            if let rule = horizontalRules.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append(Block(kind: .divider))
                index = advance(past: rule.lineRange, in: text)
                continue
            }
            if let item = listItems.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append(Block(kind: listItemBlockKind(item, in: text)))
                index = advance(past: item.lineRange, in: text)
                continue
            }
            if let quote = blockquotes.first(where: { $0.lineRange.lowerBound == index }) {
                var groupLines = [String(text[quote.contentRange])]
                var cursor = advance(past: quote.lineRange, in: text)
                while let next = blockquotes.first(where: { $0.lineRange.lowerBound == cursor }) {
                    groupLines.append(String(text[next.contentRange]))
                    cursor = advance(past: next.lineRange, in: text)
                }
                blocks.append(Block(kind: .quote(InlineMarkdown.parse(groupLines.joined(separator: " ")))))
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
            while cursor < text.endIndex, !isBlockStart(
                at: cursor,
                headers: headers,
                listItems: listItems,
                blockquotes: blockquotes,
                horizontalRules: horizontalRules,
                codeBlocks: codeBlocks,
                tables: tables
            ) {
                let range = lineRange(at: cursor, in: text)
                let line = String(text[range])
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                paragraphLines.append(line)
                cursor = advance(past: range, in: text)
            }
            blocks.append(Block(kind: .paragraph(InlineMarkdown.parse(paragraphLines.joined(separator: " ")))))
            index = cursor
        }

        // Blank-only or otherwise block-less input still needs a block to type into.
        if blocks.isEmpty {
            blocks.append(Block(kind: .paragraph(InlineText(""))))
        }

        return BlockDocument(blocks: blocks)
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

    /// The item's own line content only: text from just past the marker (and, for a task item,
    /// past the checkbox too, so the checkbox text never leaks into the inline content) through
    /// the end of its (possibly lazily-continued) line range. Continuation lines are trimmed and
    /// joined with a single space, matching `MarkdownHTMLRenderer`'s `listItemText` convention.
    private static func listItemText(_ item: ListItemSpan, in text: String) -> String {
        let start = item.taskMarkerRange?.upperBound ?? item.contentRange.lowerBound
        return String(text[start..<item.lineRange.upperBound])
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    private static func listItemBlockKind(_ item: ListItemSpan, in text: String) -> BlockKind {
        let style: ListStyle
        switch item.kind {
        case .unordered:
            if let taskState = item.taskState {
                style = .task(done: taskState == .complete)
            } else {
                style = .bullet
            }
        case .ordered:
            style = .ordered
        }
        return .listItem(style: style, indent: item.level, InlineMarkdown.parse(listItemText(item, in: text)))
    }

    private static func tableRange(_ table: TableSpan) -> Range<String.Index> {
        let end = table.bodyRows.last?.lineRange.upperBound ?? table.separatorRowRange.upperBound
        return table.headerRow.lineRange.lowerBound..<end
    }

    private static func tableBlockKind(_ table: TableSpan, in text: String) -> BlockKind {
        let columnCount = table.headerRow.pipeRanges.count - 1

        func cells(of row: TableRowSpan) -> [InlineText] {
            let cols = min(columnCount, row.pipeRanges.count - 1)
            guard cols > 0 else { return [] }
            return (0..<cols).map { c in
                let cellRange = row.pipeRanges[c].upperBound..<row.pipeRanges[c + 1].lowerBound
                let raw = String(text[cellRange]).trimmingCharacters(in: .whitespaces)
                let unescaped = raw.replacingOccurrences(of: "\\|", with: "|")
                return InlineMarkdown.parse(unescaped)
            }
        }

        let alignments: [TableAlignment] = (0..<max(columnCount, 0)).map {
            table.columnAlignments.indices.contains($0) ? table.columnAlignments[$0] : .left
        }

        return .table(
            alignments: alignments,
            header: cells(of: table.headerRow),
            rows: table.bodyRows.map(cells(of:))
        )
    }
}
