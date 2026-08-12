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
        let emojiShortcodes = model.emojiShortcodes.filter { !overlapsAnyCodeBlock($0.fullRange) }

        // The literal ":shortcode:" text is fully hidden (tiny font, not just cleared color) --
        // reserving its own (often much longer) text width read as a big dead gap around a much
        // narrower emoji glyph. Instead a kern on the run's last character reserves exactly the
        // emoji's own rendered width, so surrounding text flows tightly around it, matching
        // normal inline emoji spacing.
        for shortcode in emojiShortcodes {
            let fullNSRange = NSRange(shortcode.fullRange, in: text)
            result.addAttribute(.font, value: hiddenFont, range: fullNSRange)
            result.addAttribute(.foregroundColor, value: NSColor.clear, range: fullNSRange)

            let emojiFontSize = baseFont.pointSize * 1.15
            let emojiWidth = (shortcode.emoji as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: emojiFontSize)]).width
            let lastCharRange = NSRange(location: fullNSRange.location + fullNSRange.length - 1, length: 1)
            result.addAttribute(.kern, value: emojiWidth, range: lastCharRange)

            let firstCharRange = NSRange(location: fullNSRange.location, length: 1)
            result.addAttribute(.marginalEmojiShortcode, value: EmojiGlyphInfo(emoji: shortcode.emoji, fontSize: emojiFontSize), range: firstCharRange)
        }

        for header in headers {
            // Semibold, not full bold -- Notion's heading weight (600).
            let headerFont = NSFont.systemFont(
                ofSize: headerPointSize(for: header.level, baseSize: baseFont.pointSize),
                weight: .semibold
            )
            result.addAttribute(.font, value: headerFont, range: NSRange(header.contentRange, in: text))

            let markerRange = NSRange(header.markerRange, in: text)
            result.addAttribute(.font, value: revealedHeaders.contains(header) ? headerFont : hiddenFont, range: markerRange)

            // Notion's block rhythm: a heading carries much more air above it than below, so it
            // reads as introducing the text that follows instead of floating between two equal
            // gaps. Notion's own figures are 30/26/22px above at a 16px body -- but those assume
            // blocks sit flush, whereas here a blank source line is itself a rendered spacer line
            // (roughly one line height) that already supplies most of that gap. So this adds only
            // the *difference*, scaled by heading level; applying the full padding on top of the
            // blank line would nearly double it. See "Block rhythm" in
            // specs/notion-design-tokens.md.
            let headingStyle = NSMutableParagraphStyle()
            headingStyle.paragraphSpacingBefore = baseFont.pointSize * headerExtraSpaceAbove(for: header.level)
            headingStyle.paragraphSpacing = baseFont.pointSize * 0.125
            result.addAttribute(.paragraphStyle,
                                value: headingStyle,
                                range: (text as NSString).paragraphRange(for: markerRange))
        }

        let revealedBlockquotes = cursorLocation.map {
            CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: $0)
        } ?? []

        // Gap between the drawn left bar and the quoted text -- Notion's quote padding-left is
        // 14px at its 16px body size. Notion quotes keep the regular weight and the normal text
        // color (they are NOT italic or gray -- an earlier version did both).
        let blockquoteContentIndent = baseFont.pointSize * 0.875

        for blockquote in blockquotes {
            let markerRange = NSRange(blockquote.markerRange, in: text)
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
        // This early pass applies only the table's fonts and row chrome. The kern/grid geometry
        // is deferred to a second pass at the end of this function (see pendingTables below):
        // cell widths must be measured from the finished attributed runs -- a bold/code span or
        // emoji inside a cell renders wider/narrower than the same characters at plain baseFont,
        // and the hidden pipes/padding still advance the line by their own (tiny) widths -- so
        // measuring before inlineStyles/links/emoji have layered their fonts produced columns
        // that drifted right of their own grid lines by one pipe-width per column.
        struct PendingTableLayout {
            let allRows: [TableRowSpan]
            let columnCount: Int
            let alignments: [TableAlignment]
            let rowCellRanges: [[Range<String.Index>]]
        }
        var pendingTables: [PendingTableLayout] = []

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

            var rowCellRanges: [[Range<String.Index>]] = []
            for (rowIndex, row) in allRows.enumerated() {
                let isHeader = rowIndex == 0
                let cols = min(columnCount, row.pipeRanges.count - 1)
                var ranges: [Range<String.Index>] = []
                for c in 0..<cols {
                    let cellRange = trimmedCellRange(row.pipeRanges[c], row.pipeRanges[c + 1])
                    ranges.append(cellRange)

                    // Pipes are shrunk to the hidden font, not just cleared: at full size their
                    // advance width pushed every column right of its own grid line, one more
                    // pipe-width per column.
                    let pipeNSRange = NSRange(row.pipeRanges[c], in: text)
                    result.addAttribute(.font, value: hiddenFont, range: pipeNSRange)
                    result.addAttribute(.foregroundColor, value: NSColor.clear, range: pipeNSRange)

                    if row.pipeRanges[c].upperBound < cellRange.lowerBound {
                        result.addAttribute(.font, value: hiddenFont, range: NSRange(row.pipeRanges[c].upperBound..<cellRange.lowerBound, in: text))
                    }
                    if cellRange.upperBound < row.pipeRanges[c + 1].lowerBound {
                        result.addAttribute(.font, value: hiddenFont, range: NSRange(cellRange.upperBound..<row.pipeRanges[c + 1].lowerBound, in: text))
                    }
                    if isHeader {
                        // Medium (500), not bold -- Notion's measured header row weight. A
                        // **bold** span nested in a header cell still layers real bold on top
                        // (inlineStyles runs after this).
                        result.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium), range: NSRange(cellRange, in: text))
                    }
                }
                if let lastPipe = row.pipeRanges.last {
                    let lastPipeNSRange = NSRange(lastPipe, in: text)
                    result.addAttribute(.font, value: hiddenFont, range: lastPipeNSRange)
                    result.addAttribute(.foregroundColor, value: NSColor.clear, range: lastPipeNSRange)
                }
                rowCellRanges.append(ranges)

                // Vertical breathing room within each row -- without this, a row's height is
                // exactly the text's own line height, so content butts directly against the grid
                // lines above and below it. The grid drawing (which reads this same laid-out
                // line's bounding rect) automatically follows the increased height. TextKit
                // anchors a fixed-height line's baseline low (all the extra height lands above
                // the glyphs), which read as text glued to the bottom grid line -- the baseline
                // offset re-centers it vertically, matching Notion.
                let rowHeight = baseFont.pointSize * 2.2
                let rowParagraphStyle = NSMutableParagraphStyle()
                rowParagraphStyle.minimumLineHeight = rowHeight
                rowParagraphStyle.maximumLineHeight = rowHeight
                let rowNSRange = NSRange(row.lineRange, in: text)
                result.addAttribute(.paragraphStyle, value: rowParagraphStyle, range: rowNSRange)
                let naturalLineHeight = baseFont.ascender - baseFont.descender + baseFont.leading
                result.addAttribute(.baselineOffset, value: (rowHeight - naturalLineHeight) / 2, range: rowNSRange)
            }

            result.addAttribute(.font, value: hiddenFont, range: NSRange(table.separatorRowRange, in: text))
            pendingTables.append(PendingTableLayout(
                allRows: allRows,
                columnCount: columnCount,
                alignments: alignments,
                rowCellRanges: rowCellRanges
            ))
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
                // Semibold (600), not full bold -- 600 is the heaviest weight in the product
                // (same rule as headings; the design system never uses 700).
                result.addAttribute(.font, value: NSFont.systemFont(ofSize: spanBaseFont.pointSize, weight: .semibold), range: contentRange)
            case .italic:
                result.addAttribute(.font, value: NSFontManager.shared.convert(spanBaseFont, toHaveTrait: .italicFontMask), range: contentRange)
            case .boldItalic:
                let semibold = NSFont.systemFont(ofSize: spanBaseFont.pointSize, weight: .semibold)
                result.addAttribute(.font, value: NSFontManager.shared.convert(semibold, toHaveTrait: .italicFontMask), range: contentRange)
            case .strikethrough:
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            case .underline:
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            case .code:
                // ~85% mono on a warm panel chip, in the brand's single accent (violet) --
                // consistent with fenced blocks' 85% sizing.
                result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: spanBaseFont.pointSize * 0.85, weight: .regular), range: contentRange)
                result.addAttribute(.backgroundColor, value: DesignPalette.surfaceCode, range: contentRange)
                result.addAttribute(.foregroundColor, value: DesignPalette.accent, range: contentRange)
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
            result.addAttribute(.foregroundColor, value: DesignPalette.accent, range: textRange)
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
            // The hidden 0.1pt font would make this line fragment a fraction of a point
            // tall -- unclickable, so the cursor could never reach the line to reveal the
            // literal "---". A fixed line height keeps the rule's line a normal, clickable
            // target (and the drawn rule centers within it).
            let ruleStyle = NSMutableParagraphStyle()
            ruleStyle.minimumLineHeight = baseFont.pointSize * 1.5
            result.addAttribute(.paragraphStyle, value: ruleStyle, range: lineNSRange)
        }

        let revealedCodeBlocks = cursorLocation.map {
            CursorRevealController.revealedCodeBlockSpans(in: model, cursorLocation: $0)
        } ?? []

        for codeBlock in model.codeBlocks {
            let contentNSRange = NSRange(codeBlock.contentRange, in: text)
            // ~85% of body size, matching Notion -- an earlier version bumped code UP by 1pt,
            // which read as code shouting over the surrounding prose.
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.85, weight: .regular)
            result.addAttribute(.font, value: codeFont, range: contentNSRange)

            // The background is not a per-glyph .backgroundColor (a ragged slab hugging each
            // line's own text) -- the layout manager draws one rounded card behind the whole
            // block, Notion-style. The marker spans the fences too: the hidden fence lines are
            // given a fixed line height below, so they render as the card's top/bottom padding
            // bands, and the content is inset from the card's left edge via paragraph indent.
            let blockNSRange = NSRange(codeBlock.openingFenceRange.lowerBound..<codeBlock.closingFenceRange.upperBound, in: text)
            result.addAttribute(.marginalCodeBlockMarker, value: true, range: blockNSRange)

            let contentInset = codeBlockContentInset(for: baseFont)
            let contentStyle = NSMutableParagraphStyle()
            contentStyle.firstLineHeadIndent = contentInset
            contentStyle.headIndent = contentInset
            // Notion code lines run at 1.5 line height (20.4px for 13.6px code), airier than
            // the mono font's own default.
            contentStyle.minimumLineHeight = codeFont.pointSize * 1.5
            result.addAttribute(.paragraphStyle, value: contentStyle, range: contentNSRange)

            let fenceStyle = NSMutableParagraphStyle()
            fenceStyle.minimumLineHeight = baseFont.pointSize * 1.5
            fenceStyle.firstLineHeadIndent = contentInset
            fenceStyle.headIndent = contentInset
            result.addAttribute(.paragraphStyle, value: fenceStyle, range: NSRange(codeBlock.openingFenceRange, in: text))
            result.addAttribute(.paragraphStyle, value: fenceStyle, range: NSRange(codeBlock.closingFenceRange, in: text))

            let codeText = String(text[codeBlock.contentRange])
            for token in MarkdownParser.parseCodeHighlightTokens(in: codeText) {
                let startOffset = codeText.distance(from: codeText.startIndex, to: token.range.lowerBound)
                let endOffset = codeText.distance(from: codeText.startIndex, to: token.range.upperBound)
                guard let tokenStart = text.index(codeBlock.contentRange.lowerBound, offsetBy: startOffset, limitedBy: text.endIndex),
                      let tokenEnd = text.index(codeBlock.contentRange.lowerBound, offsetBy: endOffset, limitedBy: text.endIndex) else { continue }
                let tokenColor: NSColor
                switch token.kind {
                case .string: tokenColor = DesignPalette.synString
                case .comment: tokenColor = DesignPalette.synComment
                case .number: tokenColor = DesignPalette.synNumber
                }
                result.addAttribute(.foregroundColor, value: tokenColor, range: NSRange(tokenStart..<tokenEnd, in: text))
            }

            let fenceFont = revealedCodeBlocks.contains(codeBlock) ? baseFont : hiddenFont
            result.addAttribute(.font, value: fenceFont, range: NSRange(codeBlock.openingFenceRange, in: text))
            result.addAttribute(.font, value: fenceFont, range: NSRange(codeBlock.closingFenceRange, in: text))
        }

        // Table geometry (deferred from the early table pass above): every font that can affect
        // a cell's rendered width has been applied by now, so widths are measured from the real
        // attributed runs. Column alignment is achieved without restructuring the text into real
        // per-cell paragraphs (which NSTextTable would require -- a real mutation of the
        // underlying markdown): a precisely computed .kern on each hidden pipe pushes the
        // FOLLOWING cell's visible content to land exactly at that column's shared target
        // x-position, the same position on every row, so columns line up into a real grid.
        for pending in pendingTables {
            let cellPadding = tableCellPadding(for: baseFont)

            func measuredWidth(_ range: Range<String.Index>) -> CGFloat {
                guard !range.isEmpty else { return 0 }
                return result.attributedSubstring(from: NSRange(range, in: text)).size().width
            }

            let rowCellWidths = pending.rowCellRanges.map { $0.map(measuredWidth) }
            var columnWidths = [CGFloat](repeating: 0, count: pending.columnCount)
            for widths in rowCellWidths {
                for (c, w) in widths.enumerated() { columnWidths[c] = max(columnWidths[c], w) }
            }
            var slotStarts: [CGFloat] = [0]
            for c in 0..<pending.columnCount { slotStarts.append(slotStarts[c] + columnWidths[c] + cellPadding * 2) }

            for (rowIndex, row) in pending.allRows.enumerated() {
                let cols = min(pending.columnCount, row.pipeRanges.count - 1)
                var flowPosition: CGFloat = 0
                for c in 0..<cols {
                    let cellRange = pending.rowCellRanges[rowIndex][c]
                    let rawWidth = rowCellWidths[rowIndex][c]
                    let slotStart = slotStarts[c]
                    let slotWidth = columnWidths[c] + cellPadding * 2
                    let desiredContentStart: CGFloat
                    switch pending.alignments[c] {
                    case .left: desiredContentStart = slotStart + cellPadding
                    case .right: desiredContentStart = slotStart + slotWidth - cellPadding - rawWidth
                    case .center: desiredContentStart = slotStart + (slotWidth - rawWidth) / 2
                    }

                    // The hidden pipe and padding glyphs still advance the line by their own
                    // (tiny) measured widths -- folded into the kern so the content position
                    // is exact, not just close.
                    let pipeWidth = measuredWidth(row.pipeRanges[c])
                    let leadingPadWidth = measuredWidth(row.pipeRanges[c].upperBound..<cellRange.lowerBound)
                    let trailingPadWidth = measuredWidth(cellRange.upperBound..<row.pipeRanges[c + 1].lowerBound)
                    result.addAttribute(
                        .kern,
                        value: desiredContentStart - flowPosition - pipeWidth - leadingPadWidth,
                        range: NSRange(row.pipeRanges[c], in: text)
                    )
                    flowPosition = desiredContentStart + rawWidth + trailingPadWidth
                }

                result.addAttribute(
                    .marginalTableGridMarker,
                    value: TableGridInfo(columnBoundaries: slotStarts, isHeaderRow: rowIndex == 0),
                    range: NSRange(row.lineRange, in: text)
                )
            }
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

        let revealedTasks = cursorLocation.map {
            CursorRevealController.revealedTaskListSpans(in: model, cursorLocation: $0)
        } ?? []

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
                    // A task item shows only its checkbox, not the usual bullet shape --
                    // unless the cursor is on its line, which reveals the literal "- [ ]"
                    // source, matching every other marker's reveal-at-cursor behavior.
                    if !revealedTasks.contains(item) {
                        result.addAttribute(.foregroundColor, value: NSColor.clear, range: markerRange)
                    }
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
                        // The transparent literal marker still advances the line by its own
                        // natural width, which differs per item ("2. " vs "10. ") -- without
                        // correction each item's content starts at a different x while the drawn
                        // digits right-align against the group's shared headIndent, overlapping
                        // the content. A kern on the marker's last character stretches (or
                        // tightens) its advance to exactly the shared indentWidth, so every
                        // item's content lands on the same tab stop the digits align against.
                        let naturalMarkerWidth = (String(text[item.markerRange]) as NSString).size(withAttributes: [.font: baseFont]).width
                        result.addAttribute(
                            .kern,
                            value: indentWidth - naturalMarkerWidth,
                            range: NSRange(location: markerRange.location + markerRange.length - 1, length: 1)
                        )
                    }
                }

                if let taskState = item.taskState, let taskMarkerRange = item.taskMarkerRange {
                    // Hide the literal "[ ]"/"[x] " text -- it's still laid out at normal size (so
                    // it reserves the correct space and stays selectable/copyable), and
                    // MarkdownLayoutManager draws an actual checkbox square (+ checkmark when
                    // complete) into that same reserved space, the same technique as the bullet.
                    // When the cursor is on this line the literal source stays visible instead.
                    let taskMarkerNSRange = NSRange(taskMarkerRange, in: text)
                    if !revealedTasks.contains(item) {
                        result.addAttribute(.foregroundColor, value: NSColor.clear, range: taskMarkerNSRange)
                        result.addAttribute(.marginalTaskCheckboxMarker, value: taskState == .complete, range: taskMarkerNSRange)
                    }

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
                // Breathing room between consecutive items (Notion: ~7px at 16px body).
                // Applied to the paragraph that ENDS the item, so an item's own lazy
                // continuation lines are never pushed away from their marker line.
                let itemSpacing = baseFont.pointSize * 0.4375
                let hasContinuation = markerLineEnd < item.lineRange.upperBound

                let markerLineStyle = NSMutableParagraphStyle()
                markerLineStyle.firstLineHeadIndent = levelOffset
                markerLineStyle.headIndent = levelOffset + indentWidth
                if !hasContinuation { markerLineStyle.paragraphSpacing = itemSpacing }
                result.addAttribute(.paragraphStyle, value: markerLineStyle, range: NSRange(item.lineRange.lowerBound..<markerLineEnd, in: text))

                if hasContinuation {
                    let continuationStyle = NSMutableParagraphStyle()
                    continuationStyle.firstLineHeadIndent = levelOffset + indentWidth
                    continuationStyle.headIndent = levelOffset + indentWidth
                    continuationStyle.paragraphSpacing = itemSpacing
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

    /// Extra space above a heading, as a multiple of the body font size, on top of the blank
    /// source line that already separates it from the previous block. Bigger headings get more
    /// air, which is what makes the document's hierarchy readable at a glance; h4-h6 sit at body
    /// scale already and need none.
    private static func headerExtraSpaceAbove(for level: Int) -> CGFloat {
        let extra: [Int: CGFloat] = [1: 0.75, 2: 0.5, 3: 0.25]
        return extra[level] ?? 0
    }

    private static func headerPointSize(for level: Int, baseSize: CGFloat) -> CGFloat {
        // Notion's heading scale: 30/24/20/18px at 16px body (h5/h6 have no Notion equivalent
        // and extrapolate the same curve downward).
        let scale: [Int: CGFloat] = [1: 1.875, 2: 1.5, 3: 1.25, 4: 1.125, 5: 1.0, 6: 0.875]
        return baseSize * (scale[level] ?? 1.0)
    }

    /// Gap between an ordered list marker's period and where the content starts. Shared with
    /// MarkdownLayoutManager (which draws the marker text right-aligned against
    /// headIndent minus this same gap) so the reserved indent width and the actual draw position
    /// always agree.
    static func orderedMarkerContentGap(for font: NSFont) -> CGFloat {
        font.pointSize * 0.35
    }

    /// Horizontal padding between a column's grid line and the cell content inside it. Scales
    /// with type size; the ratio matches Notion's table cell padding (~10px at Notion's 16px
    /// body size). Shared with tests so the reserved slot math and assertions always agree.
    static func tableCellPadding(for font: NSFont) -> CGFloat {
        font.pointSize * 0.5625
    }

    /// Horizontal inset between a fenced code block's rounded card edge and the code inside it.
    /// Scales with type size; the ratio matches Notion's code block padding (~22px at Notion's
    /// 16px body size). Shared with MarkdownLayoutManager/tests so the paragraph indent and the
    /// drawn card always agree.
    static func codeBlockContentInset(for font: NSFont) -> CGFloat {
        font.pointSize * 1.375
    }
}
