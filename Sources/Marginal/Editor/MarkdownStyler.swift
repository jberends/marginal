import AppKit

struct MarkdownStyler {

    static let hiddenDelimiterFontSize: CGFloat = 0.1

    static func attributedString(
        for text: String,
        model: MarkdownDocumentModel,
        baseFont: NSFont,
        cursorLocation: String.Index?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ])

        let revealedStyles = cursorLocation.map {
            CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: $0)
        } ?? []
        let revealedHeaders = cursorLocation.map {
            CursorRevealController.revealedHeaderSpans(in: model, cursorLocation: $0)
        } ?? []
        let hiddenFont = NSFont.systemFont(ofSize: hiddenDelimiterFontSize)

        // Code blocks are parsed independently from every other span type and share no "claimed
        // ranges" mechanism with them, so a span from another parser (header/link/blockquote/
        // horizontal-rule/list-item/inline-style) can end up with a range that falls entirely
        // inside a fenced code block -- e.g. a YAML "- item" line, a "[text](url)" link, or a
        // "---" separator shown as example code. Filter those out before styling so code block
        // content and its fences only ever get code styling, never reinterpreted as markdown.
        func overlapsAnyCodeBlock(_ range: Range<String.Index>) -> Bool {
            model.codeBlocks.contains { codeBlock in
                let blockRange = codeBlock.openingFenceRange.lowerBound..<codeBlock.closingFenceRange.upperBound
                return range.lowerBound < blockRange.upperBound && range.upperBound > blockRange.lowerBound
            }
        }

        let headers = model.headers.filter { !overlapsAnyCodeBlock($0.lineRange) }
        let inlineStyles = model.inlineStyles.filter { !overlapsAnyCodeBlock($0.openingDelimiterRange.lowerBound..<$0.closingDelimiterRange.upperBound) }
        let links = model.links.filter { !overlapsAnyCodeBlock($0.fullRange) }
        let blockquotes = model.blockquotes.filter { !overlapsAnyCodeBlock($0.lineRange) }
        let horizontalRules = model.horizontalRules.filter { !overlapsAnyCodeBlock($0.lineRange) }
        let listItems = model.listItems.filter { !overlapsAnyCodeBlock($0.lineRange) }

        for header in headers {
            let headerFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: headerPointSize(for: header.level, baseSize: baseFont.pointSize)),
                toHaveTrait: .boldFontMask
            )
            result.addAttribute(.font, value: headerFont, range: NSRange(header.contentRange, in: text))

            let markerRange = NSRange(header.markerRange, in: text)
            result.addAttribute(.font, value: revealedHeaders.contains(header) ? headerFont : hiddenFont, range: markerRange)
        }

        // Blockquotes style their whole content range with a blanket italic font/color before
        // inlineStyles and links run, so those narrower, nested spans (e.g. bold or a link inside
        // a quoted line) layer their own font/color on top afterward instead of being clobbered by
        // this loop's blanket range if it ran later.
        let revealedBlockquotes = cursorLocation.map {
            CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: $0)
        } ?? []

        // Gap between the drawn left bar and the quoted text -- scales with type size (per Apple's
        // HIG guidance to size spacing relative to text rather than a fixed pixel value) rather
        // than a marker-derived width, since there's no marker character to align content under.
        let blockquoteContentIndent = baseFont.pointSize * 0.75

        for blockquote in blockquotes {
            let markerRange = NSRange(blockquote.markerRange, in: text)
            let contentRange = NSRange(blockquote.contentRange, in: text)
            result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask), range: contentRange)
            result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: contentRange)
            result.addAttribute(.marginalBlockquoteMarker, value: true, range: NSRange(blockquote.lineRange, in: text))

            let quoteParagraphStyle = NSMutableParagraphStyle()
            quoteParagraphStyle.firstLineHeadIndent = blockquoteContentIndent
            quoteParagraphStyle.headIndent = blockquoteContentIndent
            result.addAttribute(.paragraphStyle, value: quoteParagraphStyle, range: NSRange(blockquote.lineRange, in: text))

            let markerFont = revealedBlockquotes.contains(blockquote) ? baseFont : hiddenFont
            if markerRange.length > 0 {
                result.addAttribute(.font, value: markerFont, range: markerRange)
            }
        }

        for span in inlineStyles {
            let contentRange = NSRange(span.contentRange, in: text)
            // A span nested inside a header (e.g. "# **Bold Header**") must keep the header's
            // larger font size -- this loop runs after headers, so hard-coding baseFont here
            // would shrink the nested span back down to editor-content size.
            let spanBaseFont: NSFont
            if let header = headers.first(where: { $0.contentRange.contains(span.contentRange.lowerBound) }) {
                spanBaseFont = NSFont.systemFont(ofSize: headerPointSize(for: header.level, baseSize: baseFont.pointSize))
            } else {
                spanBaseFont = baseFont
            }
            switch span.kind {
            case .bold:
                result.addAttribute(.font, value: NSFontManager.shared.convert(spanBaseFont, toHaveTrait: .boldFontMask), range: contentRange)
            case .italic:
                result.addAttribute(.font, value: NSFontManager.shared.convert(spanBaseFont, toHaveTrait: .italicFontMask), range: contentRange)
            case .boldItalic:
                result.addAttribute(.font, value: NSFontManager.shared.convert(spanBaseFont, toHaveTrait: [.boldFontMask, .italicFontMask]), range: contentRange)
            case .strikethrough:
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            case .underline:
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            case .code:
                result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: spanBaseFont.pointSize, weight: .regular), range: contentRange)
                result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentRange)
            }

            let delimiterFont = revealedStyles.contains(span) ? spanBaseFont : hiddenFont
            result.addAttribute(.font, value: delimiterFont, range: NSRange(span.openingDelimiterRange, in: text))
            result.addAttribute(.font, value: delimiterFont, range: NSRange(span.closingDelimiterRange, in: text))
        }

        let revealedLinks = cursorLocation.map {
            CursorRevealController.revealedLinkSpans(in: model, cursorLocation: $0)
        } ?? []

        for link in links {
            let textRange = NSRange(link.textRange, in: text)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            result.addAttribute(.link, value: link.url, range: textRange)

            let delimiterFont = revealedLinks.contains(link) ? baseFont : hiddenFont
            let fullNSRange = NSRange(link.fullRange, in: text)
            let prefixRange = NSRange(location: fullNSRange.location, length: textRange.location - fullNSRange.location)
            let suffixRange = NSRange(location: textRange.location + textRange.length, length: fullNSRange.location + fullNSRange.length - (textRange.location + textRange.length))
            if prefixRange.length > 0 {
                result.addAttribute(.font, value: delimiterFont, range: prefixRange)
            }
            if suffixRange.length > 0 {
                result.addAttribute(.font, value: delimiterFont, range: suffixRange)
            }
        }

        let revealedHorizontalRules = cursorLocation.map {
            CursorRevealController.revealedHorizontalRuleSpans(in: model, cursorLocation: $0)
        } ?? []

        for rule in horizontalRules {
            let lineNSRange = NSRange(rule.lineRange, in: text)
            result.addAttribute(.marginalHorizontalRuleMarker, value: true, range: lineNSRange)
            let ruleFont = revealedHorizontalRules.contains(rule) ? baseFont : hiddenFont
            result.addAttribute(.font, value: ruleFont, range: lineNSRange)
        }

        let revealedCodeBlocks = cursorLocation.map {
            CursorRevealController.revealedCodeBlockSpans(in: model, cursorLocation: $0)
        } ?? []

        for codeBlock in model.codeBlocks {
            let contentNSRange = NSRange(codeBlock.contentRange, in: text)
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            result.addAttribute(.font, value: codeFont, range: contentNSRange)
            result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentNSRange)

            let codeText = String(text[codeBlock.contentRange])
            for token in MarkdownParser.parseCodeHighlightTokens(in: codeText) {
                let startOffset = codeText.distance(from: codeText.startIndex, to: token.range.lowerBound)
                let endOffset = codeText.distance(from: codeText.startIndex, to: token.range.upperBound)
                guard let tokenStart = text.index(codeBlock.contentRange.lowerBound, offsetBy: startOffset, limitedBy: text.endIndex),
                      let tokenEnd = text.index(codeBlock.contentRange.lowerBound, offsetBy: endOffset, limitedBy: text.endIndex) else { continue }
                let tokenColor: NSColor
                switch token.kind {
                case .string: tokenColor = NSColor.systemGreen
                case .comment: tokenColor = NSColor.secondaryLabelColor
                case .number: tokenColor = NSColor.systemPurple
                }
                result.addAttribute(.foregroundColor, value: tokenColor, range: NSRange(tokenStart..<tokenEnd, in: text))
            }

            let fenceFont = revealedCodeBlocks.contains(codeBlock) ? baseFont : hiddenFont
            result.addAttribute(.font, value: fenceFont, range: NSRange(codeBlock.openingFenceRange, in: text))
            result.addAttribute(.font, value: fenceFont, range: NSRange(codeBlock.closingFenceRange, in: text))
        }

        func sameListKind(_ a: ListMarkerKind, _ b: ListMarkerKind) -> Bool {
            switch (a, b) {
            case (.unordered, .unordered): return true
            case (.ordered, .ordered): return true
            default: return false
            }
        }

        // Two items are part of the same visual list only if nothing (a blank line, a
        // paragraph, a different list) separates them in the source.
        func isImmediatelyFollowing(_ next: ListItemSpan, after previous: ListItemSpan) -> Bool {
            guard previous.lineRange.upperBound < text.endIndex else { return false }
            return text.index(after: previous.lineRange.upperBound) == next.lineRange.lowerBound
        }

        var listItemGroups: [[ListItemSpan]] = []
        for item in listItems {
            if let last = listItemGroups.last?.last, sameListKind(last.kind, item.kind), isImmediatelyFollowing(item, after: last) {
                listItemGroups[listItemGroups.count - 1].append(item)
            } else {
                listItemGroups.append([item])
            }
        }

        for group in listItemGroups {
            guard let first = group.first else { continue }

            // Ordered items auto-renumber sequentially from the first item's own stated number,
            // regardless of what digits the rest of the group's source lines say -- matching the
            // common "1./1./1." authoring convention CommonMark (and other renderers) support.
            // Unordered items have no such display-vs-source distinction; use the literal marker.
            let displayTexts: [String]
            if case let .ordered(startNumber) = first.kind {
                displayTexts = group.indices.map { "\(startNumber + $0). " }
            } else {
                displayTexts = group.map { String(text[$0.markerRange]) }
            }

            // All items in one list share a single hanging-indent tab stop -- computed from the
            // group's widest display marker -- so e.g. "1." and "10." in the same list don't
            // misalign their content start, and a renumbered display value that's wider than its
            // literal source (e.g. three source lines all reading "1." rendering as "1./2./3.")
            // still has enough reserved room to be drawn.
            let indentWidth = displayTexts.map { ($0 as NSString).size(withAttributes: [.font: baseFont]).width }.max() ?? 0

            for (index, item) in group.enumerated() {
                let markerRange = NSRange(item.markerRange, in: text)

                switch item.kind {
                case .unordered:
                    result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markerRange)
                    if markerRange.length > 0 {
                        // NSGlyphInfo glyph substitution (an earlier attempt at this) does not
                        // preserve the substituted "bullet" glyph's own vertical metrics -- it
                        // reuses whatever position the base character ("-") would have drawn at,
                        // which reads as a tiny dot sitting almost on the baseline, not vertically
                        // centered on the line. Instead: keep the marker character at normal size
                        // (so it still occupies real, correctly-laid-out space and stays
                        // selectable/copyable as the literal "-"/"*"/"+"), make it fully
                        // transparent, and let MarkdownLayoutManager draw an actual filled circle
                        // sized from the font's real xHeight and centered within that character's
                        // own real, already-correctly-laid-out bounding rect -- the same technique
                        // already used for the blockquote bar and horizontal rule line.
                        let markerCharacterRange = NSRange(location: markerRange.location, length: 1)
                        result.addAttribute(.foregroundColor, value: NSColor.clear, range: markerCharacterRange)
                        result.addAttribute(.marginalListBulletMarker, value: true, range: markerCharacterRange)
                    }
                case .ordered:
                    // The literal source digits may not match the auto-renumbered display value
                    // (or may simply be a narrower/wider width than the group's shared indent), so
                    // the whole literal marker is hidden and MarkdownLayoutManager draws the
                    // correct display text into the reserved indent zone instead.
                    if markerRange.length > 0 {
                        result.addAttribute(.foregroundColor, value: NSColor.clear, range: markerRange)
                        result.addAttribute(
                            .marginalOrderedListMarkerText,
                            value: displayTexts[index],
                            range: NSRange(location: markerRange.location, length: 1)
                        )
                    }
                }

                // item.lineRange may span multiple source lines when a lazily-continued paragraph
                // line follows with no blank line between them. TextKit treats each "\n"-delimited
                // line as its own paragraph regardless of shared attributes, so the marker's own
                // line and any lazy-continuation lines need separate paragraph styles: the marker
                // line stays flush on its first visual line (headIndent handles its wrapped
                // lines), while a lazy-continuation line must be fully indented from its own first
                // character to read as belonging to the same item, not a new flush-left paragraph.
                let markerLineEnd = text[item.lineRange].firstIndex(of: "\n") ?? item.lineRange.upperBound
                let markerLineStyle = NSMutableParagraphStyle()
                markerLineStyle.firstLineHeadIndent = 0
                markerLineStyle.headIndent = indentWidth
                result.addAttribute(.paragraphStyle, value: markerLineStyle, range: NSRange(item.lineRange.lowerBound..<markerLineEnd, in: text))

                if markerLineEnd < item.lineRange.upperBound {
                    let continuationStyle = NSMutableParagraphStyle()
                    continuationStyle.firstLineHeadIndent = indentWidth
                    continuationStyle.headIndent = indentWidth
                    let continuationStart = text.index(after: markerLineEnd)
                    result.addAttribute(.paragraphStyle, value: continuationStyle, range: NSRange(continuationStart..<item.lineRange.upperBound, in: text))
                }
            }
        }

        return result
    }

    static func plainSourceAttributedString(for text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private static func headerPointSize(for level: Int, baseSize: CGFloat) -> CGFloat {
        let scale: [Int: CGFloat] = [1: 2.0, 2: 1.6, 3: 1.35, 4: 1.15, 5: 1.0, 6: 0.9]
        return baseSize * (scale[level] ?? 1.0)
    }
}
