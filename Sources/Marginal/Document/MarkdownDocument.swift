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

    // The funnel used by Save, Save As, and autosave-as -- it runs on the main actor and knows
    // the target URL before any bytes are written, so this is where managed temp images get
    // relocated into <doc>.assets/ and their paths rewritten to relative before data(ofType:)
    // serializes `text`. Gated to genuine user saves only (see shouldRelocateImages): autosaving
    // a draft document would otherwise relocate its temp images into the hidden Autosave
    // Information folder and rewrite their paths before the user ever picks a real save location,
    // stranding them there when the real save finally happens.
    override func save(
        to url: URL, ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if Self.shouldRelocateImages(for: saveOperation),
           let vc = windowControllers.first?.contentViewController as? DocumentViewController {
            vc.prepareForSave(to: url, now: Date())
        }
        super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
    }

    /// Relocate managed temp images only on a genuine user save, never on autosave -- autosaving
    /// a draft would move temp images into the hidden Autosave Information folder and rewrite
    /// their paths before the user picks a real save location.
    static func shouldRelocateImages(for op: NSDocument.SaveOperationType) -> Bool {
        switch op {
        case .saveOperation, .saveAsOperation, .saveToOperation: return true
        case .autosaveInPlaceOperation, .autosaveElsewhereOperation, .autosaveAsOperation: return false
        @unknown default: return false
        }
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
