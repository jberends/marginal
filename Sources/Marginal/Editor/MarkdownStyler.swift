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

        for header in model.headers {
            let headerFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: headerPointSize(for: header.level, baseSize: baseFont.pointSize)),
                toHaveTrait: .boldFontMask
            )
            result.addAttribute(.font, value: headerFont, range: NSRange(header.contentRange, in: text))

            let markerRange = NSRange(header.markerRange, in: text)
            result.addAttribute(.font, value: revealedHeaders.contains(header) ? headerFont : hiddenFont, range: markerRange)
        }

        for span in model.inlineStyles {
            let contentRange = NSRange(span.contentRange, in: text)
            switch span.kind {
            case .bold:
                result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask), range: contentRange)
            case .italic:
                result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask), range: contentRange)
            case .strikethrough:
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            case .underline:
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }

            let delimiterFont = revealedStyles.contains(span) ? baseFont : hiddenFont
            result.addAttribute(.font, value: delimiterFont, range: NSRange(span.openingDelimiterRange, in: text))
            result.addAttribute(.font, value: delimiterFont, range: NSRange(span.closingDelimiterRange, in: text))
        }

        for link in model.links {
            let textRange = NSRange(link.textRange, in: text)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            result.addAttribute(.link, value: link.url, range: textRange)
        }

        for item in model.listItems {
            let markerRange = NSRange(item.markerRange, in: text)
            result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markerRange)

            if case .unordered = item.kind, markerRange.length > 0 {
                let markerCharacterRange = NSRange(location: markerRange.location, length: 1)
                let markerCharacter = String((text as NSString).substring(with: markerCharacterRange))
                if let glyphInfo = NSGlyphInfo(glyphName: "bullet", for: baseFont, baseString: markerCharacter) {
                    result.addAttribute(.glyphInfo, value: glyphInfo, range: markerCharacterRange)
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
