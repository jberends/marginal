import AppKit

/// A boolean (task-complete) attribute marking the "[ ] "/"[x] " range of a rendered task-list
/// checkbox, so a click there can flip it (`MarkdownTextView.toggleTaskCheckbox`) instead of
/// moving the caret. Formerly set by the old `MarkdownStyler` WYSIWYG pass; that pass is retired
/// (Code mode is now a plain monospaced source view that never sets this attribute), but the key
/// and the click-to-toggle mechanics stay here since `MarkdownTextViewTests` still exercises them
/// directly against a hand-built attributed string.
extension NSAttributedString.Key {
    static let marginalTaskCheckboxMarker = NSAttributedString.Key("marginalTaskCheckboxMarker")
}

@MainActor
protocol MarkdownTextViewShortcutDelegate: AnyObject {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedMarkdownFileAt url: URL)
}

private let markdownFileExtensions: Set<String> = ["md", "markdown"]

final class MarkdownTextView: NSTextView {

    weak var shortcutDelegate: MarkdownTextViewShortcutDelegate?

    private func droppedMarkdownFileURL(from draggingInfo: NSDraggingInfo) -> URL? {
        guard let url = NSURL(from: draggingInfo.draggingPasteboard) as URL?,
              markdownFileExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedMarkdownFileURL(from: sender) != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedMarkdownFileURL(from: sender) {
            shortcutDelegate?.markdownTextView(self, didReceiveDroppedMarkdownFileAt: url)
            return true
        }
        return super.performDragOperation(sender)
    }

    // Clicking a drawn task checkbox toggles it ([ ] <-> [x]) instead of moving the caret.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let characterIndex = taskCheckboxCharacterIndex(at: point), toggleTaskCheckbox(atCharacterIndex: characterIndex) {
            return
        }
        super.mouseDown(with: event)
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
}
