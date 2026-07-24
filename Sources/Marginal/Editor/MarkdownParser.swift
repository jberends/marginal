import Foundation

/// Underline has no CommonMark syntax, so Marginal represents it with inline
/// HTML `<u>...</u>` — valid CommonMark (raw inline HTML is permitted) and
/// rendered as underlined by other tools (e.g. GitHub).
///
/// This is a pragmatic single-pass parser, not a full CommonMark
/// implementation: it does not apply CommonMark's intraword-emphasis
/// flanking rules (so `snake_case_like_this` can be misdetected as italic).
struct MarkdownParser {

    static func parseInlineStyles(in text: String) -> [InlineStyleSpan] {
        var spans: [InlineStyleSpan] = []
        var claimedRanges: [Range<String.Index>] = []

        func claim(_ range: Range<String.Index>) {
            claimedRanges.append(range)
        }

        // A later (lower-priority) pattern is allowed to match a range that fully contains an
        // already-claimed range -- that's legitimate nesting (e.g. **bold with `code` inside**,
        // where code claims first per the priority order below, and bold's full range
        // necessarily spans across it). It is rejected only when it partially overlaps a claimed
        // range without containing it -- a real conflict between two same-level delimiters.
        func isClaimed(_ range: Range<String.Index>) -> Bool {
            claimedRanges.contains { claimed in
                let overlaps = range.lowerBound < claimed.upperBound && range.upperBound > claimed.lowerBound
                guard overlaps else { return false }
                let fullyContainsClaimed = range.lowerBound <= claimed.lowerBound && range.upperBound >= claimed.upperBound
                return !fullyContainsClaimed
            }
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
        // Delimiter run length is 1-3 backticks (CommonMark: a code span's content may contain a
        // backtick run shorter than its own delimiter, e.g. ``a single ` backtick``); the
        // backreference (\1) requires the closing run to match the opening run's exact length.
        // A backslash immediately before the opening run escapes it -- "\`not code\`" stays literal.
        if let codeRegex = try? NSRegularExpression(pattern: "(?<!\\\\)(`{1,3})(?!`)(.+?)(?<!`)\\1(?!`)") {
            let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
            codeRegex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
                guard let match,
                      let fullRange = Range(match.range, in: text),
                      let delimiterRange = Range(match.range(at: 1), in: text),
                      let contentRange = Range(match.range(at: 2), in: text) else { return }
                if isClaimed(fullRange) { return }

                let delimiterLength = text.distance(from: delimiterRange.lowerBound, to: delimiterRange.upperBound)
                let openStart = fullRange.lowerBound
                let openEnd = text.index(openStart, offsetBy: delimiterLength)
                let closeEnd = fullRange.upperBound
                let closeStart = text.index(closeEnd, offsetBy: -delimiterLength)

                spans.append(InlineStyleSpan(
                    kind: .code,
                    contentRange: contentRange,
                    openingDelimiterRange: openStart..<openEnd,
                    closingDelimiterRange: closeStart..<closeEnd
                ))
                claim(fullRange)
            }
        }
        // Triple delimiters claim next, before plain bold: **/__ would otherwise absorb two of
        // the three delimiter characters and leave the third as stray literal content (the old,
        // documented limitation). Claiming the full ***/___ span first makes the bold pattern's
        // later, narrower match on the same text a partial-overlap conflict that isClaimed
        // correctly rejects, so no separate suppression logic is needed.
        findMatches(pattern: "\\*\\*\\*(.+?)\\*\\*\\*", kind: .boldItalic, openLength: 3, closeLength: 3)
        findMatches(pattern: "___(.+?)___", kind: .boldItalic, openLength: 3, closeLength: 3)
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

        // Nesting depth is derived from leading-space indentation, 2 spaces per level -- a
        // pragmatic fixed unit (not CommonMark's column-based nesting rule), matching common
        // editor conventions. Tabs aren't recognized as indentation (out of scope).
        func level(of line: Substring) -> Int {
            line.prefix { $0 == " " }.count / 2
        }

        func markerContentStart(of line: Substring) -> Substring {
            line[line.prefix { $0 == " " }.endIndex...]
        }

        func unorderedMarkerRange(in line: Substring) -> Range<String.Index>? {
            markerContentStart(of: line).range(of: "^[-*+]( |$)", options: .regularExpression)
        }

        func orderedMarkerRange(in line: Substring) -> Range<String.Index>? {
            markerContentStart(of: line).range(of: "^[0-9]+\\.( |$)", options: .regularExpression)
        }

        func isListMarkerLine(_ line: Substring) -> Bool {
            unorderedMarkerRange(in: line) != nil || orderedMarkerRange(in: line) != nil
        }

        // CommonMark "lazy continuation": a plain line immediately following a list item line,
        // with no blank line between them, is part of that item's paragraph rather than a
        // separate top-level paragraph. Consume such lines until a blank line, a new list
        // marker, or the end of the text.
        func extendedItemEnd(after firstLineEnd: String.Index) -> String.Index {
            var end = firstLineEnd
            var nextLineStart = end < text.endIndex ? text.index(after: end) : text.endIndex
            while nextLineStart < text.endIndex {
                let nextLineEnd = text[nextLineStart...].firstIndex(of: "\n") ?? text.endIndex
                let nextLine = text[nextLineStart..<nextLineEnd]
                if nextLine.trimmingCharacters(in: .whitespaces).isEmpty || isListMarkerLine(nextLine) {
                    break
                }
                end = nextLineEnd
                nextLineStart = end < text.endIndex ? text.index(after: end) : text.endIndex
            }
            return end
        }

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = unorderedMarkerRange(in: line) {
                let itemEnd = extendedItemEnd(after: lineEnd)
                items.append(ListItemSpan(
                    kind: .unordered,
                    level: level(of: line),
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<itemEnd
                ))
                lineStart = itemEnd < text.endIndex ? text.index(after: itemEnd) : text.endIndex
            } else if let markerRange = orderedMarkerRange(in: line) {
                let digits = line[markerRange].prefix { $0.isNumber }
                let itemEnd = extendedItemEnd(after: lineEnd)
                items.append(ListItemSpan(
                    kind: .ordered(number: Int(digits) ?? 0),
                    level: level(of: line),
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<itemEnd
                ))
                lineStart = itemEnd < text.endIndex ? text.index(after: itemEnd) : text.endIndex
            } else {
                lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            }
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

    /// Only recognizes ``` fences (not ~~~) -- a pragmatic subset matching this parser's
    /// established style. An unclosed fence (no matching closing ``` before end of document)
    /// produces no span at all; the rest of the document is treated as plain text.
    ///
    /// Matches CommonMark's fence-length rule: an opening fence may be 3-or-more backticks,
    /// and only closes on a line that is backticks-only (no language tag or other trailing
    /// content) with a count greater-than-or-equal-to the opening fence's count. This lets a
    /// longer outer fence (e.g. four backticks) safely nest a shorter inner example (e.g. a
    /// three-backtick fenced block used as documentation) without the inner fence's closing
    /// line prematurely closing the outer block.
    static func parseFencedCodeBlocks(in text: String) -> [CodeBlockSpan] {
        var blocks: [CodeBlockSpan] = []
        var lineStart = text.startIndex
        var openingFenceRange: Range<String.Index>?
        var openingFenceLength = 0
        var contentStart: String.Index?
        var language: String?

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let backtickCount = trimmed.prefix(while: { $0 == "`" }).count

            if openingFenceRange == nil, backtickCount >= 3 {
                openingFenceRange = lineStart..<lineEnd
                openingFenceLength = backtickCount
                let tag = trimmed.dropFirst(backtickCount).trimmingCharacters(in: .whitespaces)
                language = tag.isEmpty ? nil : tag
                contentStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            } else if openingFenceRange != nil, backtickCount >= openingFenceLength, trimmed.count == backtickCount {
                blocks.append(CodeBlockSpan(
                    openingFenceRange: openingFenceRange!,
                    contentRange: contentStart!..<lineStart,
                    closingFenceRange: lineStart..<lineEnd,
                    language: language
                ))
                openingFenceRange = nil
                contentStart = nil
                language = nil
            }

            if lineEnd >= text.endIndex { break }
            lineStart = text.index(after: lineEnd)
        }
        return blocks
    }

    /// Basic, language-agnostic heuristic highlighting -- not a real tokenizer. Order matters:
    /// strings claim first so a "#"/"//" INSIDE a string literal isn't later mistaken for a
    /// comment marker (the comment regex's match would overlap the already-claimed string
    /// range and get skipped by the isClaimed check).
    ///
    /// Known v1 limitation: this only protects strings-containing-comment-markers, not the
    /// reverse (e.g. a "#"/"//" that starts a real comment whose text happens to contain a
    /// quote character can still misparse) -- acceptable for a basic heuristic highlighter,
    /// not a real tokenizer.
    static func parseCodeHighlightTokens(in codeText: String) -> [CodeHighlightToken] {
        var tokens: [CodeHighlightToken] = []
        var claimed = Set<Int>()

        func offset(_ index: String.Index) -> Int {
            codeText.distance(from: codeText.startIndex, to: index)
        }
        func claim(_ range: Range<String.Index>) {
            for i in offset(range.lowerBound)..<offset(range.upperBound) { claimed.insert(i) }
        }
        func isClaimed(_ range: Range<String.Index>) -> Bool {
            for i in offset(range.lowerBound)..<offset(range.upperBound) where claimed.contains(i) { return true }
            return false
        }

        func findMatches(pattern: String, kind: CodeTokenKind) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsrange = NSRange(codeText.startIndex..<codeText.endIndex, in: codeText)
            regex.enumerateMatches(in: codeText, range: nsrange) { match, _, _ in
                guard let match, let fullRange = Range(match.range, in: codeText) else { return }
                if isClaimed(fullRange) { return }
                tokens.append(CodeHighlightToken(kind: kind, range: fullRange))
                claim(fullRange)
            }
        }

        findMatches(pattern: "\"[^\"\\n]*\"", kind: .string)
        findMatches(pattern: "'[^'\\n]*'", kind: .string)
        findMatches(pattern: "//[^\\n]*", kind: .comment)
        findMatches(pattern: "#[^\\n]*", kind: .comment)
        findMatches(pattern: "\\b\\d+(\\.\\d+)?\\b", kind: .number)

        return tokens
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
