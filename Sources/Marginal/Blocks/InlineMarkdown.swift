import Foundation

/// Converts between plain inline markdown fragments (a single block's text, e.g. a paragraph or
/// heading's content) and the structured `InlineText` run model, reusing the span parsers in
/// `MarkdownParser`.
enum InlineMarkdown {

    static func parse(_ fragment: String) -> InlineText {
        let styleSpans = MarkdownParser.parseInlineStyles(in: fragment)
        let linkSpans = MarkdownParser.parseLinks(in: fragment)
        let emojiSpans = MarkdownParser.parseEmojiShortcodes(in: fragment)

        func style(at index: String.Index) -> InlineStyle {
            var result: InlineStyle = []
            for span in styleSpans where span.contentRange.contains(index) {
                switch span.kind {
                case .bold: result.insert(.bold)
                case .italic: result.insert(.italic)
                case .boldItalic: result.insert([.bold, .italic])
                case .strikethrough: result.insert(.strikethrough)
                case .underline: result.insert(.underline)
                case .code: result.insert(.code)
                }
            }
            return result
        }

        func linkURL(at index: String.Index) -> String? {
            for link in linkSpans where link.textRange.contains(index) {
                return link.url
            }
            return nil
        }

        // Delimiter characters (style open/close markers, and the "[" / "](url)" link syntax
        // around a link's text) are excluded from the output -- only the styled/linked content
        // itself becomes a run.
        func isDelimiter(_ index: String.Index) -> Bool {
            for span in styleSpans {
                if span.openingDelimiterRange.contains(index) || span.closingDelimiterRange.contains(index) {
                    return true
                }
            }
            for link in linkSpans {
                if index >= link.fullRange.lowerBound && index < link.textRange.lowerBound {
                    return true
                }
                if index >= link.textRange.upperBound && index < link.fullRange.upperBound {
                    return true
                }
            }
            return false
        }

        var runs: [InlineRun] = []
        var index = fragment.startIndex
        while index < fragment.endIndex {
            // Emoji shortcodes normalize to the literal emoji character at parse time.
            if let emoji = emojiSpans.first(where: { $0.fullRange.lowerBound == index }) {
                runs.append(InlineRun(text: emoji.emoji, style: style(at: index), linkURL: linkURL(at: index)))
                index = emoji.fullRange.upperBound
                continue
            }
            if isDelimiter(index) {
                index = fragment.index(after: index)
                continue
            }
            runs.append(InlineRun(text: String(fragment[index]), style: style(at: index), linkURL: linkURL(at: index)))
            index = fragment.index(after: index)
        }

        return InlineText(runs: runs)
    }

    /// Delimiter order, outermost to innermost: `***` for [.bold, .italic] combined (else `**`,
    /// `*`), then `~~`, then `<u></u>`, then backticks last (closest to the raw text). A run with
    /// a `linkURL` wraps its (possibly already-delimited) text as `[text](url)` last of all.
    static func serialize(_ text: InlineText) -> String {
        var result = ""
        for run in text.runs {
            var inner = run.text

            if run.style.contains(.code) {
                inner = "`\(inner)`"
            }
            if run.style.contains(.underline) {
                inner = "<u>\(inner)</u>"
            }
            if run.style.contains(.strikethrough) {
                inner = "~~\(inner)~~"
            }
            if run.style.contains([.bold, .italic]) {
                inner = "***\(inner)***"
            } else if run.style.contains(.bold) {
                inner = "**\(inner)**"
            } else if run.style.contains(.italic) {
                inner = "*\(inner)*"
            }
            if let url = run.linkURL {
                inner = "[\(inner)](\(url))"
            }

            result += inner
        }
        return result
    }
}
