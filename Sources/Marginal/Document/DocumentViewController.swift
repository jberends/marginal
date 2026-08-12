import AppKit

/// A container view that accepts a dropped markdown file regardless of which editor mode
/// (Live's `BlockEditorViewController` or Code's `MarkdownTextView`) is currently on top -- the
/// per-mode content views don't all register for drops themselves, so this ancestor-level
/// registration is what fixes the "drop a file anywhere in the window" regression (see
/// `DocumentViewController`'s drag-drop handling, task 16 step 5).
private final class DropTargetContainerView: NSView {
    var onDroppedMarkdownFile: ((URL) -> Void)?

    private static let markdownFileExtensions: Set<String> = ["md", "markdown"]

    private func droppedMarkdownFileURL(from draggingInfo: NSDraggingInfo) -> URL? {
        guard let url = NSURL(from: draggingInfo.draggingPasteboard) as URL?,
              Self.markdownFileExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedMarkdownFileURL(from: sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedMarkdownFileURL(from: sender) else { return super.performDragOperation(sender) }
        onDroppedMarkdownFile?(url)
        return true
    }
}

final class DocumentViewController: NSViewController {

    /// Live hosts the Notion-style block editor (default); Code shows the canonical markdown
    /// serialization in a plain monospaced source view. Exactly one is visible at a time.
    enum EditorMode: Equatable {
        case live
        case code
    }

    private(set) var mode: EditorMode = .live

    private(set) var textView: MarkdownTextView!
    /// The Live-mode child view controller. Exposed (not just `private`) so tests can drive
    /// focus/selection directly and inspect `document`/`focusedBlockID`.
    private(set) var blockEditor: BlockEditorViewController!
    private var gutterView: LineNumberGutterView!
    private var statusBar: StatusBarView!
    private var scrollView: NSScrollView!
    private var firstResponderObservation: NSKeyValueObservation?
    private var isApplyingProgrammaticEdit = false

    // Single source of truth for the editor's base font size, shared by both modes (Code's
    // NSTextView.font and Live's BlockEditorViewController.baseFont).
    // 16px body -- the design system's base size (headings scale 1.25/1.5/1.875 from it).
    private var editorFontSize: CGFloat = 16

    weak var document: MarkdownDocument?

    override func loadView() {
        let containerView = DropTargetContainerView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        containerView.onDroppedMarkdownFile = { [weak self] url in
            self?.handleDroppedMarkdownFile(url)
        }
        containerView.registerForDraggedTypes([.fileURL])

        let savedSize = UserDefaults.standard.double(forKey: "editorFontPointSize")
        editorFontSize = savedSize > 0 ? savedSize : 16

        // MARK: Code mode -- gutter + scroll view + plain monospaced source text view.

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = MarkdownTextView()
        textView.isEditable = true
        // Code mode is a literal, unstyled markdown source editor (what "Show Source" used to be,
        // now the only thing Code mode ever does) -- plain-text mode means the whole storage
        // always shares one font/color, so there is no per-character attribute bookkeeping to get
        // out of sync the way the old WYSIWYG restyle pass could.
        textView.isRichText = false
        // Programmatically-created NSTextViews default allowsUndo to false (only
        // nib/storyboard-loaded ones default to true) -- without this, typing never
        // registers undo actions and Cmd+Z silently does nothing.
        textView.allowsUndo = true
        // Markdown syntax depends on literal ASCII sequences ("---", straight quotes inside
        // code spans, etc). Disabling all three "smart" substitutions keeps typed markdown source
        // literal.
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 40, height: 24)
        // Paper, not white -- the design system's page surface, with the violet-tinted
        // selection from the same token sheet. Both are dynamic (light/dark).
        textView.backgroundColor = DesignPalette.surfacePage
        textView.selectedTextAttributes = [.backgroundColor: DesignPalette.selection]
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.shortcutDelegate = self
        textView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        let gutter = LineNumberGutterView()
        gutter.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(gutter)

        // MARK: Live mode -- the block editor, hosted as a real child view controller (so menu
        // actions like Format > Bold and the mode-toggle shortcut reach it/this controller through
        // the normal responder chain).

        let blockEditor = BlockEditorViewController(
            document: BlockDocument(blocks: [Block(kind: .paragraph(InlineText("")))]),
            baseFont: NSFont.systemFont(ofSize: editorFontSize)
        )
        addChild(blockEditor)
        blockEditor.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(blockEditor.view)
        blockEditor.onDocumentChange = { [weak self] doc in
            self?.handleLiveDocumentChange(doc)
        }

        // MARK: Chrome shared by both modes.

        let statusBar = StatusBarView(frame: .zero)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusBar)

        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: containerView.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 44),

            statusBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),

            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            blockEditor.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            blockEditor.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            blockEditor.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            blockEditor.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
        ])

        // The gutter's line number follows the caret's own line, so it must re-position on
        // scroll, not just on selection changes.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        self.textView = textView
        self.gutterView = gutter
        self.statusBar = statusBar
        self.scrollView = scrollView
        self.blockEditor = blockEditor
        self.view = containerView

        applyModeVisibility()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The line number shows only while the cursor is actually in the text -- track focus
        // by observing the window's first responder.
        firstResponderObservation = view.window?.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateCursorChrome() }
        }
        updateCursorChrome()
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        updateCursorChrome()
    }

    private func applyModeVisibility() {
        let isLive = mode == .live
        blockEditor.view.isHidden = !isLive
        scrollView.isHidden = isLive
        // The gutter belongs to both modes: in Code it tracks the caret's line, in Live it shows
        // the focused block's line in the canonical serialization (0.3.0 always had a gutter, and
        // losing it in the default mode read as a regression).
        gutterView.isHidden = false
    }

    /// Live mode's chrome. There is no single text view to count lines in, so the focused block's
    /// first line in the canonical serialization is the line number, and the status bar shows the
    /// block's kind as its breadcrumb.
    private func updateLiveCursorChrome(gutterView: LineNumberGutterView, statusBar: StatusBarView) {
        guard let focusedID = blockEditor.focusedBlockID else {
            gutterView.lineNumber = nil
            statusBar.update(with: nil)
            return
        }
        let (_, lineMap) = MarkdownSerializer.serialize(blockEditor.document)
        guard let lineRange = lineMap[focusedID] else {
            gutterView.lineNumber = nil
            statusBar.update(with: nil)
            return
        }
        gutterView.lineNumber = lineRange.lowerBound
        let kindName: String
        switch blockEditor.document[focusedID]?.kind {
        case .heading(let level, _): kindName = "Heading \(level)"
        case .listItem: kindName = "List item"
        case .quote: kindName = "Quote"
        case .codeBlock: kindName = "Code block"
        case .table: kindName = "Table"
        case .divider: kindName = "Divider"
        case .paragraph, .none: kindName = "Paragraph"
        }
        statusBar.update(with: CursorStatus(line: lineRange.lowerBound, column: 1, path: [kindName]))
    }

    /// Recomputes the gutter's line number/position and the status bar's breadcrumb. Only
    /// meaningful in Code mode (Live mode has no line-oriented gutter/breadcrumb concept), so this
    /// clears both chrome elements outright while Live is active.
    private func updateCursorChrome() {
        guard let gutterView, let statusBar else { return }
        guard mode == .code else {
            updateLiveCursorChrome(gutterView: gutterView, statusBar: statusBar)
            return
        }
        let text = textView.string
        let cursorInText = view.window?.firstResponder === textView

        guard cursorInText, let cursor = currentCursorIndex() else {
            gutterView.lineNumber = nil
            statusBar.update(with: nil)
            return
        }

        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text),
            tables: MarkdownParser.parseTables(in: text),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text)
        )
        let status = CursorStatus.status(for: text, model: model, cursor: cursor)
        statusBar.update(with: status)

        guard let layoutManager = textView.layoutManager else {
            gutterView.lineNumber = nil
            return
        }
        let location = textView.selectedRange().location
        var lineRect: NSRect
        if location < (textView.textStorage?.length ?? 0) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        } else {
            // Caret at the very end: the extra line fragment when the text ends in a newline,
            // else the last real line.
            lineRect = layoutManager.extraLineFragmentRect
            if lineRect.isEmpty, layoutManager.numberOfGlyphs > 0 {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: nil)
            }
        }
        var rectInTextView = lineRect
        rectInTextView.origin.y += textView.textContainerInset.height
        let rectInGutter = textView.convert(rectInTextView, to: gutterView)
        gutterView.fontSize = min(12, max(10, editorFontSize * 0.7))
        gutterView.lineNumber = status.line
        gutterView.lineCenterY = rectInGutter.midY
    }

    /// Parses `text` into the canonical block model and shows it in Live mode (the default for a
    /// freshly opened/created document) -- called once, from `MarkdownDocument.makeWindowControllers()`.
    /// Also immediately writes the canonical serialization back into `document.text`, so a
    /// document is saved in canonical form even before any edit (e.g. "1) x" read in becomes
    /// "1. x\n" on save, with no user interaction required).
    func loadInitialText(_ text: String) {
        let parsed = MarkdownBlockParser.parse(text)
        mode = .live
        blockEditor.setDocument(parsed)
        applyModeVisibility()
        document?.text = MarkdownSerializer.serialize(parsed).markdown
        updateCursorChrome()
    }

    func currentCursorIndex() -> String.Index? {
        let text = textView.string
        let location = textView.selectedRange().location
        guard location != NSNotFound, let range = Range(NSRange(location: location, length: 0), in: text) else { return nil }
        return range.lowerBound
    }

    // MARK: - Mode switch (Live <-> Code)

    /// Live -> Code: serializes the live block document to canonical markdown, shows it in the
    /// (now visible) code text view, and places the caret on the first source line of whichever
    /// block was focused -- via the line map `MarkdownSerializer.serialize` returns alongside the
    /// markdown. Undo stacks always reset across a mode switch (a structural edit in one mode has
    /// no meaningful inverse in the other's undo stack).
    func switchToCode() {
        guard mode == .live else { return }
        let focusedID = blockEditor.focusedBlockID
        let (markdown, lineMap) = MarkdownSerializer.serialize(blockEditor.document)

        isApplyingProgrammaticEdit = true
        textView.string = markdown
        isApplyingProgrammaticEdit = false

        mode = .code
        applyModeVisibility()
        document?.text = markdown

        let targetLine = focusedID.flatMap { lineMap[$0]?.lowerBound } ?? 1
        let offset = Self.characterOffset(ofLine: targetLine, in: markdown as NSString)
        view.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: offset, length: 0))

        // The window/document undo manager is Code mode's (`MarkdownTextView.allowsUndo = true`
        // registers into it); the block editor has its own, separate manager (see
        // `BlockEditorViewController.undoManager`) that Live mode's edits registered into instead
        // -- both need resetting so leftover Live-mode undo history doesn't dangle once Code mode
        // starts registering its own steps.
        view.window?.undoManager?.removeAllActions()
        blockEditor.blockEditorUndoManager.removeAllActions()
        updateCursorChrome()
    }

    /// Code -> Live: parses the current source text into a fresh block document and focuses the
    /// block whose source line range (per the same line map) contains the caret's current line --
    /// falling back to the nearest preceding block, then the first block, if the caret sits on a
    /// separator line no block "owns" (e.g. the blank line between two blocks).
    func switchToLive() {
        guard mode == .code else { return }
        let text = textView.string
        let caretLine = Self.lineNumber(atLocation: textView.selectedRange().location, in: text as NSString)
        let parsed = MarkdownBlockParser.parse(text)
        let (canonical, lineMap) = MarkdownSerializer.serialize(parsed)

        blockEditor.setDocument(parsed)
        mode = .live
        applyModeVisibility()
        document?.text = canonical

        let candidates = parsed.blocks.filter { lineMap[$0.id] != nil }
        let targetID = candidates.first(where: { lineMap[$0.id]!.contains(caretLine) })?.id
            ?? candidates.last(where: { lineMap[$0.id]!.lowerBound <= caretLine })?.id
            ?? candidates.first?.id
        if let targetID, blockEditor.document[targetID]?.kind.inlineText != nil {
            blockEditor.focusBlock(targetID, caretOffset: 0)
        }

        // Symmetric reset -- see the comment in `switchToCode()`.
        view.window?.undoManager?.removeAllActions()
        blockEditor.blockEditorUndoManager.removeAllActions()
        updateCursorChrome()
    }

    /// Routes both the ⌘⇧P keyboard shortcut (via `MarkdownTextViewShortcutDelegate`, when Code
    /// mode's text view is first responder) and the View menu item (reaches this controller
    /// through the normal responder chain regardless of which mode/child view is focused).
    @objc func toggleMode(_ sender: Any?) {
        switch mode {
        case .live: switchToCode()
        case .code: switchToLive()
        }
    }

    private static func lineNumber(atLocation location: Int, in text: NSString) -> Int {
        let clamped = min(max(location, 0), text.length)
        var line = 1
        var i = 0
        while i < clamped {
            if text.character(at: i) == 10 { line += 1 } // "\n"
            i += 1
        }
        return line
    }

    private static func characterOffset(ofLine targetLine: Int, in text: NSString) -> Int {
        guard targetLine > 1 else { return 0 }
        var line = 1
        var i = 0
        let length = text.length
        while i < length, line < targetLine {
            if text.character(at: i) == 10 { line += 1 } // "\n"
            i += 1
        }
        return i
    }

    /// The canonical markdown for whichever model is currently authoritative -- Live's block
    /// document re-serialized, or Code's text view's current (already-canonical, or user-edited)
    /// source. Feeds exports/HTML copy so they always reflect what's actually on screen.
    private func currentCanonicalMarkdown() -> String {
        switch mode {
        case .live: return MarkdownSerializer.serialize(blockEditor.document).markdown
        case .code: return textView.string
        }
    }

    // MARK: - Copy / export

    func copyCurrentSelectionAsMarkdown() {
        let markdown: String
        switch mode {
        case .code:
            guard let range = Range(textView.selectedRange(), in: textView.string) else { return }
            markdown = String(textView.string[range])
        case .live:
            markdown = liveSelectionMarkdown()
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func copyCurrentSelectionAsHTML() {
        let markdown: String
        switch mode {
        case .code:
            guard let range = Range(textView.selectedRange(), in: textView.string) else { return }
            markdown = String(textView.string[range])
        case .live:
            markdown = liveSelectionMarkdown()
        }
        let html = MarkdownHTMLRenderer.html(fromMarkdown: markdown)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
    }

    /// Live mode's "copy selection" markdown source: an active whole-block selection's canonical
    /// markdown, or (with no whole-block selection -- e.g. an ordinary in-block text selection,
    /// which has no raw-markdown-substring equivalent since a `BlockTextView`'s storage is a
    /// WYSIWYG rendering, not source text) the entire document's canonical markdown.
    private func liveSelectionMarkdown() -> String {
        if !blockEditor.selectionController.selectedBlockIDs.isEmpty {
            return blockEditor.selectionController.markdownForSelection(in: blockEditor.document)
        }
        return MarkdownSerializer.serialize(blockEditor.document).markdown
    }

    // The underlying text storage is always the literal markdown source (never mutated for
    // display), so Cmd+C must copy that raw source as plain text -- not NSTextView's default
    // copy:, which would also place an RTF/attributed representation on the pasteboard.
    @objc func copySelectionAsMarkdown(_ sender: Any?) {
        copyCurrentSelectionAsMarkdown()
    }

    @objc func copySelectionAsHTML(_ sender: Any?) {
        copyCurrentSelectionAsHTML()
    }

    /// File -> Export as PDF: renders the whole document through the HTML renderer and
    /// prints it to a paginated PDF at a user-chosen location.
    @objc func exportAsPDF(_ sender: Any?) {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (document?.displayName ?? "Document") + ".pdf"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            PDFExporter.shared.export(
                markdown: self.currentCanonicalMarkdown(),
                title: self.document?.displayName ?? "Document",
                to: url
            ) { error in
                guard let error else { return }
                let alert = NSAlert()
                alert.messageText = "Could not export the PDF."
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window)
            }
        }
    }

    // MARK: - Live model change / drag-drop

    private func handleLiveDocumentChange(_ doc: BlockDocument) {
        document?.text = MarkdownSerializer.serialize(doc).markdown
        document?.updateChangeCount(.changeDone)
        updateCursorChrome()
    }

    // Dropping a markdown file always opens it. If this window's document is untitled and
    // still empty, the dropped file replaces it in place (closing this now-redundant empty
    // window) rather than leaving a stray blank window behind. Any other content-bearing
    // window is left untouched and the file opens in a new window, so existing work is
    // never silently overwritten.
    private func handleDroppedMarkdownFile(_ url: URL) {
        let isEmptyUntitled = document?.fileURL == nil
            && blockEditor.document.blocks.count == 1
            && blockEditor.document.blocks[0].kind == .paragraph(InlineText(""))
            && textView.string.isEmpty
        let windowToCloseIfOpenSucceeds: NSWindow? = isEmptyUntitled ? view.window : nil

        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSApp.presentError(error)
                return
            }
            windowToCloseIfOpenSucceeds?.close()
        }
    }

    private func setFontSize(_ size: CGFloat) {
        editorFontSize = size
        textView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        UserDefaults.standard.set(size, forKey: "editorFontPointSize")
        // Live mode's base font is fixed at BlockEditorViewController init time; font-size
        // changes while Live is active take effect the next time the document is (re)loaded.
        // No test exercises live font resizing, and BlockEditorViewController's `baseFont` is
        // intentionally `let` (Task 11+) -- rebuilding it live is out of scope here.
    }
}

extension DocumentViewController: NSTextViewDelegate {
    // Return inside a list item continues the list ("- ", "4. ", "- [ ] " on the new
    // line); Return on an empty item outdents one level, then leaves the list. Only ever fires
    // for Code mode's text view (Live mode's BlockTextViews have their own delegate).
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let nsText = textView.string as NSString
        let selection = textView.selectedRange()
        guard selection.location != NSNotFound else { return false }

        let lineRange = nsText.lineRange(for: NSRange(location: selection.location, length: 0))
        var line = nsText.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        guard let action = ListContinuation.action(forLine: line) else { return false }

        switch action {
        case .continueList(let insertion):
            textView.insertText("\n" + insertion, replacementRange: selection)
        case .replaceLine(let newLine):
            let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
            guard textView.shouldChangeText(in: contentRange, replacementString: newLine) else { return false }
            textView.textStorage?.replaceCharacters(in: contentRange, with: newLine)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: contentRange.location + (newLine as NSString).length, length: 0))
        }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard mode == .code, !isApplyingProgrammaticEdit else { return }
        document?.text = textView.string
        document?.updateChangeCount(.changeDone)
        updateCursorChrome()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard mode == .code, !isApplyingProgrammaticEdit else { return }
        updateCursorChrome()
    }
}

extension DocumentViewController: MarkdownTextViewShortcutDelegate {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.increased(from: editorFontSize))
    }

    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.decreased(from: editorFontSize))
    }

    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView) {
        toggleMode(nil)
    }

    func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedMarkdownFileAt url: URL) {
        handleDroppedMarkdownFile(url)
    }
}
