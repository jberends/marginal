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
        let inset = textContainerInset
        let p = NSPoint(x: point.x - inset.width, y: point.y - inset.height)
        let glyph = lm.glyphIndex(for: p, in: tc)
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
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), openLink(at: point) {
            return
        }
        if let characterIndex = taskCheckboxCharacterIndex(at: point), toggleTaskCheckbox(atCharacterIndex: characterIndex) {
            return
        }
        super.mouseDown(with: event)
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
}
