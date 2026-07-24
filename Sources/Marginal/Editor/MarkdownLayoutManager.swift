import AppKit

extension NSAttributedString.Key {
    static let marginalBlockquoteMarker = NSAttributedString.Key("marginalBlockquoteMarker")
    static let marginalHorizontalRuleMarker = NSAttributedString.Key("marginalHorizontalRuleMarker")
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

        textStorage.enumerateAttribute(.marginalBlockquoteMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
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
    }
}
