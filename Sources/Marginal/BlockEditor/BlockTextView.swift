import AppKit

extension NSAttributedString.Key {
    /// Marks a run's underline as an *explicit* `.underline` inline style, as opposed to the
    /// purely visual underline `BlockViewFactory` also paints under link runs. Read back in
    /// `BlockTextView.currentInlineText` to tell the two apart -- see the comment there.
    static let marginalExplicitUnderline = NSAttributedString.Key("marginalExplicitUnderline")
}

/// Delegate protocol through which a `BlockTextView` reports edits and structural events
/// (Enter, backspace-at-start, Tab, vertical focus movement, selection escaping the block's
/// bounds) to whatever owns the block document -- the text view itself never mutates the
/// document's block structure.
protocol BlockTextViewDelegate: AnyObject {
    func blockTextView(_ view: BlockTextView, didEditInlineText text: InlineText)
    func blockTextViewDidPressEnter(_ view: BlockTextView, atOffset offset: Int)
    func blockTextViewDidBackspaceAtStart(_ view: BlockTextView)
    func blockTextViewDidPressTab(_ view: BlockTextView, backward: Bool)
    func blockTextView(_ view: BlockTextView, moveFocusVertically up: Bool, caretX: CGFloat)
    func blockTextView(_ view: BlockTextView, selectionEscapedBoundary up: Bool)
}

/// One block's text view. Renders a single block's `InlineText` as an attributed string and
/// intercepts the handful of key commands (Enter, backspace-at-start, Tab, vertical arrows,
/// shift-arrow past the block's own bounds) that need to be handled at the *document* level
/// (splitting/merging/indenting blocks, moving focus between blocks) instead of mutating this
/// block's own text storage.
final class BlockTextView: NSTextView {
    weak var blockDelegate: BlockTextViewDelegate?
    var blockID: UUID!

    convenience init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        self.init(frame: .zero, textContainer: textContainer)
        configure()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        allowsUndo = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        drawsBackground = false
        isRichText = true
    }

    // MARK: - Rendering

    /// Builds the attributed string for `text` under `kind`'s styling rules and installs it into
    /// the view's text storage, replacing whatever was there.
    func render(_ text: InlineText, asKind kind: BlockKind, baseFont: NSFont) {
        let attributed = BlockViewFactory.attributedString(for: text, kind: kind, baseFont: baseFont)
        textStorage?.setAttributedString(attributed)
    }

    /// Reads the text storage's current attributes back into `InlineRun`s -- the inverse of
    /// `render(_:asKind:baseFont:)`. Font traits (bold/italic), the monospaced code font,
    /// strikethrough/underline attributes, and the `.link` attribute each round-trip into the
    /// matching `InlineStyle` flag / `linkURL`.
    var currentInlineText: InlineText {
        guard let storage = textStorage, storage.length > 0 else { return InlineText() }
        var runs: [InlineRun] = []
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let substring = (storage.string as NSString).substring(with: range)
            var style: InlineStyle = []

            if let font = attributes[.font] as? NSFont {
                let traits = NSFontManager.shared.traits(of: font)
                if traits.contains(.italicFontMask) {
                    style.insert(.italic)
                }
                if font.isBoldWeight {
                    style.insert(.bold)
                }
                if font.isMonospaced {
                    style.insert(.code)
                }
            }

            if let strikethrough = attributes[.strikethroughStyle] as? Int, strikethrough != 0 {
                style.insert(.strikethrough)
            }

            var linkURL: String? = nil
            if let link = attributes[.link] as? String {
                linkURL = link
            } else if let link = attributes[.link] as? URL {
                linkURL = link.absoluteString
            }

            // The visual underline under a link is rendered with plain `.underlineStyle` (same
            // attribute an explicit underline style uses), so it can't be told apart from a real
            // `.underline` run just by reading that attribute back -- a link-only run would
            // otherwise gain a spurious `.underline` bit on every round-trip. The private
            // `.marginalExplicitUnderline` marker (set only when the *run* itself asked for
            // underline, in `BlockViewFactory.attributedString(for:kind:baseFont:)`) disambiguates:
            // an underline is only inferred as an explicit style bit when that marker is present.
            let hasExplicitUnderlineMarker = (attributes[.marginalExplicitUnderline] as? Bool) == true
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                if linkURL == nil || hasExplicitUnderlineMarker {
                    style.insert(.underline)
                }
            }

            runs.append(InlineRun(text: substring, style: style, linkURL: linkURL))
        }
        return InlineText(runs: runs)
    }

    var caretOffset: Int {
        get { selectedRange().location }
        set { setSelectedRange(NSRange(location: newValue, length: 0)) }
    }

    // MARK: - Command interception

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            blockDelegate?.blockTextViewDidPressEnter(self, atOffset: selectedRange().location)
            return

        case #selector(NSResponder.deleteBackward(_:)):
            let selection = selectedRange()
            if selection.location == 0 && selection.length == 0 {
                blockDelegate?.blockTextViewDidBackspaceAtStart(self)
                return
            }

        case #selector(NSResponder.insertTab(_:)):
            blockDelegate?.blockTextViewDidPressTab(self, backward: false)
            return

        case #selector(NSResponder.insertBacktab(_:)):
            blockDelegate?.blockTextViewDidPressTab(self, backward: true)
            return

        case #selector(NSResponder.moveUp(_:)):
            if isCaretOnFirstVisualLine {
                blockDelegate?.blockTextView(self, moveFocusVertically: true, caretX: caretXPosition)
                return
            }

        case #selector(NSResponder.moveDown(_:)):
            if isCaretOnLastVisualLine {
                blockDelegate?.blockTextView(self, moveFocusVertically: false, caretX: caretXPosition)
                return
            }

        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            if isCaretOnFirstVisualLine {
                blockDelegate?.blockTextView(self, selectionEscapedBoundary: true)
                return
            }

        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            if isCaretOnLastVisualLine {
                blockDelegate?.blockTextView(self, selectionEscapedBoundary: false)
                return
            }

        default:
            break
        }

        super.doCommand(by: selector)
    }

    /// The x-position (in the view's own coordinate space) of the caret's current insertion point
    /// -- used to preserve horizontal position when focus moves vertically into a neighboring
    /// block's text view.
    private var caretXPosition: CGFloat {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return 0 }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: selectedRange().location)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 0), in: textContainer)
        return rect.minX + textContainerOrigin.x
    }

    private var isCaretOnFirstVisualLine: Bool {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return true }
        let caretIndex = selectedRange().location
        guard layoutManager.numberOfGlyphs > 0 else { return true }
        var caretLineRange = NSRange(location: 0, length: 0)
        let caretGlyphIndex = min(layoutManager.glyphIndexForCharacter(at: caretIndex), max(layoutManager.numberOfGlyphs - 1, 0))
        let caretLineRect = layoutManager.lineFragmentRect(forGlyphAt: caretGlyphIndex, effectiveRange: &caretLineRange)

        var firstLineRange = NSRange(location: 0, length: 0)
        let firstLineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &firstLineRange)
        _ = textContainer
        return caretLineRect.minY <= firstLineRect.minY + 0.5
    }

    private var isCaretOnLastVisualLine: Bool {
        guard let layoutManager = layoutManager, layoutManager.numberOfGlyphs > 0 else { return true }
        let caretIndex = selectedRange().location
        var caretLineRange = NSRange(location: 0, length: 0)
        let caretGlyphIndex = min(layoutManager.glyphIndexForCharacter(at: caretIndex), max(layoutManager.numberOfGlyphs - 1, 0))
        let caretLineRect = layoutManager.lineFragmentRect(forGlyphAt: caretGlyphIndex, effectiveRange: &caretLineRange)

        var lastLineRange = NSRange(location: 0, length: 0)
        let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: &lastLineRange)
        return caretLineRect.minY >= lastLineRect.minY - 0.5
    }
}

private extension NSFont {
    var isMonospaced: Bool {
        // `NSFont.monospacedSystemFont` produces fonts whose fixed-pitch fontDescriptor trait is
        // set; `isFixedPitch` is the reliable cross-version check.
        return fontDescriptor.symbolicTraits.contains(.monoSpace) || isFixedPitch
    }

    var isBoldWeight: Bool {
        // The design system's "bold" is semibold (600), not the NSFontManager .boldFontMask
        // trait -- system semibold fonts don't set that trait. NSFontManager's own integer
        // weight scale (regular=5, medium=6, semibold=8, bold=9) is the reliable read; matches
        // anything at semibold or heavier.
        return NSFontManager.shared.weight(of: self) >= 8
    }
}
