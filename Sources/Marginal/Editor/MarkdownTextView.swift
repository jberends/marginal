import AppKit

@MainActor
protocol MarkdownTextViewShortcutDelegate: AnyObject {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView)
}

final class MarkdownTextView: NSTextView {

    weak var shortcutDelegate: MarkdownTextViewShortcutDelegate?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "=":
                shortcutDelegate?.markdownTextViewIncreaseFontSize(self)
                return
            case "-":
                shortcutDelegate?.markdownTextViewDecreaseFontSize(self)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}
