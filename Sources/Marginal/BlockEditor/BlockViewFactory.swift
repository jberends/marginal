import AppKit

/// Builds the per-block `NSView` hierarchy and the attributed-string rendering rules shared by
/// every block kind. `BlockViewFactory` is the only place that knows how a `BlockKind` maps onto
/// AppKit views/fonts/colors -- the block engine (Sources/Marginal/Blocks) stays UI-free, and the
/// (future) document-level controller stays layout-free.
enum BlockViewFactory {

    /// Notion's heading scale, indexed by (level - 1): H1 is 1.875x the base size, down to H6 at
    /// 0.875x.
    private static let headingScale: [CGFloat] = [1.875, 1.5, 1.25, 1.125, 1.0, 0.875]

    /// Fixed per-indent-level gutter width for list item markers (bullet/number/checkbox).
    static let listGutterStep: CGFloat = 24

    // MARK: - Attributes

    /// The block-level base attributes (font + text color) a block kind renders its plain text
    /// with, before any per-run inline styling (bold/italic/code/link) is layered on top.
    static func attributes(for kind: BlockKind, baseFont: NSFont) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .heading(let level, _):
            let clampedLevel = min(max(level, 1), headingScale.count)
            let scale = headingScale[clampedLevel - 1]
            let font = NSFont.systemFont(ofSize: baseFont.pointSize * scale, weight: .semibold)
            return [.font: font, .foregroundColor: NSColor.labelColor]

        case .codeBlock:
            // A full code block renders at 0.85x with 1.5x line height, inside its own rounded
            // card (see `CodeBlockCardView`) -- unlike an *inline* code run sitting inside
            // otherwise-regular text, which also uses 0.85x but stays at the paragraph's own
            // line height and gets its background from a per-character `.backgroundColor`
            // instead of a card.
            let font = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.85, weight: .regular)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.5
            return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraphStyle]

        case .paragraph, .listItem, .quote, .table, .divider:
            return [.font: baseFont, .foregroundColor: NSColor.labelColor]
        }
    }

    /// Builds the attributed string for `text` under `kind`'s block-level attributes, layering
    /// each run's inline style (bold/italic/strikethrough/underline/code/link) on top.
    static func attributedString(for text: InlineText, kind: BlockKind, baseFont: NSFont) -> NSAttributedString {
        let base = attributes(for: kind, baseFont: baseFont)
        let baseParagraphFont = (base[.font] as? NSFont) ?? baseFont
        let result = NSMutableAttributedString()

        for run in text.runs {
            var attrs = base
            var font = baseParagraphFont

            if run.style.contains(.code) {
                // Bold/italic layer onto the monospaced font itself (not the proportional base
                // font) so a "**`code`**" run keeps both its mono face and its weight/slant --
                // .code no longer unconditionally overwrites font, which used to silently drop
                // any bold/italic also present on the same run.
                font = NSFont.monospacedSystemFont(
                    ofSize: baseFont.pointSize * 0.85,
                    weight: run.style.contains(.bold) ? .semibold : .regular
                )
                if run.style.contains(.italic) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                attrs[.backgroundColor] = DesignPalette.surfaceCode
                attrs[.foregroundColor] = DesignPalette.accent
            } else {
                if run.style.contains(.bold) {
                    // Semibold (600) -- Notion's "bold" weight; the design system never uses 700.
                    font = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
                }
                if run.style.contains(.italic) {
                    font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
            }
            attrs[.font] = font

            if run.style.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.style.contains(.underline) {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                // Distinguishes an explicit underline style from the purely visual underline a
                // link also gets below -- see `.marginalExplicitUnderline`'s doc comment.
                attrs[.marginalExplicitUnderline] = true
            }
            if let linkURL = run.linkURL {
                attrs[.link] = linkURL
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.foregroundColor] = DesignPalette.accent
            }

            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }

        return result
    }

    // MARK: - Views

    /// Builds the view for one block: a bare `BlockTextView` for paragraphs/headings/code blocks,
    /// a marker-gutter-wrapped text view for list items, a bar-wrapped text view for quotes, and
    /// a fixed-height hairline view for dividers.
    @MainActor
    static func view(for block: Block, baseFont: NSFont, textDelegate: BlockTextViewDelegate) -> NSView {
        switch block.kind {
        case .paragraph(let text), .heading(_, let text):
            return makeTextView(text: text, kind: block.kind, baseFont: baseFont, blockID: block.id, textDelegate: textDelegate)

        case .codeBlock(_, let code):
            let textView = makeTextView(text: InlineText(code), kind: block.kind, baseFont: baseFont, blockID: block.id, textDelegate: textDelegate)
            applyCodeHighlighting(to: textView, code: code)
            return CodeBlockCardView(textView: textView, baseFont: baseFont)

        case .quote(let text):
            let textView = makeTextView(text: text, kind: block.kind, baseFont: baseFont, blockID: block.id, textDelegate: textDelegate)
            return QuoteWrapperView(textView: textView, baseFont: baseFont)

        case .listItem(let style, let indent, let text):
            let textView = makeTextView(text: text, kind: block.kind, baseFont: baseFont, blockID: block.id, textDelegate: textDelegate)
            return ListItemWrapperView(textView: textView, markerText: markerText(for: style), indent: indent)

        case .divider:
            return DividerView()

        case .table(let alignments, let header, let rows):
            return BlockTableView(blockID: block.id, alignments: alignments, header: header, rows: rows, baseFont: baseFont)
        }
    }

    /// The gutter marker text for a list item's style. Ordered lists always show "1." here --
    /// the real running number is computed by the document-level controller (Task 10), which
    /// knows this item's position among its siblings; this factory only sees one block at a time.
    static func markerText(for style: ListStyle) -> String {
        switch style {
        case .bullet:
            return "•"
        case .ordered:
            return "1."
        case .task(let done):
            return done ? "☑" : "☐"
        }
    }

    /// Re-applies `MarkdownParser.parseCodeHighlightTokens` coloring over a code block's text
    /// storage -- shared between the initial factory render above and the document controller's
    /// re-render after every edit (Task 12), so the two paths can never drift. Token kind -> color
    /// mapping: `.string`/`.comment`/`.number`; any other kind gets no color override.
    static func applyCodeHighlighting(to textView: BlockTextView, code: String) {
        guard let storage = textView.textStorage else { return }
        for token in MarkdownParser.parseCodeHighlightTokens(in: code) {
            let nsRange = NSRange(token.range, in: code)
            guard nsRange.location != NSNotFound, nsRange.location + nsRange.length <= storage.length else { continue }

            let tokenColor: NSColor
            switch token.kind {
            case .string: tokenColor = DesignPalette.synString
            case .comment: tokenColor = DesignPalette.synComment
            case .number: tokenColor = DesignPalette.synNumber
            }
            storage.addAttribute(.foregroundColor, value: tokenColor, range: nsRange)
        }
    }

    private static func makeTextView(text: InlineText, kind: BlockKind, baseFont: NSFont, blockID: UUID, textDelegate: BlockTextViewDelegate) -> BlockTextView {
        let textView = BlockTextView()
        textView.blockID = blockID
        textView.blockDelegate = textDelegate
        textView.render(text, asKind: kind, baseFont: baseFont)
        return textView
    }

    /// Finds the `BlockTextView` embedded inside a block's wrapper view (as returned by
    /// `view(for:baseFont:textDelegate:)`) -- bare for paragraphs/headings/code blocks, nested
    /// one level inside list-item and quote wrappers, and absent for dividers/tables. Lets the
    /// document-level controller (Task 10) reach the text view without knowing each wrapper's
    /// internal shape.
    static func textView(in wrapper: NSView) -> BlockTextView? {
        if let textView = wrapper as? BlockTextView {
            return textView
        }
        if let listItem = wrapper as? ListItemWrapperView {
            return listItem.textView
        }
        if let quote = wrapper as? QuoteWrapperView {
            return quote.textView
        }
        if let codeCard = wrapper as? CodeBlockCardView {
            return codeCard.textView
        }
        return nil
    }
}

/// Wraps a list item's `BlockTextView` with a fixed leading gutter slot (`24 * (indent + 1)` pt)
/// containing the bullet/number/checkbox marker, right-aligned against the text's own inset.
final class ListItemWrapperView: NSView {
    let textView: BlockTextView
    let markerLabel: NSTextField

    init(textView: BlockTextView, markerText: String, indent: Int) {
        self.textView = textView
        self.markerLabel = NSTextField(labelWithString: markerText)
        super.init(frame: .zero)

        let gutterWidth = BlockViewFactory.listGutterStep * CGFloat(indent + 1)

        markerLabel.alignment = .right
        markerLabel.font = textView.font ?? .systemFont(ofSize: 16)
        markerLabel.textColor = .labelColor
        markerLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(markerLabel)
        addSubview(textView)

        NSLayoutConstraint.activate([
            markerLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            markerLabel.widthAnchor.constraint(equalToConstant: gutterWidth),
            markerLabel.topAnchor.constraint(equalTo: topAnchor),
            markerLabel.trailingAnchor.constraint(equalTo: textView.leadingAnchor),

            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The gutter marker's displayed text. Bullets/checkboxes never change after creation, but
    /// an ordered item's running number depends on its position among sibling items -- something
    /// only the document-level controller (Task 10) knows -- so this must stay settable after
    /// the wrapper is built, not just an `init` parameter.
    var markerText: String {
        get { markerLabel.stringValue }
        set { markerLabel.stringValue = newValue }
    }
}

/// Wraps a quote's `BlockTextView` with a 3px `labelColor` bar at the leading edge and inset the
/// text by 0.875em -- matching Notion's blockquote padding.
final class QuoteWrapperView: NSView {
    let textView: BlockTextView
    let barView: NSView

    init(textView: BlockTextView, baseFont: NSFont) {
        self.textView = textView
        self.barView = NSView()
        super.init(frame: .zero)

        let contentInset = baseFont.pointSize * 0.875
        let barWidth: CGFloat = 3

        barView.wantsLayer = true
        barView.layer?.backgroundColor = NSColor.labelColor.cgColor
        barView.translatesAutoresizingMaskIntoConstraints = false

        textView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(barView)
        addSubview(textView)

        NSLayoutConstraint.activate([
            barView.leadingAnchor.constraint(equalTo: leadingAnchor),
            barView.widthAnchor.constraint(equalToConstant: barWidth),
            barView.topAnchor.constraint(equalTo: topAnchor),
            barView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInset),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Wraps a code block's `BlockTextView` in a rounded `DesignPalette.surfaceCode` card, following
/// the `QuoteWrapperView`/`ListItemWrapperView` pattern -- the card's fill + 10pt corner radius
/// replaces the per-character background an *inline* code run gets, and the text is inset by
/// 1.375em on every side (Notion's code-block padding).
final class CodeBlockCardView: NSView {
    let textView: BlockTextView

    init(textView: BlockTextView, baseFont: NSFont) {
        self.textView = textView
        super.init(frame: .zero)

        let contentInset = baseFont.pointSize * 1.375

        wantsLayer = true
        layer?.backgroundColor = DesignPalette.surfaceCode.cgColor
        layer?.cornerRadius = 10

        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInset),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInset),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: contentInset),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInset)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// A horizontal rule: a 1px `DesignPalette.hairline` line centered in a fixed 13pt-tall view.
final class DividerView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let y = bounds.midY
        context.setFillColor(DesignPalette.hairline.cgColor)
        context.fill(CGRect(x: bounds.minX, y: y, width: bounds.width, height: 1))
    }
}
