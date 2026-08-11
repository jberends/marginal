import Foundation

/// Serializes a `BlockDocument` back into canonical markdown source, the inverse of
/// `MarkdownBlockParser.parse`. "Canonical" means: `-` bullets, sequentially renumbered
/// `1.`/`2.`/… ordered items (restarting at 1 for each contiguous run of ordered items at the
/// same indent), `- [ ]`/`- [x]` tasks, 2-space indent per nesting level, `#`×level headings,
/// `> ` quotes, fenced code blocks with the language on the opening fence, `---` dividers, and
/// padded pipe tables with a `|---|`/`|:---:|`/`|---:|` alignment row. Blocks are separated by
/// exactly one blank line, except two consecutive `listItem` blocks (of any style/indent), which
/// are adjacent with no blank line between them -- matching how a markdown list renders. The
/// document always ends with a single trailing newline.
///
/// Alongside the markdown text, this also returns a line map: for each block, the (1-based,
/// inclusive) range of source lines it occupies in the emitted text, so callers can translate
/// between a block id and its location in an editor's text view.
enum MarkdownSerializer {

    static func serialize(_ doc: BlockDocument) -> (markdown: String, lineMap: [UUID: ClosedRange<Int>]) {
        var lines: [String] = []
        var lineMap: [UUID: ClosedRange<Int>] = [:]
        var orderedCounters: [Int: Int] = [:]
        var previousKind: BlockKind?

        for block in doc.blocks {
            if let previousKind, !(isListItem(previousKind) && isListItem(block.kind)) {
                lines.append("")
            }

            let startLine = lines.count + 1
            let blockLines = emit(block.kind, orderedCounters: &orderedCounters)
            lines.append(contentsOf: blockLines)
            let endLine = lines.count
            lineMap[block.id] = startLine...endLine

            previousKind = block.kind
        }

        let markdown = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        return (markdown, lineMap)
    }

    private static func isListItem(_ kind: BlockKind) -> Bool {
        if case .listItem = kind { return true }
        return false
    }

    /// Emits the physical source lines for a single block, updating `orderedCounters` (indent ->
    /// next ordered number) as it goes: any non-ordered-listItem block clears the whole table
    /// (ending every ordered run), while an ordered listItem bumps its own indent's counter.
    private static func emit(_ kind: BlockKind, orderedCounters: inout [Int: Int]) -> [String] {
        switch kind {
        case .paragraph(let text):
            orderedCounters.removeAll()
            return [InlineMarkdown.serialize(text)]

        case .heading(let level, let text):
            orderedCounters.removeAll()
            return [String(repeating: "#", count: level) + " " + InlineMarkdown.serialize(text)]

        case .quote(let text):
            orderedCounters.removeAll()
            return ["> " + InlineMarkdown.serialize(text)]

        case .divider:
            orderedCounters.removeAll()
            return ["---"]

        case .codeBlock(let language, let content):
            orderedCounters.removeAll()
            var result = ["```" + (language ?? "")]
            // Content lines each carry their own trailing "\n" (per `MarkdownBlockParser`'s
            // contentRange, which ends right at the closing fence's line start), so splitting on
            // "\n" leaves one spurious trailing empty element to drop -- unless content is empty,
            // in which case there are no content lines at all.
            var contentLines = content.components(separatedBy: "\n")
            if contentLines.last == "" {
                contentLines.removeLast()
            }
            result.append(contentsOf: contentLines)
            result.append("```")
            return result

        case .table(let alignments, let header, let rows):
            orderedCounters.removeAll()
            var result = [rowLine(header)]
            result.append(alignmentLine(alignments))
            result.append(contentsOf: rows.map(rowLine))
            return result

        case .listItem(let style, let indent, let text):
            let marker: String
            switch style {
            case .bullet:
                orderedCounters.removeValue(forKey: indent)
                marker = "- "
            case .task(let done):
                orderedCounters.removeValue(forKey: indent)
                marker = done ? "- [x] " : "- [ ] "
            case .ordered:
                let next = (orderedCounters[indent] ?? 0) + 1
                orderedCounters[indent] = next
                // Any list item at a deeper indent no longer continues once a shallower item
                // appears; only ancestor (shallower-or-equal) runs stay alive.
                for key in orderedCounters.keys where key > indent {
                    orderedCounters.removeValue(forKey: key)
                }
                orderedCounters[indent] = next
                marker = "\(next). "
            }
            let indentPrefix = String(repeating: "  ", count: max(indent, 0))
            return [indentPrefix + marker + InlineMarkdown.serialize(text)]
        }
    }

    private static func rowLine(_ cells: [InlineText]) -> String {
        "| " + cells.map(escapedCellMarkdown).joined(separator: " | ") + " |"
    }

    /// A cell's serialized markdown, made safe to sit between two `|` column separators.
    /// `MarkdownBlockParser.tableBlockKind` unescapes `\|` back into a literal `|` when reading a
    /// cell, so a literal `|` here must be re-escaped as `\|` -- otherwise it's indistinguishable
    /// from a real column separator on the next parse, and the parser silently clamps/drops any
    /// cell past the header's column count (content loss, not just a cosmetic misparse). A
    /// newline would similarly split this row across two physical source lines and destroy the
    /// table's structure, so it's collapsed to a single space (chosen over `<br>` since this
    /// parser doesn't render HTML `<br>` -- a space is at least visually inert either way).
    private static func escapedCellMarkdown(_ text: InlineText) -> String {
        InlineMarkdown.serialize(text)
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func alignmentLine(_ alignments: [TableAlignment]) -> String {
        "|" + alignments.map(alignmentDashes).joined(separator: "|") + "|"
    }

    private static func alignmentDashes(_ alignment: TableAlignment) -> String {
        switch alignment {
        case .left: return "---"
        case .center: return ":---:"
        case .right: return "---:"
        }
    }
}
