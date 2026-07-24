import Foundation

/// Underline has no CommonMark syntax, so Marginal represents it with inline
/// HTML `<u>...</u>` — valid CommonMark (raw inline HTML is permitted) and
/// rendered as underlined by other tools (e.g. GitHub).
///
/// This is a pragmatic single-pass parser, not a full CommonMark
/// implementation: it does not apply CommonMark's intraword-emphasis
/// flanking rules (so `snake_case_like_this` can be misdetected as italic),
/// and `***bold+italic***` nesting is only partially handled (recognized as
/// bold, with the extra asterisk left as a literal character).
struct MarkdownParser {

    static func parseInlineStyles(in text: String) -> [InlineStyleSpan] {
        var spans: [InlineStyleSpan] = []
        var claimed = Set<Int>()

        func offset(_ index: String.Index) -> Int {
            text.distance(from: text.startIndex, to: index)
        }

        func claim(_ range: Range<String.Index>) {
            for i in offset(range.lowerBound)..<offset(range.upperBound) {
                claimed.insert(i)
            }
        }

        func isClaimed(_ range: Range<String.Index>) -> Bool {
            for i in offset(range.lowerBound)..<offset(range.upperBound) where claimed.contains(i) {
                return true
            }
            return false
        }

        func findMatches(pattern: String, kind: InlineStyleKind, openLength: Int, closeLength: Int) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
                guard let match,
                      let fullRange = Range(match.range, in: text),
                      let contentRange = Range(match.range(at: 1), in: text) else { return }
                if isClaimed(fullRange) { return }

                let openStart = fullRange.lowerBound
                let openEnd = text.index(openStart, offsetBy: openLength)
                let closeEnd = fullRange.upperBound
                let closeStart = text.index(closeEnd, offsetBy: -closeLength)

                spans.append(InlineStyleSpan(
                    kind: kind,
                    contentRange: contentRange,
                    openingDelimiterRange: openStart..<openEnd,
                    closingDelimiterRange: closeStart..<closeEnd
                ))
                claim(fullRange)
            }
        }

        // Order matters: higher-priority (longer/more specific) delimiters
        // claim their ranges first so shorter delimiters don't cut through them.
        // Inline code claims first: its content must never be reinterpreted as bold/italic/etc.
        findMatches(pattern: "`([^`\\n]+?)`", kind: .code, openLength: 1, closeLength: 1)
        findMatches(pattern: "\\*\\*(.+?)\\*\\*", kind: .bold, openLength: 2, closeLength: 2)
        findMatches(pattern: "__(.+?)__", kind: .bold, openLength: 2, closeLength: 2)
        findMatches(pattern: "~~(.+?)~~", kind: .strikethrough, openLength: 2, closeLength: 2)
        findMatches(pattern: "<u>(.+?)</u>", kind: .underline, openLength: 3, closeLength: 4)
        findMatches(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", kind: .italic, openLength: 1, closeLength: 1)
        findMatches(pattern: "(?<!_)_([^_\\n]+?)_(?!_)", kind: .italic, openLength: 1, closeLength: 1)

        return spans.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }
    }

    static func parseHeaders(in text: String) -> [HeaderSpan] {
        var headers: [HeaderSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = line.range(of: "^#{1,6} ", options: .regularExpression) {
                let level = line.distance(from: markerRange.lowerBound, to: markerRange.upperBound) - 1
                headers.append(HeaderSpan(
                    level: level,
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return headers
    }

    static func parseListItems(in text: String) -> [ListItemSpan] {
        var items: [ListItemSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = line.range(of: "^[-*+] ", options: .regularExpression) {
                items.append(ListItemSpan(
                    kind: .unordered,
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            } else if let markerRange = line.range(of: "^[0-9]+\\. ", options: .regularExpression) {
                let digits = line[markerRange].prefix { $0.isNumber }
                items.append(ListItemSpan(
                    kind: .ordered(number: Int(digits) ?? 0),
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return items
    }

    /// Single-level only: a line's leading ">" marks it as a blockquote line. Any additional
    /// ">" characters are treated as literal content, not further nesting -- known v1 limitation,
    /// matching Phase 1's single-level-lists precedent.
    static func parseBlockquotes(in text: String) -> [BlockquoteSpan] {
        var blockquotes: [BlockquoteSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = line.range(of: "^> ?", options: .regularExpression) {
                blockquotes.append(BlockquoteSpan(
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return blockquotes
    }

    /// Pragmatic subset of CommonMark's thematic-break rule: exactly "---", "***", or "___" on
    /// their own line (no interior spaces, no other repetition counts) -- matches this parser's
    /// established single-pass, not-full-CommonMark style.
    static func parseHorizontalRules(in text: String) -> [HorizontalRuleSpan] {
        var rules: [HorizontalRuleSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if line == "---" || line == "***" || line == "___" {
                rules.append(HorizontalRuleSpan(lineRange: lineStart..<lineEnd))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return rules
    }

    static func parseLinks(in text: String) -> [LinkSpan] {
        var links: [LinkSpan] = []
        guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") else { return links }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let textRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { return }
            links.append(LinkSpan(textRange: textRange, urlRange: urlRange, fullRange: fullRange, url: String(text[urlRange])))
        }
        return links
    }
}
