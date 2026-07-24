import AppKit

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
