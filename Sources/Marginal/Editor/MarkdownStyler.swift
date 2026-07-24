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
        let tables = model.tables.filter { table in
            let fullRange = table.headerRow.lineRange.lowerBound..<(table.bodyRows.last?.lineRange.upperBound ?? table.separatorRowRange.upperBound)
            return !overlapsAnyCodeBlock(fullRange)
        }

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

        // Tables run before inlineStyles (like blockquotes) so nested bold/italic/code/links
        // within a cell layer their own font on top afterward, instead of the header row's
        // blanket bold being applied last and clobbering them.
        //
        // Column alignment is achieved without ever restructuring the text into real per-cell
        // paragraphs (which NSTextTable would require, and which would mean inserting paragraph
        // breaks that aren't in the source -- a real mutation of the underlying markdown). Instead:
        // every "|" and the whitespace padding around each cell's trimmed content is hidden (same
        // technique as every other custom marker in this file), and a precisely computed .kern
        // value on each hidden pipe pushes the FOLLOWING cell's visible content to land exactly at
        // that column's shared target x-position -- the same shared position on every row, so the
        // columns line up into a real grid despite each row's content having a different natural
        // width. The separator ("|---|") row is pure syntax and stays fully hidden.
        for table in tables {
            let columnCount = table.headerRow.pipeRanges.count - 1
            guard columnCount > 0 else { continue }
            let alignments: [TableAlignment] = (0..<columnCount).map {
                table.columnAlignments.indices.contains($0) ? table.columnAlignments[$0] : .left
            }
            let allRows = [table.headerRow] + table.bodyRows

            func trimmedCellRange(_ pipeStart: Range<String.Index>, _ pipeEnd: Range<String.Index>) -> Range<String.Index> {
                var start = pipeStart.upperBound
                var end = pipeEnd.lowerBound
                while start < end, text[start] == " " { start = text.index(after: start) }
                while end > start, text[text.index(before: end)] == " " { end = text.index(before: end) }
                return start..<end
            }

            // Pass 1: gather each row's trimmed cell ranges/widths so column widths (the max
            // across every row) can be computed before any row is actually styled.
            var rowCellRanges: [[Range<String.Index>]] = []
            var rowCellWidths: [[CGFloat]] = []
            for row in allRows {
                let cols = min(columnCount, row.pipeRanges.count - 1)
                var ranges: [Range<String.Index>] = []
                var widths: [CGFloat] = []
                for c in 0..<cols {
                    let range = trimmedCellRange(row.pipeRanges[c], row.pipeRanges[c + 1])
                    ranges.append(range)
                    widths.append((String(text[range]) as NSString).size(withAttributes: [.font: baseFont]).width)
                }
                rowCellRanges.append(ranges)
                rowCellWidths.append(widths)
            }

            let cellPadding: CGFloat = 10
            var columnWidths = [CGFloat](repeating: 0, count: columnCount)
            for widths in rowCellWidths {
                for (c, w) in widths.enumerated() { columnWidths[c] = max(columnWidths[c], w) }
            }
            var slotStarts: [CGFloat] = [0]
            for c in 0..<columnCount { slotStarts.append(slotStarts[c] + columnWidths[c] + cellPadding * 2) }
            let gridColumnBoundaries = slotStarts

            for (rowIndex, row) in allRows.enumerated() {
                let isHeader = rowIndex == 0
                let cols = min(columnCount, row.pipeRanges.count - 1)
                var flowPosition: CGFloat = 0
                for c in 0..<cols {
                    let cellRange = rowCellRanges[rowIndex][c]
                    let rawWidth = rowCellWidths[rowIndex][c]
                    let slotStart = slotStarts[c]
                    let slotWidth = columnWidths[c] + cellPadding * 2
                    let desiredContentStart: CGFloat
                    switch alignments[c] {
                    case .left: desiredContentStart = slotStart + cellPadding
                    case .right: desiredContentStart = slotStart + slotWidth - cellPadding - rawWidth
                    case .center: desiredContentStart = slotStart + (slotWidth - rawWidth) / 2
                    }

                    let pipeNSRange = NSRange(row.pipeRanges[c], in: text)
                    result.addAttribute(.foregroundColor, value: NSColor.clear, range: pipeNSRange)
                    result.addAttribute(.kern, value: desiredContentStart - flowPosition, range: pipeNSRange)

                    if row.pipeRanges[c].upperBound < cellRange.lowerBound {
                        result.addAttribute(.font, value: hiddenFont, range: NSRange(row.pipeRanges[c].upperBound..<cellRange.lowerBound, in: text))
                    }
                    if cellRange.upperBound < row.pipeRanges[c + 1].lowerBound {
                        result.addAttribute(.font, value: hiddenFont, range: NSRange(cellRange.upperBound..<row.pipeRanges[c + 1].lowerBound, in: text))
                    }
                    if isHeader {
                        result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask), range: NSRange(cellRange, in: text))
                    }

                    flowPosition = desiredContentStart + rawWidth
                }
                if let lastPipe = row.pipeRanges.last {
                    result.addAttribute(.foregroundColor, value: NSColor.clear, range: NSRange(lastPipe, in: text))
                }

                result.addAttribute(
                    .marginalTableGridMarker,
                    value: TableGridInfo(columnBoundaries: gridColumnBoundaries, isHeaderRow: isHeader),
                    range: NSRange(row.lineRange, in: text)
                )
            }

            result.addAttribute(.font, value: hiddenFont, range: NSRange(table.separatorRowRange, in: text))
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

        // Grouping also requires matching nesting level: a run like "1. / 1. nested / 2. nested /
        // 2." must not treat the nested pair as continuing the outer list's own numbering. This
        // naturally splits an outer item on either side of a nested run into their own
        // (single-item) groups, which still renumbers them correctly since each starts fresh from
        // its own literal number.
        var listItemGroups: [[ListItemSpan]] = []
        for item in listItems {
            if let last = listItemGroups.last?.last, sameListKind(last.kind, item.kind), last.level == item.level, isImmediatelyFollowing(item, after: last) {
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
            // The ordered display text deliberately excludes a trailing space -- an earlier
            // version relied on NSString.size(withAttributes:) including a trailing space's
            // advance width to create the gap before content, which is not guaranteed and read
            // as the number nearly colliding with the following text. The gap is now an explicit,
            // guaranteed value (below) instead of an implicit byproduct of string measurement.
            let displayTexts: [String]
            if case let .ordered(startNumber) = first.kind {
                displayTexts = group.indices.map { "\(startNumber + $0)." }
            } else {
                displayTexts = group.map { String(text[$0.markerRange]) }
            }

            // All items in one list share a single hanging-indent tab stop -- computed from the
            // group's widest display marker -- so e.g. "1." and "10." in the same list don't
            // misalign their content start, and a renumbered display value that's wider than its
            // literal source (e.g. three source lines all reading "1." rendering as "1./2./3.")
            // still has enough reserved room to be drawn. Ordered markers reserve extra room for
            // an explicit gap before the content starts (MarkdownLayoutManager draws the digits
            // right-aligned against headIndent minus this same gap).
            let isOrderedGroup = { if case .ordered = first.kind { return true } else { return false } }()
            let indentWidth = displayTexts.map { text -> CGFloat in
                let width = (text as NSString).size(withAttributes: [.font: baseFont]).width
                return isOrderedGroup ? width + orderedMarkerContentGap(for: baseFont) : width
            }.max() ?? 0

            for (index, item) in group.enumerated() {
                let markerRange = NSRange(item.markerRange, in: text)

                // Leading indentation (2 spaces per nesting level) is hidden -- the actual visual
                // indent comes entirely from the paragraph style below, computed per level, so it
                // stays consistent regardless of exactly how much whitespace was typed.
                if item.markerRange.lowerBound > item.lineRange.lowerBound {
                    let leadingWhitespaceRange = NSRange(item.lineRange.lowerBound..<item.markerRange.lowerBound, in: text)
                    result.addAttribute(.font, value: hiddenFont, range: leadingWhitespaceRange)
                }

                switch item.kind {
                case .unordered where item.taskState != nil:
                    // A task item shows only its checkbox, not the usual bullet shape.
                    result.addAttribute(.foregroundColor, value: NSColor.clear, range: markerRange)
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
                        // transparent, and let MarkdownLayoutManager draw an actual filled shape
                        // sized from the font's real xHeight and centered within that character's
                        // own real, already-correctly-laid-out bounding rect -- the same technique
                        // already used for the blockquote bar and horizontal rule line. The shape
                        // cycles filled circle / hollow circle / filled square per nesting level,
                        // matching common editors' nested-list conventions.
                        let markerCharacterRange = NSRange(location: markerRange.location, length: 1)
                        result.addAttribute(.foregroundColor, value: NSColor.clear, range: markerCharacterRange)
                        result.addAttribute(.marginalListBulletMarker, value: item.level % 3, range: markerCharacterRange)
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

                if let taskState = item.taskState, let taskMarkerRange = item.taskMarkerRange {
                    // Hide the literal "[ ]"/"[x] " text -- it's still laid out at normal size (so
                    // it reserves the correct space and stays selectable/copyable), and
                    // MarkdownLayoutManager draws an actual checkbox square (+ checkmark when
                    // complete) into that same reserved space, the same technique as the bullet.
                    let taskMarkerNSRange = NSRange(taskMarkerRange, in: text)
                    result.addAttribute(.foregroundColor, value: NSColor.clear, range: taskMarkerNSRange)
                    result.addAttribute(.marginalTaskCheckboxMarker, value: taskState == .complete, range: taskMarkerNSRange)

                    if taskState == .complete {
                        // Completed tasks read as done: struck through and de-emphasized, matching
                        // common editors' (e.g. Notion's) convention. This runs after inlineStyles
                        // and only touches color/strikethrough, not .font, so nested bold/italic
                        // within the task text keeps its own font trait.
                        let taskTextRange = NSRange(taskMarkerRange.upperBound..<item.lineRange.upperBound, in: text)
                        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: taskTextRange)
                        result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: taskTextRange)
                    }
                }

                // Each nesting level reserves one more indentWidth-sized slot: the marker itself
                // shifts right by level * indentWidth, and content starts one slot further in.
                let levelOffset = CGFloat(item.level) * indentWidth

                // item.lineRange may span multiple source lines when a lazily-continued paragraph
                // line follows with no blank line between them. TextKit treats each "\n"-delimited
                // line as its own paragraph regardless of shared attributes, so the marker's own
                // line and any lazy-continuation lines need separate paragraph styles: the marker
                // line stays flush (at this level's own offset) on its first visual line
                // (headIndent handles its wrapped lines), while a lazy-continuation line must be
                // fully indented from its own first character to read as belonging to the same
                // item, not a new flush-left paragraph.
                let markerLineEnd = text[item.lineRange].firstIndex(of: "\n") ?? item.lineRange.upperBound
                let markerLineStyle = NSMutableParagraphStyle()
                markerLineStyle.firstLineHeadIndent = levelOffset
                markerLineStyle.headIndent = levelOffset + indentWidth
                result.addAttribute(.paragraphStyle, value: markerLineStyle, range: NSRange(item.lineRange.lowerBound..<markerLineEnd, in: text))

                if markerLineEnd < item.lineRange.upperBound {
                    let continuationStyle = NSMutableParagraphStyle()
                    continuationStyle.firstLineHeadIndent = levelOffset + indentWidth
                    continuationStyle.headIndent = levelOffset + indentWidth
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

    /// Gap between an ordered list marker's period and where the content starts. Shared with
    /// MarkdownLayoutManager (which draws the marker text right-aligned against
    /// headIndent minus this same gap) so the reserved indent width and the actual draw position
    /// always agree.
    static func orderedMarkerContentGap(for font: NSFont) -> CGFloat {
        font.pointSize * 0.35
    }
}
