import Foundation

/// Live inline autoformatting (Notion behavior row 8) and selection style toggles.
enum InlineAutoformat {
    /// Called right after a character insertion. Scans backward from `caret` in
    /// `text.plainText` for a just-completed `**bold**` / `*italic*` / `` `code` `` /
    /// `~~strikethrough~~` pattern ending exactly at `caret`. Returns the text with the
    /// delimiters removed and the matched content styled (existing styles preserved),
    /// plus the caret adjusted to sit right after the styled content. Returns nil when
    /// no pattern was just completed.
    static func convertCompletedPattern(in text: InlineText, caret: Int) -> (InlineText, caret: Int)? {
        let chars = Array(text.plainText)
        guard caret >= 0 && caret <= chars.count else { return nil }

        if let result = tryPattern(chars: chars, text: text, caret: caret, delim: ["*", "*"], style: .bold, isolate: false) {
            return result
        }
        if let result = tryPattern(chars: chars, text: text, caret: caret, delim: ["~", "~"], style: .strikethrough, isolate: false) {
            return result
        }
        if let result = tryPattern(chars: chars, text: text, caret: caret, delim: ["`"], style: .code, isolate: false) {
            return result
        }
        if let result = tryPattern(chars: chars, text: text, caret: caret, delim: ["*"], style: .italic, isolate: true) {
            return result
        }
        return nil
    }

    /// Toggles `style` across the character range `range`. If every character in the
    /// range already has the style, it is removed from all of them; otherwise it is
    /// added to all of them. Other styles and links are preserved. Out-of-range or
    /// empty ranges return `text` unchanged.
    static func toggling(_ text: InlineText, range: Range<Int>, style: InlineStyle) -> InlineText {
        guard range.lowerBound >= 0, range.upperBound <= text.length, !range.isEmpty else {
            return text
        }

        let (before, rest) = text.split(at: range.lowerBound)
        let (middle, after) = rest.split(at: range.upperBound - range.lowerBound)

        let allHaveStyle = !middle.runs.isEmpty && middle.runs.allSatisfy { $0.style.contains(style) }

        let newMiddleRuns = middle.runs.map { run -> InlineRun in
            var newStyle = run.style
            if allHaveStyle {
                newStyle.remove(style)
            } else {
                newStyle.insert(style)
            }
            return InlineRun(text: run.text, style: newStyle, linkURL: run.linkURL)
        }

        var result = before
        result.append(InlineText(runs: newMiddleRuns))
        result.append(after)
        return result
    }

    // MARK: - Pattern matching

    private static func tryPattern(
        chars: [Character],
        text: InlineText,
        caret: Int,
        delim: [Character],
        style: InlineStyle,
        isolate: Bool
    ) -> (InlineText, caret: Int)? {
        let delimLen = delim.count
        guard caret >= delimLen else { return nil }
        guard Array(chars[(caret - delimLen)..<caret]) == delim else { return nil }

        let closingStart = caret - delimLen
        var openingStart = closingStart - delimLen

        while openingStart >= 0 {
            if Array(chars[openingStart..<(openingStart + delimLen)]) == delim {
                let isolationOK = !isolate || openingStart == 0 || chars[openingStart - 1] != delim[0]
                if isolationOK {
                    let contentStart = openingStart + delimLen
                    let contentEnd = closingStart
                    if contentStart < contentEnd {
                        let content = chars[contentStart..<contentEnd]
                        if !content.contains(where: { delim.contains($0) }) {
                            return buildResult(
                                text: text,
                                openingStart: openingStart,
                                delimLen: delimLen,
                                contentEnd: contentEnd,
                                caret: caret,
                                style: style
                            )
                        }
                    }
                }
            }
            openingStart -= 1
        }

        return nil
    }

    private static func buildResult(
        text: InlineText,
        openingStart: Int,
        delimLen: Int,
        contentEnd: Int,
        caret: Int,
        style: InlineStyle
    ) -> (InlineText, caret: Int) {
        let (before, rest1) = text.split(at: openingStart)
        let (_, rest2) = rest1.split(at: delimLen) // drop opening delimiter
        let (content, rest3) = rest2.split(at: contentEnd - (openingStart + delimLen))
        let (_, after) = rest3.split(at: delimLen) // drop closing delimiter

        let styledContent = InlineText(runs: content.runs.map {
            InlineRun(text: $0.text, style: $0.style.union(style), linkURL: $0.linkURL)
        })

        var result = before
        result.append(styledContent)
        result.append(after)

        return (result, before.length + styledContent.length)
    }
}
