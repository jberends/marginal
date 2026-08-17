import AppKit

extension NSAttributedString.Key {
    static let marginalBlockquoteMarker = NSAttributedString.Key("marginalBlockquoteMarker")
    static let marginalHorizontalRuleMarker = NSAttributedString.Key("marginalHorizontalRuleMarker")
    static let marginalListBulletMarker = NSAttributedString.Key("marginalListBulletMarker")
    static let marginalOrderedListMarkerText = NSAttributedString.Key("marginalOrderedListMarkerText")
    static let marginalTaskCheckboxMarker = NSAttributedString.Key("marginalTaskCheckboxMarker")
    static let marginalTableGridMarker = NSAttributedString.Key("marginalTableGridMarker")
    static let marginalCodeBlockMarker = NSAttributedString.Key("marginalCodeBlockMarker")
    static let marginalEmojiShortcode = NSAttributedString.Key("marginalEmojiShortcode")
    static let marginalImage = NSAttributedString.Key("marginalImage")
}

/// Carries the info needed to draw an inline image in place of its hidden "![alt](path)"
/// markup. `displaySize.height` is the total reserved band (the whole figure card: image area +
/// caption row + padding); the styler computes it from `ImageCardMetrics`. `caption` is the text
/// shown beneath the image (the alt text, or the filename stem when alt is empty).
struct ImageDisplayInfo: Equatable {
    let resolvedURL: URL
    let displaySize: NSSize
    let caption: String
}

/// Metrics for the inline-image "figure card" -- shared by the styler (which reserves the band)
/// and the layout manager (which draws it) so the reserved space and the drawn card always agree.
enum ImageCardMetrics {
    static let cornerRadius: CGFloat = 8
    static let outerInset: CGFloat = 4      // gap between the card and the text column edges
    static let padding: CGFloat = 14        // inner padding inside the card
    static let captionGap: CGFloat = 8      // between the image and its caption
    static let imageAreaHeight: CGFloat = 200

    /// Height of the caption text line at the given font size.
    static func captionHeight(fontSize: CGFloat) -> CGFloat { (fontSize * 1.3).rounded(.up) }

    /// Total reserved band height: padding + image + gap + caption + padding.
    static func bandHeight(captionFontSize: CGFloat) -> CGFloat {
        padding + imageAreaHeight + captionGap + captionHeight(fontSize: captionFontSize) + padding
    }
}

/// One table row's grid geometry, computed once per table in MarkdownStyler and drawn by
/// MarkdownLayoutManager. Column boundaries are relative x-offsets from the row's own left edge
/// (0, then each column's cumulative slot width), shared by every row in the same table so the
/// grid lines up across rows regardless of each row's own content width.
struct TableGridInfo: Equatable {
    let columnBoundaries: [CGFloat]
    let isHeaderRow: Bool
}

/// An emoji glyph to draw in place of a hidden ":shortcode:" run. Carries its own intended font
/// size (computed in MarkdownStyler from baseFont) since the hidden run's own .font attribute is
/// shrunk to hiddenFont and can't be used to recover the intended drawing size.
struct EmojiGlyphInfo: Equatable {
    let emoji: String
    let fontSize: CGFloat
}

/// Draws paragraph-level decorations that can't be expressed as ordinary run attributes: the
/// blockquote left bar and the horizontal rule line. Keyed off custom attributes MarkdownStyler
/// applies to the relevant ranges.
///
/// De-risked by a compiled standalone spike (see Phase 2 design spec) before this class existed,
/// confirming the general technique -- overriding drawBackground(forGlyphRange:at:) and keying off
/// a custom attribute -- correctly spans multi-line wrapped paragraphs, unlike a single-character
/// attachment would. The exact rect math below differs from that spike, discovered when compiled
/// against this app's real NSTextContainer geometry:
///
/// 1. `boundingRect(forGlyphRange:in:)` does NOT union across multiple line fragments the way its
///    documentation might suggest -- for a glyph range spanning several wrapped visual lines it
///    only returns ONE line fragment's rect (empirically, the first). Spanning a wrapped paragraph
///    requires enumerating each line fragment individually via `enumerateLineFragments` and drawing
///    one bar segment per line; stacked directly atop one another they read as one continuous bar.
/// 2. NSTextView clips the layout manager's background/glyph drawing to the text container's own
///    bounds -- i.e. nothing left of `origin.x + lineFragmentRect.minX` is drawable, so the bar
///    cannot be pushed out into the textContainerInset margin (verified empirically: a bar drawn
///    with a negative x offset into that margin was silently clipped and invisible). The bar is
///    therefore drawn starting exactly at the container's left edge, not to the left of it.
final class MarkdownLayoutManager: NSLayoutManager {

    /// The rect that actually hugs the glyphs on a line, for aligning anything drawn beside text.
    ///
    /// `boundingRect(forGlyphRange:in:)` returns the *line fragment*, and a paragraph style with a
    /// `lineHeightMultiple` inflates that fragment above the glyphs -- so its `midY` sits higher
    /// than the text does, and every marker drawn against it (bullets, list numbers, checkboxes,
    /// emoji) drifted upward off its own line the moment body line height went to 1.55. Deriving
    /// the rect from the glyph baseline and the font's ascender/descender keeps decorations
    /// aligned to the text no matter what the line height is.
    /// The y of the text baseline on the line containing `range`, in container coordinates.
    ///
    /// Anything *textual* drawn beside the text -- a list number, an emoji standing in for a
    /// shortcode, an ellipsis or dash standing in for its source characters -- has to sit on this
    /// baseline. Centring such a string vertically in the line instead leaves it visibly low,
    /// because a string's bounding box is taller than the distance from its baseline to its top.
    func textBaselineY(forGlyphRange range: NSRange) -> CGFloat? {
        guard range.location < numberOfGlyphs else { return nil }
        let fragment = lineFragmentRect(forGlyphAt: range.location, effectiveRange: nil)
        return fragment.minY + location(forGlyphAt: range.location).y
    }

    func textLineRect(forGlyphRange range: NSRange, in container: NSTextContainer) -> NSRect {
        let bounding = boundingRect(forGlyphRange: range, in: container)
        guard range.location < numberOfGlyphs, let storage = textStorage else { return bounding }
        let characterIndex = characterIndexForGlyph(at: range.location)
        guard characterIndex < storage.length else { return bounding }

        let font = (storage.attribute(.font, at: characterIndex, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let fragment = lineFragmentRect(forGlyphAt: range.location, effectiveRange: nil)
        let baseline = fragment.minY + location(forGlyphAt: range.location).y
        return NSRect(x: bounding.minX,
                      y: baseline - font.ascender,
                      width: bounding.width,
                      height: font.ascender - font.descender)
    }

    /// Horizontal distance between the bars of nested blockquotes. Matches the per-level content
    /// indent the styler applies, so each bar lands just left of the text it encloses.
    var blockquoteBarStep: CGFloat = 14

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let textContainer = textContainers.first else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // The code block card is painted BEFORE super, and everything else after it.
        //
        // super.drawBackground is what paints the selection highlight. Filling the card after it
        // covered that highlight completely, so selecting text inside a code block looked like
        // nothing had been selected at all -- the status bar knew, the page didn't show it.
        // Drawing the card first puts the selection on top of it, while the decorations below
        // still layer on top of the card.
        textStorage.enumerateAttribute(.marginalCodeBlockMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            // The value carries how far the card is inset -- non-zero when the fence sits inside a
            // blockquote, so the quote bar has room to its left instead of overlapping the card.
            let quoteInset = (value as? CGFloat) ?? 0
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // boundingRect only returns ONE line fragment's rect (see the type doc comment) --
            // the card's vertical extent must be unioned from every fragment, including the
            // fixed-height hidden fence lines that act as top/bottom padding bands.
            var top = CGFloat.greatestFiniteMagnitude
            var bottom = -CGFloat.greatestFiniteMagnitude
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                top = min(top, lineRect.minY)
                bottom = max(bottom, lineRect.maxY)
            }
            guard top < bottom else { return }
            let cardRect = NSRect(
                x: origin.x + textContainer.lineFragmentPadding + quoteInset,
                y: origin.y + top,
                width: max(0, textContainer.size.width - textContainer.lineFragmentPadding * 2 - quoteInset),
                height: bottom - top
            )
            DesignPalette.surfaceCode.setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 10, yRadius: 10).fill()
        }

        // Selection highlight and any .backgroundColor runs -- now above the card.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        textStorage.enumerateAttribute(.marginalBlockquoteMarker, in: fullRange) { value, range, _ in
            // The value is the nesting depth: ">> quoted" draws two bars, one per level, each a
            // content-indent step further in, so a quoted reply reads as nested.
            let depth = (value as? Int) ?? (value != nil ? 1 : 0)
            guard depth > 0 else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // Solid text color, matching Notion's quote bar (border-left: 3px solid currentColor).
            NSColor.labelColor.setFill()
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                for level in 0..<depth {
                    let x = origin.x + lineRect.minX + CGFloat(level) * self.blockquoteBarStep
                    NSRect(x: x, y: origin.y + lineRect.minY, width: 3, height: lineRect.height).fill()
                }
            }
        }

        textStorage.enumerateAttribute(.marginalHorizontalRuleMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let lineRect = NSRect(
                x: origin.x + textContainer.lineFragmentPadding,
                y: origin.y + rect.midY,
                width: max(0, textContainer.size.width - textContainer.lineFragmentPadding * 2),
                height: 1
            )
            DesignPalette.hairline.setFill()
            lineRect.fill()
        }

        textStorage.enumerateAttribute(.marginalListBulletMarker, in: fullRange) { value, range, _ in
            guard let shapeIndex = value as? Int,
                  let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // The marker character is still laid out at normal size (just transparent), so its own
            // bounding rect already reflects this exact line's real vertical geometry -- centering
            // the shape within it, sized from the font's own xHeight, needs no guessed offsets.
            let charRect = textLineRect(forGlyphRange: glyphRange, in: textContainer)
            let diameter = font.xHeight * 0.85
            let shapeRect = NSRect(
                x: origin.x + charRect.midX - diameter / 2,
                y: origin.y + charRect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            // Cycles filled circle / hollow circle / filled square per nesting level, matching
            // common editors' (Word, Notion, etc.) nested unordered-list marker conventions.
            switch shapeIndex % 3 {
            case 0:
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: shapeRect).fill()
            case 1:
                NSColor.labelColor.setStroke()
                let strokePath = NSBezierPath(ovalIn: shapeRect.insetBy(dx: 0.75, dy: 0.75))
                strokePath.lineWidth = 1.2
                strokePath.stroke()
            default:
                NSColor.labelColor.setFill()
                NSBezierPath(rect: shapeRect).fill()
            }
        }

        textStorage.enumerateAttribute(.marginalOrderedListMarkerText, in: fullRange) { value, range, _ in
            guard let displayText = value as? String,
                  let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
                  let paragraphStyle = textStorage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // The marker text is hidden (transparent) but still laid out at normal size, so its
            // own bounding rect reflects this exact line's real vertical geometry. The literal
            // source digits may auto-renumber to a different, possibly wider, display value (see
            // MarkdownStyler), so this draws into the shared group indent zone rather than
            // being confined to the literal marker's own width -- right-aligned against where
            // the content starts (headIndent), matching how numbered lists conventionally
            // right-align their digits before the period. A explicit gap (matching the one
            // MarkdownStyler reserved room for) is subtracted rather than drawing flush against
            // headIndent: relying on a trailing space's advance width for the gap (an earlier
            // version) is not guaranteed by NSString measurement and read as the number nearly
            // colliding with the following text.
            let charRect = textLineRect(forGlyphRange: glyphRange, in: textContainer)
            let markerAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let markerSize = (displayText as NSString).size(withAttributes: markerAttributes)
            let rightEdge = origin.x + paragraphStyle.headIndent - MarkdownStyler.orderedMarkerContentGap(for: font)
            let markerBaseline = textBaselineY(forGlyphRange: glyphRange).map { $0 - font.ascender }
                ?? (charRect.midY - markerSize.height / 2)
            let drawPoint = NSPoint(x: rightEdge - markerSize.width, y: origin.y + markerBaseline)
            (displayText as NSString).draw(at: drawPoint, withAttributes: markerAttributes)
        }

        textStorage.enumerateAttribute(.marginalTaskCheckboxMarker, in: fullRange) { value, range, _ in
            guard let isComplete = value as? Bool,
                  let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // The hidden "[ ]"/"[x] " text is still laid out at normal size, so its own bounding
            // rect reflects this exact line's real geometry -- the checkbox is anchored at its
            // left edge (where the bullet would otherwise sit) and sized from xHeight, same
            // principle as the bullet/ordered-number markers.
            let charRect = textLineRect(forGlyphRange: glyphRange, in: textContainer)
            let side = font.xHeight * 1.35
            let boxRect = NSRect(x: origin.x + charRect.minX, y: origin.y + charRect.midY - side / 2, width: side, height: side)
            let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

            if isComplete {
                DesignPalette.accent.setFill()
                boxPath.fill()
                let check = NSBezierPath()
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.lineWidth = max(1.2, side * 0.12)
                check.move(to: NSPoint(x: boxRect.minX + side * 0.22, y: boxRect.minY + side * 0.52))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.42, y: boxRect.minY + side * 0.70))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.78, y: boxRect.minY + side * 0.28))
                DesignPalette.accentOn.setStroke()
                check.stroke()
            } else {
                NSColor.tertiaryLabelColor.setStroke()
                boxPath.lineWidth = 1.2
                boxPath.stroke()
            }
        }

        textStorage.enumerateAttribute(.marginalTableGridMarker, in: fullRange) { value, range, _ in
            guard let gridInfo = value as? TableGridInfo, let totalWidth = gridInfo.columnBoundaries.last else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rowRect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let left = origin.x + rowRect.minX
            let top = origin.y + rowRect.minY
            let bottom = origin.y + rowRect.maxY

            if gridInfo.isHeaderRow {
                DesignPalette.surfaceCode.setFill()
                NSRect(x: left, y: top, width: totalWidth, height: rowRect.height).fill()
            }

            DesignPalette.hairline.setStroke()
            for x in gridInfo.columnBoundaries {
                let line = NSBezierPath()
                line.lineWidth = 1
                line.move(to: NSPoint(x: left + x, y: top))
                line.line(to: NSPoint(x: left + x, y: bottom))
                line.stroke()
            }
            let bottomLine = NSBezierPath()
            bottomLine.lineWidth = 1
            bottomLine.move(to: NSPoint(x: left, y: bottom))
            bottomLine.line(to: NSPoint(x: left + totalWidth, y: bottom))
            bottomLine.stroke()
            if gridInfo.isHeaderRow {
                let topLine = NSBezierPath()
                topLine.lineWidth = 1
                topLine.move(to: NSPoint(x: left, y: top))
                topLine.line(to: NSPoint(x: left + totalWidth, y: top))
                topLine.stroke()
            }
        }

        textStorage.enumerateAttribute(.marginalEmojiShortcode, in: fullRange) { value, range, _ in
            guard let info = value as? EmojiGlyphInfo else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // The whole ":shortcode:" run is hidden (tiny font) with a kern on its last character
            // reserving exactly the emoji's own rendered width (see MarkdownStyler), so this
            // first character's own position marks the left edge of that reserved space.
            let charRect = textLineRect(forGlyphRange: glyphRange, in: textContainer)
            let emojiAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: info.fontSize)]
            let emojiSize = (info.emoji as NSString).size(withAttributes: emojiAttributes)
            let emojiFont = (emojiAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: info.fontSize)
            let emojiBaseline = textBaselineY(forGlyphRange: glyphRange).map { $0 - emojiFont.ascender }
                ?? (charRect.midY - emojiSize.height / 2)
            let drawPoint = NSPoint(x: origin.x + charRect.minX, y: origin.y + emojiBaseline)
            (info.emoji as NSString).draw(at: drawPoint, withAttributes: emojiAttributes)
        }

        // Inline images: Task 5 hid (or dimmed, when active) the "![alt](path)" source line and
        // reserved the image's height as `paragraphSpacingBefore` ABOVE that line -- so the markup
        // line keeps its natural height (the caret never balloons to the image's height). That
        // leading space is the band between the line fragment's top and its USED rect's top; the
        // source text sits at the bottom in the used rect. This paints the decoded pixels into
        // that reserved top band, aspect-fit and left-aligned to the text inset, so the image is
        // anchored above its source and never overlaps it. Same `origin`-offset coordinate
        // approach as the decorations above.
        textStorage.enumerateAttribute(.marginalImage, in: fullRange) { value, range, _ in
            guard let info = value as? ImageDisplayInfo else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location < self.numberOfGlyphs else { return }
            let lineRect = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            // The markup line is inflated (via line height) to `band + one source line`, with the
            // source glyphs pushed to the bottom slot (see MarkdownStyler). The card occupies the
            // top `band` region of the fragment; `displaySize.height` IS that band. Using the known
            // band -- rather than a measured used-rect gap -- works uniformly on the first line too
            // (line height, unlike paragraphSpacingBefore, is honored for the first paragraph).
            let band = NSRect(x: origin.x + lineRect.minX, y: origin.y + lineRect.minY,
                              width: lineRect.width, height: min(info.displaySize.height, lineRect.height))
            Self.drawImageCard(in: band,
                               image: ImageCache.shared.image(at: info.resolvedURL),
                               caption: info.caption,
                               fileName: info.resolvedURL.lastPathComponent)
        }
    }

    /// Draws the inline-image "figure card" inside its reserved `band`: a rounded container with a
    /// hairline border and a faint tint, the image aspect-fit and centered in the top area, and a
    /// small dimmed caption beneath it. When `image` is nil (missing/unreadable file) the image
    /// area shows an "unavailable" message instead, in the same card, so the band never sits blank.
    /// Never throws/crashes: `NSString.draw`/`NSBezierPath` are safe on degenerate/tiny rects.
    static func drawImageCard(in band: NSRect, image: NSImage?, caption: String, fileName: String) {
        let m = ImageCardMetrics.self
        let card = NSRect(x: band.minX + m.outerInset, y: band.minY + 2,
                          width: max(0, band.width - 2 * m.outerInset), height: max(0, band.height - 4))
        guard card.width > 8, card.height > 8 else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        // A near-transparent figure that floats on the paper rather than a grey slab: no visible
        // fill (the container reads as the page itself), a hairline edge, and a soft shadow that
        // does the grouping (Law of Common Region) so the border can stay whisper-thin without the
        // card losing its shape. The fill is the page surface only so the shadow has an opaque
        // shape to cast from -- over the paper it's invisible, so the fill still reads as "none".
        let path = NSBezierPath(roundedRect: card, xRadius: m.cornerRadius, yRadius: m.cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 6
        shadow.set()
        DesignPalette.surfacePage.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 0.5   // device-hairline on retina
        path.stroke()

        let inner = card.insetBy(dx: m.padding, dy: m.padding)
        guard inner.width > 0, inner.height > 0 else { return }
        // Split the padded interior into an image area (top) and a caption row (bottom). The
        // caption height is derived from the band, so it stays consistent with the styler's
        // reservation without the layout manager needing to know the caption font size.
        let captionRowH = max(0, min(inner.height, inner.height - m.imageAreaHeight - m.captionGap))
        let imageBox = NSRect(x: inner.minX, y: inner.minY,
                              width: inner.width, height: max(0, inner.height - captionRowH - m.captionGap))
        let captionBox = NSRect(x: inner.minX, y: inner.maxY - captionRowH,
                                width: inner.width, height: captionRowH)

        if let image, imageBox.height > 0 {
            var fitted = aspectFit(imageSize: image.size, into: imageBox)
            fitted.origin.x = imageBox.minX + (imageBox.width - fitted.width) / 2
            fitted.origin.y = imageBox.minY + (imageBox.height - fitted.height) / 2
            image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1.0,
                       respectFlipped: true, hints: nil)
        } else if imageBox.height > 0 {
            drawUnavailableContent(in: imageBox, fileName: fileName)
        }

        if captionRowH > 0, !caption.isEmpty {
            let font = NSFont.systemFont(ofSize: min(13, max(9, captionRowH / 1.3)))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            let text = caption as NSString
            let size = text.size(withAttributes: attrs)
            let point = NSPoint(x: captionBox.minX + max(0, (captionBox.width - size.width) / 2),
                                y: captionBox.minY + max(0, (captionBox.height - size.height) / 2))
            text.draw(at: point, withAttributes: attrs)
        }
    }

    /// The "unavailable" message drawn inside the card's image area when the file can't be loaded
    /// (missing file, unreadable path after a sandbox re-open, corrupt data).
    static func drawUnavailableContent(in box: NSRect, fileName: String) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(13, max(9, box.height * 0.12))),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: min(11, max(8, box.height * 0.10))),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let title = "\u{26A0}\u{FE0E} Image unavailable — click to grant access" as NSString
        let subtitle = fileName as NSString
        let titleSize = title.size(withAttributes: titleAttributes)
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        let spacing: CGFloat = 2
        let blockHeight = titleSize.height + subtitleSize.height + spacing
        let blockTop = box.minY + max(0, (box.height - blockHeight) / 2)

        let titleOrigin = NSPoint(x: box.minX + max(0, (box.width - titleSize.width) / 2), y: blockTop)
        title.draw(at: titleOrigin, withAttributes: titleAttributes)

        let subtitleOrigin = NSPoint(x: box.minX + max(0, (box.width - subtitleSize.width) / 2),
                                      y: blockTop + titleSize.height + spacing)
        subtitle.draw(at: subtitleOrigin, withAttributes: subtitleAttributes)
    }

    /// The largest rect with `imageSize`'s aspect ratio that fits inside `box`, anchored at the
    /// box's top-left. Used to letterbox an inline image into its reserved layout box without
    /// distorting it.
    static func aspectFit(imageSize: NSSize, into box: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return NSRect(x: box.minX, y: box.minY,
                      width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
