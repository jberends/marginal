import AppKit

@MainActor
protocol MarkdownTextViewShortcutDelegate: AnyObject {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewCopyAsMarkdown(_ textView: MarkdownTextView)
    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView)
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
            case "c" where event.modifierFlags.contains(.option):
                shortcutDelegate?.markdownTextViewCopyAsMarkdown(self)
                return
            case "p" where event.modifierFlags.contains(.shift):
                shortcutDelegate?.markdownTextViewToggleShowSource(self)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}
