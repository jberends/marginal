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
            vc.prepareForSave(to: url, now: Date(), copyLinkedImages: copyLinkedImagesCheckbox?.state == .on)
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

    // New documents propose "Untitled.md" rather than AppKit's UTI-derived "Untitled.markdown" --
    // .md is the extension users expect and the one every other markdown tool defaults to.
    override func fileNameExtension(forType typeName: String,
                                     saveOperation: NSDocument.SaveOperationType) -> String? {
        "md"
    }

    // Held only while a Save panel is on screen, so `save(to:…)` can read whether the user ticked
    // "also copy linked images" (see prepareSavePanel). Nil when no such panel is up.
    private weak var copyLinkedImagesCheckbox: NSButton?

    // fileNameExtension(forType:) alone is NOT enough for the *visible* Save-As proposal: the
    // Markdown UTI (net.daringfireball.markdown) is declared by the system, and its system
    // preferred filename extension is ".markdown" (md is last in its tag list), so NSSavePanel
    // seeds "Untitled.markdown". Rewrite the name field here to end in ".md" -- the one control
    // that governs what the user actually sees -- while still accepting ".markdown" if typed.
    //
    // When the document references externally-linked images (dragged in from elsewhere on disk),
    // also add an accessory checkbox offering to copy them into the document's "<name>.assets/"
    // folder on save, so the document becomes self-contained. Pasted images always relocate there
    // regardless, so the checkbox is only offered -- and only meaningful -- when there is an
    // external image to copy.
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.nameFieldStringValue = Self.proposedMarkdownFileName(from: savePanel.nameFieldStringValue)

        copyLinkedImagesCheckbox = nil
        if let vc = windowControllers.first?.contentViewController as? DocumentViewController,
           vc.hasExternallyLinkedImages() {
            let checkbox = NSButton(checkboxWithTitle: "Copy linked images into the document’s .assets folder",
                                    target: nil, action: nil)
            checkbox.state = .off
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 34))
            accessory.addSubview(checkbox)
            NSLayoutConstraint.activate([
                checkbox.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: 20),
                checkbox.trailingAnchor.constraint(lessThanOrEqualTo: accessory.trailingAnchor, constant: -20),
                checkbox.centerYAnchor.constraint(equalTo: accessory.centerYAnchor)
            ])
            savePanel.accessoryView = accessory
            copyLinkedImagesCheckbox = checkbox
        }

        return super.prepareSavePanel(savePanel)
    }

    /// Normalizes a Save-panel filename to end in `.md`: replaces a trailing `.md`/`.markdown`
    /// (any case) with `.md`, supplies "Untitled" when empty, and otherwise appends `.md` only
    /// when the name carries no extension at all. Suffix-based (not `NSString.pathExtension`) so a
    /// dotted/spaced base like "v1.2 draft.markdown" normalizes correctly.
    static func proposedMarkdownFileName(from current: String) -> String {
        let name = current.isEmpty ? "Untitled" : current
        let lower = name.lowercased()
        for suffix in [".markdown", ".md"] where lower.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count)) + ".md"
        }
        // No markdown extension: append .md unless the name already has some other extension.
        return (name as NSString).pathExtension.isEmpty ? name + ".md" : name
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
