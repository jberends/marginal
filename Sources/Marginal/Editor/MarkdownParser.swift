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

        // Emoji shortcodes claim first, highest priority: many contain underscores between
        // words (":white_check_mark:") which would otherwise be misdetected as italic by the
        // italic pattern below (this parser doesn't implement CommonMark's intraword-emphasis
        // flanking rules -- see the type doc comment).
        for shortcode in parseEmojiShortcodes(in: text) {
            claim(shortcode.fullRange)
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

        // GFM task-list checkbox: only recognized on unordered items, matching convention.
        func taskCheckbox(in content: Substring) -> (state: TaskState, matchRange: Range<String.Index>)? {
            guard let matchRange = content.range(of: "^\\[([ xX])\\] ", options: .regularExpression) else { return nil }
            let stateChar = content[content.index(after: matchRange.lowerBound)]
            return (stateChar == "x" || stateChar == "X") ? (.complete, matchRange) : (.incomplete, matchRange)
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
                let checkbox = taskCheckbox(in: text[markerRange.upperBound..<lineEnd])
                items.append(ListItemSpan(
                    kind: .unordered,
                    level: level(of: line),
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<itemEnd,
                    taskState: checkbox?.state,
                    taskMarkerRange: checkbox?.matchRange
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
                    lineRange: lineStart..<itemEnd,
                    taskState: nil,
                    taskMarkerRange: nil
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

    /// Requires both a leading and trailing "|" on every row -- the vast majority of real-world
    /// pipe tables, and a pragmatic subset matching this parser's established style (a table row
    /// without outer pipes, e.g. "a | b", is not recognized). A header row immediately followed by
    /// a valid alignment separator row starts a table; every subsequent consecutive row-shaped
    /// line becomes a body row, until a line that isn't row-shaped, a blank line, or the end of
    /// text. Escaped pipes ("\|") do not split a cell.
    static func parseTables(in text: String) -> [TableSpan] {
        var tables: [TableSpan] = []
        var lineStart = text.startIndex

        func lineRange(at start: String.Index) -> Range<String.Index> {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            return start..<end
        }

        func pipePositions(in range: Range<String.Index>) -> [String.Index] {
            var positions: [String.Index] = []
            var i = range.lowerBound
            while i < range.upperBound {
                if text[i] == "|" {
                    let isEscaped = i > range.lowerBound && text[text.index(before: i)] == "\\"
                    if !isEscaped { positions.append(i) }
                }
                i = text.index(after: i)
            }
            return positions
        }

        func isTableRow(_ range: Range<String.Index>) -> Bool {
            let line = text[range]
            guard line.hasPrefix("|"), line.hasSuffix("|") else { return false }
            return pipePositions(in: range).count >= 2
        }

        func isSeparatorRow(_ range: Range<String.Index>) -> Bool {
            text[range].range(of: "^\\|(\\s*:?-+:?\\s*\\|)+$", options: .regularExpression) != nil
        }

        func alignments(fromSeparator range: Range<String.Index>) -> [TableAlignment] {
            let pipes = pipePositions(in: range)
            guard pipes.count >= 2 else { return [] }
            return (0..<(pipes.count - 1)).map { i in
                let cell = text[text.index(after: pipes[i])..<pipes[i + 1]].trimmingCharacters(in: .whitespaces)
                switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                case (true, true): return .center
                case (false, true): return .right
                default: return .left
                }
            }
        }

        func row(for range: Range<String.Index>) -> TableRowSpan {
            TableRowSpan(lineRange: range, pipeRanges: pipePositions(in: range).map { $0..<text.index(after: $0) })
        }

        while lineStart < text.endIndex {
            let headerRange = lineRange(at: lineStart)
            if isTableRow(headerRange), headerRange.upperBound < text.endIndex {
                let separatorRange = lineRange(at: text.index(after: headerRange.upperBound))
                if isSeparatorRow(separatorRange) {
                    var bodyRows: [TableRowSpan] = []
                    var cursor = separatorRange.upperBound < text.endIndex ? text.index(after: separatorRange.upperBound) : text.endIndex
                    while cursor < text.endIndex {
                        let rowRange = lineRange(at: cursor)
                        guard isTableRow(rowRange) else { break }
                        bodyRows.append(row(for: rowRange))
                        cursor = rowRange.upperBound < text.endIndex ? text.index(after: rowRange.upperBound) : text.endIndex
                    }
                    tables.append(TableSpan(
                        headerRow: row(for: headerRange),
                        separatorRowRange: separatorRange,
                        bodyRows: bodyRows,
                        columnAlignments: alignments(fromSeparator: separatorRange)
                    ))
                    lineStart = cursor
                    continue
                }
            }
            lineStart = headerRange.upperBound < text.endIndex ? text.index(after: headerRange.upperBound) : text.endIndex
        }
        return tables
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

    /// Only recognizes ":word:" sequences that match a known GFM/gemoji alias (see
    /// GemojiTable.swift) -- an unrecognized ":word:" (e.g. a literal time-like ":thinking:" typo
    /// or unrelated colon-wrapped text) is left as plain text, not guessed at.
    static func parseEmojiShortcodes(in text: String) -> [EmojiShortcodeSpan] {
        var spans: [EmojiShortcodeSpan] = []
        guard let regex = try? NSRegularExpression(pattern: ":([a-zA-Z0-9_+-]+):") else { return spans }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let aliasRange = Range(match.range(at: 1), in: text),
                  let emoji = GemojiTable.shortcodeToEmoji[String(text[aliasRange])] else { return }
            spans.append(EmojiShortcodeSpan(fullRange: fullRange, emoji: emoji))
        }
        return spans
    }
}

// MARK: - Autolinks

extension MarkdownParser {
    /// Bare URLs and email addresses written straight into the prose -- no `[text](url)` syntax.
    /// Returns them as `LinkSpan`s whose text/url/full ranges are all the URL itself, so the
    /// styler and the HTML renderer can treat them exactly like an explicit markdown link that
    /// happens to have no delimiters to hide.
    ///
    /// `claimed` ranges are skipped: pass the `fullRange`s of the explicit markdown links (so the
    /// URL inside `[text](url)` isn't linked twice) and of inline code spans (a URL inside
    /// backticks is sample text, not a link).
    ///
    /// Trailing punctuation follows GFM's autolink rules, which exist because a URL at the end of
    /// a sentence is far more common than a URL that genuinely ends in punctuation:
    /// `https://example.com.` links without the full stop, `(https://example.com/path).` drops
    /// both the paren and the stop, but `…/Markdown_(markup_language)` keeps its closing paren
    /// because the parens inside the URL balance.
    static func parseAutolinks(in text: String, excluding claimed: [Range<String.Index>] = []) -> [LinkSpan] {
        var spans: [LinkSpan] = []

        func isClaimed(_ range: Range<String.Index>) -> Bool {
            claimed.contains { $0.lowerBound < range.upperBound && $0.upperBound > range.lowerBound }
        }

        func appendMatches(pattern: String, isEmail: Bool) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
                guard let match, var range = Range(match.range, in: text) else { return }
                guard let trimmed = trimmingAutolinkTrailingPunctuation(range, in: text) else { return }
                range = trimmed
                guard !isClaimed(range) else { return }
                let raw = String(text[range])
                spans.append(LinkSpan(textRange: range,
                                      urlRange: range,
                                      fullRange: range,
                                      url: isEmail ? "mailto:\(raw)" : raw))
            }
        }

        // A scheme'd URL runs to the first whitespace or angle bracket; the trailing-punctuation
        // pass below decides where it really ends. The lookbehind keeps it from starting midway
        // through a longer token.
        appendMatches(pattern: "(?<![A-Za-z0-9._%+-])https?://[^\\s<>]+", isEmail: false)
        // Email: local@domain.tld. Requires a dotted domain so "a@b" in prose isn't linked.
        appendMatches(pattern: "(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}", isEmail: true)

        return spans.sorted { $0.fullRange.lowerBound < $1.fullRange.lowerBound }
    }

    /// Walks back off the end of an autolink candidate while the last character is punctuation
    /// that reads as sentence punctuation rather than part of the address. A closing bracket is
    /// only dropped when it is unbalanced within the candidate -- that is what lets a Wikipedia
    /// URL keep its `(markup_language)` suffix while `(https://example.com/path)` loses the paren
    /// that was wrapping it. Returns nil if nothing is left.
    private static func trimmingAutolinkTrailingPunctuation(_ range: Range<String.Index>,
                                                            in text: String) -> Range<String.Index>? {
        // Not "_" or "~": those are legitimate, common URL characters (…/some_path/file_name).
        let sentencePunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", "\"", "'", "*"]
        let brackets: [Character: Character] = [")": "(", "]": "[", "}": "{"]

        var end = range.upperBound
        while end > range.lowerBound {
            let last = text[text.index(before: end)]
            if sentencePunctuation.contains(last) {
                end = text.index(before: end)
                continue
            }
            if let opener = brackets[last] {
                let candidate = text[range.lowerBound..<end]
                let opens = candidate.filter { $0 == opener }.count
                let closes = candidate.filter { $0 == last }.count
                if closes > opens {
                    end = text.index(before: end)
                    continue
                }
            }
            break
        }

        guard end > range.lowerBound else { return nil }
        let trimmed = range.lowerBound..<end
        // "https://" on its own isn't a link.
        return String(text[trimmed]).hasSuffix("//") ? nil : trimmed
    }
}

// MARK: - Display substitutions

/// A run of source characters that should *display* as something else while the file on disk keeps
/// the literal characters the user typed -- HTML entities (`&copy;` shown as ©) and typographic
/// replacements (`--` shown as –). The same idea as the existing `:shortcode:` → emoji handling,
/// and it reuses that drawing path in MarkdownLayoutManager.
struct DisplaySubstitutionSpan: Equatable {
    let range: Range<String.Index>
    let replacement: String
}

extension MarkdownParser {
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "plusmn": "±", "times": "×",
        "divide": "÷", "frac12": "½", "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³",
        "micro": "µ", "para": "¶", "sect": "§", "dagger": "†", "Dagger": "‡", "bull": "•",
        "middot": "·", "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "\u{2018}",
        "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "laquo": "«", "raquo": "»",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "permil": "‰",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔",
        "ne": "≠", "le": "≤", "ge": "≥", "infin": "∞", "asymp": "≈", "equiv": "≡", "radic": "√"
    ]

    /// HTML entities -- named (`&copy;`), decimal (`&#169;`) and hexadecimal (`&#x00A9;`).
    static func parseHTMLEntities(in text: String) -> [DisplaySubstitutionSpan] {
        guard let regex = try? NSRegularExpression(pattern: "&(#[Xx][0-9A-Fa-f]+|#[0-9]+|[A-Za-z][A-Za-z0-9]{1,31});") else { return [] }
        var spans: [DisplaySubstitutionSpan] = []
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
            guard let match,
                  let full = Range(match.range, in: text),
                  let body = Range(match.range(at: 1), in: text) else { return }
            let token = String(text[body])
            var replacement: String?
            if token.hasPrefix("#x") || token.hasPrefix("#X") {
                if let value = UInt32(token.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) {
                    replacement = String(Character(scalar))
                }
            } else if token.hasPrefix("#") {
                if let value = UInt32(token.dropFirst()), let scalar = Unicode.Scalar(value) {
                    replacement = String(Character(scalar))
                }
            } else {
                replacement = namedEntities[token]
            }
            guard let replacement else { return }
            spans.append(DisplaySubstitutionSpan(range: full, replacement: replacement))
        }
        return spans
    }

    /// Typographic substitution: straight quotes become curly, `...` becomes an ellipsis, `--` an
    /// en dash and `---` an em dash. Done at *display* time only -- AppKit's own automatic
    /// substitution is deliberately disabled on the text view because it rewrites the buffer
    /// before the parser ever sees it, which silently turned a typed `---` into an em dash and
    /// broke horizontal rules.
    static func parseTypographicSubstitutions(in text: String) -> [DisplaySubstitutionSpan] {
        var spans: [DisplaySubstitutionSpan] = []
        let characters = Array(text)
        let indices = Array(text.indices)
        var i = 0

        func character(at offset: Int) -> Character? {
            (offset >= 0 && offset < characters.count) ? characters[offset] : nil
        }
        /// A quote opens when what precedes it is nothing, whitespace, or an opening bracket.
        func isOpening(before offset: Int) -> Bool {
            guard let previous = character(at: offset - 1) else { return true }
            return previous.isWhitespace || "([{-–—/".contains(previous)
        }

        while i < characters.count {
            let c = characters[i]
            let start = indices[i]

            /// The index `count` characters after `i`, clamped to the end of the text.
            func end(after count: Int) -> String.Index {
                i + count < indices.count ? indices[i + count] : text.endIndex
            }

            if c == ".", character(at: i + 1) == ".", character(at: i + 2) == "." {
                spans.append(DisplaySubstitutionSpan(range: start..<end(after: 3), replacement: "…"))
                i += 3
                continue
            }
            if c == "-", character(at: i + 1) == "-" {
                let isEmDash = character(at: i + 2) == "-"
                let length = isEmDash ? 3 : 2
                spans.append(DisplaySubstitutionSpan(range: start..<end(after: length),
                                                    replacement: isEmDash ? "—" : "–"))
                i += length
                continue
            }
            if c == "\"" {
                spans.append(DisplaySubstitutionSpan(range: start..<end(after: 1),
                                                    replacement: isOpening(before: i) ? "\u{201C}" : "\u{201D}"))
                i += 1
                continue
            }
            if c == "'" {
                spans.append(DisplaySubstitutionSpan(range: start..<end(after: 1),
                                                    replacement: isOpening(before: i) ? "\u{2018}" : "\u{2019}"))
                i += 1
                continue
            }
            i += 1
        }
        return spans
    }
}
