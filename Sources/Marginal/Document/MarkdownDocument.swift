import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {

    var text: String = ""

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let viewController = DocumentViewController()
        viewController.document = self

        let window = NSWindow(contentViewController: viewController)
        window.setContentSize(NSSize(width: 700, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)

        viewController.loadInitialText(text)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
}
