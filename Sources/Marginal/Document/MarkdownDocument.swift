import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {

    // NSDocument calls read(from:ofType:) / data(ofType:) off the main actor (background
    // file reads and asynchronous autosave), so this can't be main-actor-isolated storage.
    // NSDocument itself serializes those calls against each other and against UI access
    // (it snapshots state before an async save), so unsynchronized access is safe here.
    nonisolated(unsafe) var text: String = ""

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let viewController = DocumentViewController()
        viewController.document = self

        let window = NSWindow(contentViewController: viewController)
        window.setContentSize(NSSize(width: 700, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        // Documents group into one window with the native macOS tab bar (the same tab-bar
        // pattern iTerm2 presents): opening a second file joins the existing window as a tab,
        // and the bar only appears once more than one document is open. The shared identifier
        // keeps document windows tabbing together (and keeps the Preferences window out).
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MarginalDocumentWindow"

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
        // UTF-8 only, deliberately. Marginal now opens .txt as well as .md, so falling back to
        // encoding sniffing for older Latin-1 files is tempting -- but Latin-1 decodes *any* byte
        // sequence without loss, so a sniffing fallback cannot tell a Latin-1 document from a
        // binary file that happens to be named .txt. It would open the latter as mojibake instead
        // of reporting it as unreadable. Refusing is the better failure.
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
}
