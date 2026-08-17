import AppKit

@MainActor
protocol MarkdownTextViewShortcutDelegate: AnyObject {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedMarkdownFileAt url: URL)
    /// A real image FILE was dropped (linked, not managed): insert an absolute-path image at `characterIndex`.
    func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedImageFileAt url: URL, atCharacterIndex characterIndex: Int)
    /// Return true if an image was found on the pasteboard and handled (markup inserted).
    func markdownTextViewInsertPastedImage(_ textView: MarkdownTextView) -> Bool
    /// The "image unavailable" placeholder was clicked: `resolvedURL` is the image the document
    /// references but currently can't load. Implementers should offer a way to grant access to
    /// the folder containing it (see `DocumentViewController`'s NSOpenPanel-backed grant flow).
    func markdownTextViewRequestImageAccess(_ textView: MarkdownTextView, resolvedURL: URL)
}

/// Every extension Marginal opens as a document. A .txt is markdown without markup, so it opens
/// in its own tab exactly like a .md rather than being treated as different in kind.
private let markdownFileExtensions: Set<String> = ["md", "markdown", "txt", "text"]

private let imageFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"]

final class MarkdownTextView: NSTextView {

    weak var shortcutDelegate: MarkdownTextViewShortcutDelegate?

    /// Decides what a link activation means -- an external URL to hand to the browser, or an
    /// in-document "#anchor" to scroll to. Owned by DocumentViewController, which is the only
    /// object that knows the document's heading structure. Returns true when it handled the link.
    var linkActivationHandler: ((Any) -> Bool)?

    private func droppedMarkdownFileURL(from draggingInfo: NSDraggingInfo) -> URL? {
        guard let url = NSURL(from: draggingInfo.draggingPasteboard) as URL?,
              markdownFileExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    private func droppedImageFileURL(from info: NSDraggingInfo) -> URL? {
        guard let url = NSURL(from: info.draggingPasteboard) as URL? else { return nil }
        return imageFileExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }

    private func dropCharacterIndex(_ info: NSDraggingInfo) -> Int {
        let point = convert(info.draggingLocation, from: nil)
        guard let lm = layoutManager, let tc = textContainer else { return string.count }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = lm.glyphIndex(for: containerPoint, in: tc)
        return lm.characterIndexForGlyph(at: glyph)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedImageFileURL(from: sender) != nil || droppedMarkdownFileURL(from: sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let imageURL = droppedImageFileURL(from: sender) {
            shortcutDelegate?.markdownTextView(self, didReceiveDroppedImageFileAt: imageURL,
                                               atCharacterIndex: dropCharacterIndex(sender))
            return true
        }
        if let url = droppedMarkdownFileURL(from: sender) {
            shortcutDelegate?.markdownTextView(self, didReceiveDroppedMarkdownFileAt: url)
            return true
        }
        return super.performDragOperation(sender)
    }

    // Clicking a drawn task checkbox toggles it ([ ] <-> [x]) instead of moving the caret.
    // Clicking an unavailable-image placeholder requests folder access instead of moving the
    // caret -- checked before the checkbox/caret paths so it takes precedence for that run.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), openLink(at: point) {
            return
        }
        if let resolvedURL = unavailableImageURL(at: point) {
            shortcutDelegate?.markdownTextViewRequestImageAccess(self, resolvedURL: resolvedURL)
            return
        }
        if let characterIndex = taskCheckboxCharacterIndex(at: point), toggleTaskCheckbox(atCharacterIndex: characterIndex) {
            return
        }
        super.mouseDown(with: event)
    }

    /// The resolved URL of an inline image under `point` (view coordinates), but only when that
    /// image currently FAILS to load -- i.e. `point` is on the drawn "image unavailable"
    /// placeholder. A successfully-loading image returns nil here so its click falls through to
    /// the normal caret/reveal-source behavior. Same glyph/character hit-test pattern as
    /// `taskCheckboxCharacterIndex`.
    private func unavailableImageURL(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        var imageRange = NSRange()
        guard let info = textStorage.attribute(.marginalImage, at: characterIndex, effectiveRange: &imageRange) as? ImageDisplayInfo,
              ImageCache.shared.image(at: info.resolvedURL) == nil
        else { return nil }
        // `glyphIndex(for:in:)` maps to the NEAREST glyph, so a click in blank container space
        // beside a narrow line (or past its last glyph) can still resolve to this image's glyph
        // index -- reject it unless the point actually falls within the image run's own drawn
        // rect, same containment guard `openLink`/`taskCheckboxCharacterIndex` apply.
        let glyphRange = layoutManager.glyphRange(forCharacterRange: imageRange, actualCharacterRange: nil)
        let imageRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard imageRect.contains(containerPoint) else { return nil }
        return info.resolvedURL
    }

    /// ⌘-click opens the link under `point` in the default browser. A plain click deliberately
    /// still just moves the caret: this is an editor, and in an editable text view a bare click on
    /// a link has to remain a way to put the cursor inside it -- ⌘-click is the same gesture Xcode
    /// and VS Code use for exactly that reason. Returns false when there is no link under the
    /// point, so the normal click handling continues.
    private func openLink(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return false }

        // Reject points past the end of the line's glyphs, so clicking the empty space to the
        // right of a link-terminated line doesn't open it.
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.contains(point) else { return false }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return false }
        guard let value = textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) else { return false }

        return linkActivationHandler?(value) ?? false
    }

    /// The character index of a task-checkbox marker under `point` (view coordinates),
    /// or nil when the point isn't on a drawn checkbox.
    private func taskCheckboxCharacterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return nil }
        var markerRange = NSRange()
        guard textStorage.attribute(.marginalTaskCheckboxMarker, at: characterIndex, effectiveRange: &markerRange) != nil else { return nil }
        // The nearest-glyph hit test maps clicks from anywhere on the line; require the
        // click to actually fall on the checkbox's own drawn rect (plus a little slop).
        let glyphRange = layoutManager.glyphRange(forCharacterRange: markerRange, actualCharacterRange: nil)
        let markerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard markerRect.insetBy(dx: -3, dy: -3).contains(containerPoint) else { return nil }
        return characterIndex
    }

    /// Flips the "[ ]"/"[x]" source under the checkbox at `characterIndex`. Runs through
    /// shouldChangeText/didChangeText so the toggle is undoable and restyles normally.
    @discardableResult
    func toggleTaskCheckbox(atCharacterIndex characterIndex: Int) -> Bool {
        guard let textStorage else { return false }
        var markerRange = NSRange()
        guard characterIndex < textStorage.length,
              let isComplete = textStorage.attribute(.marginalTaskCheckboxMarker, at: characterIndex, effectiveRange: &markerRange) as? Bool
        else { return false }

        let markerText = (string as NSString).substring(with: markerRange)
        guard let bracket = markerText.firstIndex(of: "[") else { return false }
        let stateLocation = markerRange.location + markerText.distance(from: markerText.startIndex, to: bracket) + 1
        let stateRange = NSRange(location: stateLocation, length: 1)
        let replacement = isComplete ? " " : "x"

        guard shouldChangeText(in: stateRange, replacementString: replacement) else { return false }
        textStorage.replaceCharacters(in: stateRange, with: replacement)
        didChangeText()
        return true
    }

    // An image markup line is inflated (via line height) to hold the image card above its source
    // line, so its natural insertion-point rect is as tall as the whole card. Clamp the caret back
    // to a normal source-line height at the BOTTOM of the fragment (where the revealed `![](path)`
    // source sits), so editing an image's source never shows a card-tall caret.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: clampedImageInsertionRect(rect), color: color, turnedOn: flag)
    }

    func clampedImageInsertionRect(_ rect: NSRect) -> NSRect {
        guard let storage = textStorage, storage.length > 0 else { return rect }
        let loc = selectedRange().location
        // The caret can sit at the start/inside/just-after the image markup; check the character
        // it's on and the one just before it so an end-of-markup caret is clamped too.
        for idx in [loc, loc - 1] where idx >= 0 && idx < storage.length {
            if let info = storage.attribute(.marginalImage, at: idx, effectiveRange: nil) as? ImageDisplayInfo,
               rect.height > info.displaySize.height {
                let caretHeight = rect.height - info.displaySize.height
                return NSRect(x: rect.minX, y: rect.maxY - caretHeight, width: rect.width, height: caretHeight)
            }
        }
        return rect
    }

    /// One indentation level in Marginal is two spaces (matching the list parser's 2-spaces-per-
    /// level rule), so Tab/Shift-Tab indent and outdent by two — never a literal tab character
    /// (which would render at the ~8-column default and isn't recognized as list nesting).
    static let indentUnit = "  "

    // Tab indents every line the selection touches by one level; a bare caret indents its own
    // line. Line-based (not caret-based) so it reads as "indent this item", the behavior every
    // list-capable editor uses.
    override func insertTab(_ sender: Any?) {
        reindentSelectedLines(outdent: false)
    }

    // Shift-Tab outdents, removing up to one level (two leading spaces) from each touched line.
    override func insertBacktab(_ sender: Any?) {
        reindentSelectedLines(outdent: true)
    }

    private func reindentSelectedLines(outdent: Bool) {
        guard let textStorage else { return }
        let ns = string as NSString
        let sel = selectedRange()
        let lineRange = ns.lineRange(for: sel)
        var block = ns.substring(with: lineRange)
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { block.removeLast() }

        let lines = block.components(separatedBy: "\n")
        var removedPerLine: [Int] = []
        let newLines: [String] = lines.map { line in
            if outdent {
                var removed = 0
                var idx = line.startIndex
                while removed < Self.indentUnit.count, idx < line.endIndex, line[idx] == " " {
                    idx = line.index(after: idx); removed += 1
                }
                removedPerLine.append(removed)
                return String(line[idx...])
            } else {
                removedPerLine.append(-Self.indentUnit.count)   // negative == inserted
                return Self.indentUnit + line
            }
        }
        // A pure outdent that changes nothing (no line had leading spaces) shouldn't push an
        // empty undo step or fight the caret.
        if outdent, removedPerLine.allSatisfy({ $0 == 0 }) { return }

        var newBlock = newLines.joined(separator: "\n")
        if trailingNewline { newBlock += "\n" }

        guard shouldChangeText(in: lineRange, replacementString: newBlock) else { return }
        textStorage.replaceCharacters(in: lineRange, with: newBlock)
        didChangeText()

        // Keep the selection over the same logical text: shift its start by the first line's
        // delta, and its end by the total delta across every touched line.
        let firstDelta = -removedPerLine.first! // +2 when indenting, -removed when outdenting
        let totalDelta = -removedPerLine.reduce(0, +)
        let newLocation = max(lineRange.location, sel.location + firstDelta)
        let newEnd = max(newLocation, sel.location + sel.length + totalDelta)
        setSelectedRange(NSRange(location: newLocation, length: newEnd - newLocation))
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "=", "+":
                shortcutDelegate?.markdownTextViewIncreaseFontSize(self)
                return
            case "-":
                shortcutDelegate?.markdownTextViewDecreaseFontSize(self)
                return
            case "P":
                // charactersIgnoringModifiers honors Shift (only Option/Command/Control are
                // stripped), so Shift+P produces "P", never lowercase "p" — match the actual
                // character Shift produces rather than gating on the modifier flag directly.
                shortcutDelegate?.markdownTextViewToggleShowSource(self)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if shortcutDelegate?.markdownTextViewInsertPastedImage(self) == true { return }
        super.paste(sender)
    }

    /// File-URL extensions the paste path accepts, for BOTH validation (here) and handling
    /// (`DocumentViewController.imageDataFromPasteboard`). Deliberately narrower than the
    /// drag path's `imageFileExtensions`: tiff/bmp are omitted because their raw bytes would be
    /// mis-written as png by `normalizedImageExtension`, so the handler doesn't accept tiff/bmp
    /// *files* either -- keeping one shared list stops validation and handling from diverging.
    static let pasteImageFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    /// Cheap presence check (no image decode) used only to enable the Paste command for images.
    static func pasteboardContainsImage(_ pb: NSPasteboard) -> Bool {
        if pb.data(forType: .png) != nil { return true }
        if pb.data(forType: .tiff) != nil { return true }
        if let url = NSURL(from: pb) as URL? {
            return pasteImageFileExtensions.contains(url.pathExtension.lowercased())
        }
        return false
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        // NSTextView disables paste: for an image-only clipboard because importsGraphics is false.
        // Re-enable it when we can handle the image ourselves (our paste(_:) override inserts markdown).
        if item.action == #selector(NSText.paste(_:)), Self.pasteboardContainsImage(NSPasteboard.general) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
