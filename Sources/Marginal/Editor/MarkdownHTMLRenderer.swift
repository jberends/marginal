import Foundation

/// Converts markdown source into HTML, reusing the same block/inline parsers MarkdownStyler uses
/// for on-screen rendering -- one parsing model, two consumers. Covers exactly the constructs this
/// app supports (single-level lists/blockquotes, no tables, no nested lists), matching
/// MarkdownParser's own "pragmatic single-pass, not full CommonMark" scope.
struct MarkdownHTMLRenderer {

    static func html(fromMarkdown text: String) -> String {
        guard !text.isEmpty else { return "" }

        let headers = MarkdownParser.parseHeaders(in: text)
        let listItems = MarkdownParser.parseListItems(in: text)
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        let horizontalRules = MarkdownParser.parseHorizontalRules(in: text)
        let codeBlocks = MarkdownParser.parseFencedCodeBlocks(in: text)

        var blocks: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            if let codeBlock = codeBlocks.first(where: { $0.openingFenceRange.lowerBound == index }) {
                let languageAttribute = codeBlock.language.map { " class=\"language-\(htmlEscape($0))\"" } ?? ""
                blocks.append("<pre><code\(languageAttribute)>\(htmlEscape(String(text[codeBlock.contentRange])))</code></pre>")
                index = advance(past: codeBlock.openingFenceRange.lowerBound..<codeBlock.closingFenceRange.upperBound, in: text)
                continue
            }
            if let header = headers.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append("<h\(header.level)>\(inlineHTML(for: String(text[header.contentRange])))</h\(header.level)>")
                index = advance(past: header.lineRange, in: text)
                continue
            }
            if let rule = horizontalRules.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append("<hr>")
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
                blocks.append("<\(tag)>\(items)</\(tag)>")
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
                blocks.append("<blockquote><p>\(inlineHTML(for: groupLines.joined(separator: " ")))</p></blockquote>")
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
            while cursor < text.endIndex, !isBlockStart(at: cursor, headers: headers, listItems: listItems, blockquotes: blockquotes, horizontalRules: horizontalRules, codeBlocks: codeBlocks) {
                let range = lineRange(at: cursor, in: text)
                let line = String(text[range])
                if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
                paragraphLines.append(line)
                cursor = advance(past: range, in: text)
            }
            blocks.append("<p>\(inlineHTML(for: paragraphLines.joined(separator: " ")))</p>")
            index = cursor
        }

        return blocks.joined(separator: "\n")
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
        codeBlocks: [CodeBlockSpan]
    ) -> Bool {
        headers.contains { $0.lineRange.lowerBound == index }
            || listItems.contains { $0.lineRange.lowerBound == index }
            || blockquotes.contains { $0.lineRange.lowerBound == index }
            || horizontalRules.contains { $0.lineRange.lowerBound == index }
            || codeBlocks.contains { $0.openingFenceRange.lowerBound == index }
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

        let explicitLinks = MarkdownParser.parseLinks(in: line)
        // Bare URLs/emails become real anchors in exported HTML and PDF too, matching what the
        // editor shows. Explicit links and inline code are excluded so a URL is never linked
        // twice and a URL shown as sample code stays literal.
        let inlineCodeRanges = MarkdownParser.parseInlineStyles(in: line)
            .filter { $0.kind == .code }
            .map { $0.openingDelimiterRange.lowerBound..<$0.closingDelimiterRange.upperBound }
        let autolinks = MarkdownParser.parseAutolinks(in: line,
                                                      excluding: explicitLinks.map(\.fullRange) + inlineCodeRanges)
        for link in explicitLinks + autolinks {
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
