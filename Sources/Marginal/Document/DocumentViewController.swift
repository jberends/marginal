import AppKit

final class DocumentViewController: NSViewController {
    weak var document: MarkdownDocument?
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
    }
    func loadInitialText(_ text: String) {}
}
