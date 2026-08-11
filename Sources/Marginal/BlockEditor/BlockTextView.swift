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
    /// Escape was pressed while `view` is focused -- the delegate selects `view`'s whole block
    /// (see `BlockSelectionController`).
    func blockTextViewDidPressEscape(_ view: BlockTextView)
    /// A mouse click landed in `view` -- reported *before* the click is otherwise handled (see
    /// `mouseDown(with:)` below) so the delegate can clear an active whole-block selection and
    /// return to normal text editing.
    func blockTextViewDidReceiveClick(_ view: BlockTextView)
    /// A ⌘B/⌘I/⌘U/⌘⇧S style toggle (see `BlockTextView.toggleStyleBold(_:)` etc.) already
    /// computed `text` (the block's `InlineText` with `style` toggled over the selection) --
    /// the delegate persists it into the document model, re-renders `view` through
    /// `BlockViewFactory` (so the semibold/italic/underline/strikethrough styling actually
    /// shows), and restores `selection` since re-rendering replaces the text storage and would
    /// otherwise collapse the selection.
    func blockTextView(_ view: BlockTextView, didToggleStyle text: InlineText, selection: NSRange)
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

    // MARK: - Auto Layout height

    /// An `NSTextView` reports no useful height to Auto Layout on its own, so inside the block
    /// editor's vertical `NSStackView` every block would collapse to nothing and the blocks would
    /// all paint on top of each other. The block's real height is whatever TextKit actually laid
    /// the text out to occupy, plus the container insets.
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: ceil(used.height) + textContainerInset.height * 2)
    }

    /// Text got longer or shorter (typing, or a re-render): the laid-out height changed with it.
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    /// A width change re-wraps the text, which changes how many lines it occupies -- so the
    /// height Auto Layout was given is stale until the new layout is measured.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            textContainer?.containerSize = CGSize(width: newSize.width,
                                                  height: CGFloat.greatestFiniteMagnitude)
            invalidateIntrinsicContentSize()
        }
    }

    // MARK: - Rendering

    /// Builds the attributed string for `text` under `kind`'s styling rules and installs it into
    /// the view's text storage, replacing whatever was there.
    func render(_ text: InlineText, asKind kind: BlockKind, baseFont: NSFont) {
        let attributed = BlockViewFactory.attributedString(for: text, kind: kind, baseFont: baseFont)
        textStorage?.setAttributedString(attributed)
        // Setting the storage directly bypasses didChangeText(), so the new laid-out height has
        // to be reported to Auto Layout here instead.
        invalidateIntrinsicContentSize()
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

    /// Character offset (not UTF-16 code-unit offset) into `string`. `NSTextView.selectedRange()`
    /// reports UTF-16 locations, but the block model (`InlineText.length`/`split(at:)`, `Caret`,
    /// `InlineAutoformat`) counts in `Character`s -- the two diverge as soon as the text contains
    /// any codepoint outside the BMP (this app promotes emoji shortcodes like `:tada:` to their
    /// literal 🎉 at parse time, so this is common, not exotic). This getter/setter is the single
    /// conversion point so every other caller of `caretOffset` gets/sets a plain Character offset
    /// uniformly, regardless of what's actually in the text. `limitedBy`/`samePosition` guards
    /// make a malformed offset fail safe (clamp to the string's end) instead of crashing.
    var caretOffset: Int {
        get { characterOffset(fromUTF16: selectedRange().location) }
        set {
            let text = string
            let clampedCharacterOffset = max(0, newValue)
            guard let index = text.index(text.startIndex, offsetBy: clampedCharacterOffset, limitedBy: text.endIndex),
                  let utf16Index = index.samePosition(in: text.utf16) else {
                setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
                return
            }
            let utf16Offset = text.utf16.distance(from: text.utf16.startIndex, to: utf16Index)
            setSelectedRange(NSRange(location: utf16Offset, length: 0))
        }
    }

    /// Converts a UTF-16 code-unit offset into `string` (the indexing convention of
    /// `selectedRange().location` and, e.g., `characterIndexForInsertion(at:)`) into a Character
    /// offset. Shared by `caretOffset`'s getter and by callers that get a UTF-16 index from some
    /// other AppKit API (see `BlockEditorViewController.blockTextView(_:moveFocusVertically:caretX:)`,
    /// which does exactly that with `characterIndexForInsertion(at:)`).
    func characterOffset(fromUTF16 utf16Location: Int) -> Int {
        let text = string
        let clampedLocation = max(0, utf16Location)
        guard let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clampedLocation, limitedBy: text.utf16.endIndex),
              let index = utf16Index.samePosition(in: text) else {
            return text.count
        }
        return text.distance(from: text.startIndex, to: index)
    }

    /// Converts a UTF-16 `NSRange` (as reported by `selectedRange()`) into a `Range<Int>` of
    /// Character offsets into `string` -- the same UTF-16/Character mismatch `caretOffset` guards
    /// against, but for a length-bearing selection (used by the style-toggle path below, which
    /// hands a selection straight to `InlineAutoformat.toggling`'s `Range<Int>` of Characters).
    /// Returns nil if either endpoint doesn't land on a Character boundary.
    private func characterRange(from nsRange: NSRange) -> Range<Int>? {
        let text = string
        guard let startUTF16 = text.utf16.index(text.utf16.startIndex, offsetBy: nsRange.location, limitedBy: text.utf16.endIndex),
              let endUTF16 = text.utf16.index(startUTF16, offsetBy: nsRange.length, limitedBy: text.utf16.endIndex),
              let startIndex = startUTF16.samePosition(in: text),
              let endIndex = endUTF16.samePosition(in: text) else {
            return nil
        }
        return text.distance(from: text.startIndex, to: startIndex)..<text.distance(from: text.startIndex, to: endIndex)
    }

    // MARK: - Style toggles (⌘B / ⌘I / ⌘U / ⌘⇧S)

    /// These are plain `@objc` menu-action methods (not part of the command-interception
    /// dispatch above -- they're never routed through `doCommand(by:)`, AppKit invokes them
    /// directly via the responder chain from `Format` menu items whose `action` names them).
    /// Each computes the current selection, toggles `style` over it on the *model*
    /// (`InlineAutoformat.toggling`, operating on `currentInlineText` read back from this
    /// view's own text storage), and hands the result to `blockDelegate` -- this view never
    /// hand-patches its own attributed string for a toggle, `didToggleStyle` re-renders it
    /// through `BlockViewFactory` so semibold/italic/underline/strikethrough all match the
    /// design system (see the brief's design-constraints note on why bold means semibold, not
    /// the `NSFontManager` bold trait).
    @objc func toggleStyleBold(_ sender: Any?) { toggleStyle(.bold) }
    @objc func toggleStyleItalic(_ sender: Any?) { toggleStyle(.italic) }
    @objc func toggleStyleUnderline(_ sender: Any?) { toggleStyle(.underline) }
    @objc func toggleStyleStrikethrough(_ sender: Any?) { toggleStyle(.strikethrough) }

    private func toggleStyle(_ style: InlineStyle) {
        let selection = selectedRange()
        guard selection.length > 0 else { return }
        let text = currentInlineText
        // `selection` is a UTF-16 NSRange; `text.length` (InlineText) counts Characters -- must
        // convert before comparing/indexing, same UTF-16-vs-Character mismatch `caretOffset`
        // guards against elsewhere in this file.
        guard let range = characterRange(from: selection), range.upperBound <= text.length else { return }
        let toggled = InlineAutoformat.toggling(text, range: range, style: style)
        blockDelegate?.blockTextView(self, didToggleStyle: toggled, selection: selection)
    }

    // MARK: - Command interception

    // Each concrete NSStandardKeyBindingResponding override below is the single place its
    // command is intercepted: it makes the decision (is the caret at the boundary that means
    // "hand this to the document controller?") and, when the answer is no, falls back to the
    // real `super.<method>(sender)` -- NSTextView's own implementation -- to get normal editing
    // behavior (actually deleting a character, actually moving the caret up a line, etc.).
    //
    // `doCommand(by:)` is *not* a second, independent place this logic lives. NSTextView's own
    // keyDown -> interpretKeyEvents(_:) flow calls `doCommand(by:)` exclusively for these
    // selectors -- it never calls the concrete action method directly -- so `doCommand(by:)`
    // below just dispatches each selector straight into its concrete override. That keeps both
    // call paths (a real key event, and a direct call to e.g. `deleteBackward(nil)` from a menu
    // item / accessibility action / test) behaving identically, without the recursion a prior
    // version of this file had: that version put the decision in `doCommand(by:)` and fell back
    // to `super.doCommand(by: selector)` on "no", but `NSResponder.doCommand(by:)`'s own default
    // implementation re-invokes the overridden concrete method (`self.deleteBackward(_:)`, since
    // that's the dynamic type), which called `doCommand(by:)` again -- an infinite loop that
    // crashed (`EXC_BAD_ACCESS`) on any mid-block backspace or off-boundary arrow press. Falling
    // back to `super.<concreteMethod>(sender)` here instead reaches `NSTextView`'s real
    // implementation directly, so there is nothing left to recurse through.
    override func insertNewline(_ sender: Any?) {
        // `atOffset` feeds straight into `BlockEditEngine.split` -> `InlineText.split(at:)`, which
        // counts Characters, not UTF-16 code units -- `caretOffset` (not `selectedRange().location`)
        // is the Character-offset conversion of the caret position (see its doc comment).
        blockDelegate?.blockTextViewDidPressEnter(self, atOffset: caretOffset)
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        if selection.location == 0 && selection.length == 0 {
            blockDelegate?.blockTextViewDidBackspaceAtStart(self)
            return
        }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) {
        blockDelegate?.blockTextViewDidPressTab(self, backward: false)
    }

    override func insertBacktab(_ sender: Any?) {
        blockDelegate?.blockTextViewDidPressTab(self, backward: true)
    }

    override func moveUp(_ sender: Any?) {
        if isCaretOnFirstVisualLine {
            blockDelegate?.blockTextView(self, moveFocusVertically: true, caretX: caretXPosition)
            return
        }
        super.moveUp(sender)
    }

    override func moveDown(_ sender: Any?) {
        if isCaretOnLastVisualLine {
            blockDelegate?.blockTextView(self, moveFocusVertically: false, caretX: caretXPosition)
            return
        }
        super.moveDown(sender)
    }

    override func moveUpAndModifySelection(_ sender: Any?) {
        if isCaretOnFirstVisualLine {
            blockDelegate?.blockTextView(self, selectionEscapedBoundary: true)
            return
        }
        super.moveUpAndModifySelection(sender)
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
        if isCaretOnLastVisualLine {
            blockDelegate?.blockTextView(self, selectionEscapedBoundary: false)
            return
        }
        super.moveDownAndModifySelection(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        blockDelegate?.blockTextViewDidPressEscape(self)
    }

    /// Any click clears an active whole-block selection (see `BlockSelectionController`) before
    /// falling through to `super.mouseDown`, which does the real hit-testing/caret placement.
    override func mouseDown(with event: NSEvent) {
        blockDelegate?.blockTextViewDidReceiveClick(self)
        super.mouseDown(with: event)
    }

    /// The real key-event path (`interpretKeyEvents(_:)`) reaches every command above only
    /// through here, never through the concrete method directly -- so this just routes each
    /// selector into its concrete override (see the comment above) and forwards anything else
    /// (selectors this class doesn't care about) to `super.doCommand(by:)` unchanged.
    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            insertNewline(nil)
        case #selector(NSResponder.deleteBackward(_:)):
            deleteBackward(nil)
        case #selector(NSResponder.insertTab(_:)):
            insertTab(nil)
        case #selector(NSResponder.insertBacktab(_:)):
            insertBacktab(nil)
        case #selector(NSResponder.moveUp(_:)):
            moveUp(nil)
        case #selector(NSResponder.moveDown(_:)):
            moveDown(nil)
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            moveUpAndModifySelection(nil)
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            moveDownAndModifySelection(nil)
        case #selector(NSResponder.cancelOperation(_:)):
            cancelOperation(nil)
        default:
            super.doCommand(by: selector)
        }
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
