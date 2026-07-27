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

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage, let textContainer = textContainers.first else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Drawn first so every other decoration (blockquote bar, bullets, grid lines) layers on
        // top of the card, never underneath it.
        textStorage.enumerateAttribute(.marginalCodeBlockMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
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
                x: origin.x + textContainer.lineFragmentPadding,
                y: origin.y + top,
                width: max(0, textContainer.size.width - textContainer.lineFragmentPadding * 2),
                height: bottom - top
            )
            NSColor.textBackgroundColor.blended(withFraction: 0.04, of: .labelColor)?.setFill()
            NSBezierPath(roundedRect: cardRect, xRadius: 10, yRadius: 10).fill()
        }

        textStorage.enumerateAttribute(.marginalBlockquoteMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // Solid text color, matching Notion's quote bar (border-left: 3px solid currentColor).
            NSColor.labelColor.setFill()
            enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, _, _, _ in
                let barRect = NSRect(x: origin.x + lineRect.minX, y: origin.y + lineRect.minY, width: 3, height: lineRect.height)
                barRect.fill()
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
            NSColor.separatorColor.setFill()
            lineRect.fill()
        }

        textStorage.enumerateAttribute(.marginalListBulletMarker, in: fullRange) { value, range, _ in
            guard let shapeIndex = value as? Int,
                  let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // The marker character is still laid out at normal size (just transparent), so its own
            // bounding rect already reflects this exact line's real vertical geometry -- centering
            // the shape within it, sized from the font's own xHeight, needs no guessed offsets.
            let charRect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
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
            let charRect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let markerAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let markerSize = (displayText as NSString).size(withAttributes: markerAttributes)
            let rightEdge = origin.x + paragraphStyle.headIndent - MarkdownStyler.orderedMarkerContentGap(for: font)
            let drawPoint = NSPoint(x: rightEdge - markerSize.width, y: origin.y + charRect.midY - markerSize.height / 2)
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
            let charRect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let side = font.xHeight * 1.35
            let boxRect = NSRect(x: origin.x + charRect.minX, y: origin.y + charRect.midY - side / 2, width: side, height: side)
            let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3)

            if isComplete {
                NSColor.controlAccentColor.setFill()
                boxPath.fill()
                let check = NSBezierPath()
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.lineWidth = max(1.2, side * 0.12)
                check.move(to: NSPoint(x: boxRect.minX + side * 0.22, y: boxRect.minY + side * 0.52))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.42, y: boxRect.minY + side * 0.70))
                check.line(to: NSPoint(x: boxRect.minX + side * 0.78, y: boxRect.minY + side * 0.28))
                NSColor.white.setStroke()
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
                NSColor.textBackgroundColor.blended(withFraction: 0.04, of: .labelColor)?.setFill()
                NSRect(x: left, y: top, width: totalWidth, height: rowRect.height).fill()
            }

            NSColor.separatorColor.setStroke()
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
            let charRect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let emojiAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: info.fontSize)]
            let emojiSize = (info.emoji as NSString).size(withAttributes: emojiAttributes)
            let drawPoint = NSPoint(x: origin.x + charRect.minX, y: origin.y + charRect.midY - emojiSize.height / 2)
            (info.emoji as NSString).draw(at: drawPoint, withAttributes: emojiAttributes)
        }
    }
}
