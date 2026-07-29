import AppKit

final class DocumentViewController: NSViewController {

    private(set) var textView: MarkdownTextView!
    private var gutterView: LineNumberGutterView!
    private var statusBar: StatusBarView!
    private var latestModel: MarkdownDocumentModel?
    private var firstResponderObservation: NSKeyValueObservation?
    private var isApplyingProgrammaticEdit = false

    private var previewWebView: PreviewWebView?
    private var scrollView: NSScrollView!

    /// Bumped on every `setEditorMode` call so an in-flight `topmostVisibleSourceLine` query
    /// from an earlier switch can recognize it's been superseded and discard its answer.
    private var modeSwitchGeneration = 0

    /// Where the mode controller reads and persists the mode. Tests point this at a throwaway
    /// suite so a developer's own last-used mode can never change what a test observes; it must
    /// be set before `loadInitialText`, which is what first touches `modeController`.
    var editorModeDefaults: UserDefaults = .standard
    private lazy var modeController = EditorModeController(host: self, defaults: editorModeDefaults)

    /// The active rendering mode.
    var editorMode: EditorMode { modeController.mode }

    var previewWebViewForTesting: PreviewWebView? { previewWebView }
    var gutterViewForTesting: NSView { gutterView }
    var modeSwitchGenerationForTesting: Int { modeSwitchGeneration }

    // Single source of truth for the editor's base font size. NSTextView's `font` getter
    // (in rich-text mode) returns whatever attribute sits at the current selection/cursor —
    // which restyle() may have set to the near-invisible hidden-delimiter size (see
    // MarkdownStyler.hiddenDelimiterFontSize) — so it must never be read back as "the base
    // font"; this property is the only thing restyle()/renderCode()/font-size adjustment
    // consult or mutate.
    // 16px body -- the design system's base size (headings scale 1.25/1.5/1.875 from it).
    private var editorFontSize: CGFloat = 16

    weak var document: MarkdownDocument?

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = MarkdownTextView()
        textView.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
        textView.isEditable = true
        textView.isRichText = true
        // Programmatically-created NSTextViews default allowsUndo to false (only
        // nib/storyboard-loaded ones default to true) -- without this, typing never
        // registers undo actions and Cmd+Z silently does nothing.
        textView.allowsUndo = true
        // Markdown syntax depends on literal ASCII sequences ("---", straight quotes inside
        // code spans, etc). Discovered via Task 7's manual GUI verification: with these left at
        // their AppKit defaults, typing "---" was silently substituted into a single em-dash "—"
        // by Smart Dashes before the parser ever saw the text, so a horizontal rule could never
        // be recognized from real typing (only from pre-existing/pasted text). Disabling all
        // three "smart" substitutions keeps typed markdown source literal.
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: 16)
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
        let savedSize = UserDefaults.standard.double(forKey: "editorFontPointSize")
        editorFontSize = savedSize > 0 ? savedSize : 16
        textView.font = NSFont.systemFont(ofSize: editorFontSize)

        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        // Left sidebar (faint current-line number) and bottom status bar (cursor context).
        let gutter = LineNumberGutterView()
        gutter.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(gutter)

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
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
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

        self.scrollView = scrollView
        self.textView = textView
        self.gutterView = gutter
        self.statusBar = statusBar
        self.view = containerView
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

    /// Recomputes the gutter's line number/position and the status bar's breadcrumb.
    private func updateCursorChrome() {
        guard let gutterView, let statusBar else { return }
        guard editorMode != .preview else { return }
        let text = textView.string
        let cursorInText = view.window?.firstResponder === textView

        guard cursorInText, let cursor = currentCursorIndex() else {
            gutterView.lineNumber = nil
            statusBar.update(with: nil)
            return
        }

        let model = latestModel ?? MarkdownDocumentModel()
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

    func loadInitialText(_ text: String) {
        textView.string = text
        modeController.activate()
    }

    func currentCursorIndex() -> String.Index? {
        let text = textView.string
        let location = textView.selectedRange().location
        guard location != NSNotFound, let range = Range(NSRange(location: location, length: 0), in: text) else { return nil }
        return range.lowerBound
    }

    func copyCurrentSelectionAsMarkdown() {
        guard let range = Range(textView.selectedRange(), in: textView.string) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(textView.string[range]), forType: .string)
    }

    func copyCurrentSelectionAsHTML() {
        guard let range = Range(textView.selectedRange(), in: textView.string) else { return }
        let html = MarkdownHTMLRenderer.html(fromMarkdown: String(textView.string[range]))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
    }

    // The underlying text storage is always the literal markdown source (never mutated for
    // display), so Cmd+C must copy that raw source as plain text -- not NSTextView's default
    // copy:, which would also place an RTF/attributed representation on the pasteboard (carrying
    // WYSIWYG font/color runs, including near-invisible hidden-delimiter and transparent-bullet
    // runs) that a rich-text-aware paste target would use instead of the plain string.
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
                markdown: self.textView.string,
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

    /// Switches rendering mode. Preserves reading position across the switch: leaving an editing
    /// surface scrolls Preview to the caret's block, and leaving Preview puts the caret on the
    /// topmost visible block's first line.
    func setEditorMode(_ mode: EditorMode) {
        guard mode != editorMode else { return }

        // Distinguishes this switch from a later one that might complete first: the
        // topmost-line query below is an asynchronous JS round-trip, and a stale answer must
        // never move the caret after the user has already switched modes again (e.g. Preview ->
        // Live -> Preview faster than the first query resolves).
        modeSwitchGeneration += 1
        let generation = modeSwitchGeneration

        if editorMode == .preview, let previewWebView {
            // Capture the reading position before the web view goes away. The JS round-trip is
            // asynchronous, so the caret move lands just after the switch — which is fine, the
            // text view is already showing by then.
            previewWebView.topmostVisibleSourceLine { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self, self.modeSwitchGeneration == generation, let line else { return }
                    self.moveCaretToLine(line)
                }
            }
        }

        let caretLineBeforeSwitch = mode == .preview ? currentCaretLine() : nil
        modeController.setMode(mode)
        if let caretLineBeforeSwitch {
            // Must be requested, not performed: setMode -> renderPreview -> load() kicks off an
            // asynchronous loadHTMLString, so there is no DOM to scroll yet. PreviewWebView
            // holds the request and applies it when navigation finishes.
            previewWebView?.requestScrollToSourceLine(caretLineBeforeSwitch)
        }
    }

    /// View-menu action. `sender.tag` is the mode's index in `EditorMode.allCases`.
    @objc func selectEditorMode(_ sender: NSMenuItem) {
        guard EditorMode.allCases.indices.contains(sender.tag) else { return }
        setEditorMode(EditorMode.allCases[sender.tag])
    }

    /// The 1-based line the caret sits on, via the same status computation the status bar uses.
    private func currentCaretLine() -> Int {
        guard let cursor = currentCursorIndex() else { return 1 }
        let model = latestModel ?? MarkdownDocumentModel()
        return CursorStatus.status(for: textView.string, model: model, cursor: cursor).line
    }

    /// Puts the caret at the start of 1-based `line` and scrolls it into view.
    private func moveCaretToLine(_ line: Int) {
        let nsText = textView.string as NSString
        var location = 0
        var currentLine = 1
        while currentLine < line, location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            currentLine += 1
        }
        let clamped = min(location, nsText.length)
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
        textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }

    private func parsedModel(for text: String) -> MarkdownDocumentModel {
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
        latestModel = model
        return model
    }

    /// Applies a fully-styled attributed string to the text storage in place, preserving the
    /// selection. Shared by Live and Code rendering — only the string differs.
    private func applyRendering(_ attributed: NSAttributedString) {
        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticEdit = true
        textView.textStorage?.beginEditing()
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            textView.textStorage?.setAttributes(attrs, range: range)
        }
        textView.textStorage?.endEditing()
        textView.setSelectedRange(selectedRange)
        isApplyingProgrammaticEdit = false
        // Horizontal rules are the first feature where revealing/hiding a marker changes an
        // entire line's font size (0.1pt <-> baseFont), which changes that line's height and
        // therefore shifts every line below it. NSTextView's automatic display invalidation
        // after the in-place setAttributes calls above redraws only the stale (pre-shift)
        // region, leaving lines below a revealed/hidden rule visually blank until some other
        // event forces a full redraw. The layout itself is always correct; only the drawn
        // pixels go stale. Forcing a full-view redraw after every render fixes it.
        textView.needsDisplay = true
    }

    private func restyle(cursorLocation: String.Index?) {
        let text = textView.string
        let model = parsedModel(for: text)
        applyRendering(
            MarkdownStyler.attributedString(
                for: text,
                model: model,
                baseFont: NSFont.systemFont(ofSize: editorFontSize),
                cursorLocation: cursorLocation
            )
        )
    }
}

extension DocumentViewController: EditorModeHost {

    func renderCode() {
        let text = textView.string
        let model = parsedModel(for: text)
        applyRendering(
            MarkdownStyler.codeSourceAttributedString(
                for: text,
                model: model,
                font: NSFont.systemFont(ofSize: editorFontSize)
            )
        )
    }

    func renderLive() {
        restyle(cursorLocation: currentCursorIndex())
    }

    func renderPreview() {
        let webView = previewWebView ?? makePreviewWebView()
        webView.load(
            markdown: textView.string,
            title: document?.displayName ?? "Document",
            fontSize: editorFontSize,
            appearance: view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        )
    }

    func applyChrome(for mode: EditorMode) {
        let isPreview = mode == .preview
        if isPreview, previewWebView == nil {
            _ = makePreviewWebView()
        }
        previewWebView?.isHidden = !isPreview
        scrollView.isHidden = isPreview
        gutterView.isHidden = isPreview
        // NOTE: the status bar's Preview readout (word count / reading time) and its segmented
        // control are wired in Task 10, which is where those StatusBarView members are added.
        // Do not reference them here — they do not exist yet and this task must compile.
        if isPreview {
            // Preview is read-only, so the text view must not stay first responder. AppKit does
            // resign it automatically when scrollView.isHidden above takes effect (verified: the
            // window falls back to being its own first responder) -- but that fallback leaves
            // focus stranded on the bare window, with no visible focus and nothing to forward
            // keyboard/scroll input to. Explicitly handing it to the web view instead is what
            // actually makes Preview interactive (scrollable, selectable) rather than a dead end.
            view.window?.makeFirstResponder(previewWebView)
        } else {
            // Editing surfaces take focus back when Preview yields it.
            view.window?.makeFirstResponder(textView)
        }
        updateCursorChrome()
    }

    private func makePreviewWebView() -> PreviewWebView {
        let webView = PreviewWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
        ])
        previewWebView = webView
        return webView
    }
}

extension DocumentViewController: NSTextViewDelegate {
    // Return inside a list item continues the list ("- ", "4. ", "- [ ] " on the new
    // line); Return on an empty item outdents one level, then leaves the list.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // List continuation is an editing-surface convenience (Code and Live alike): both
        // restructure the source the same way on Return inside a list item. Only Preview is
        // read-only and gets none of this.
        guard commandSelector == #selector(NSResponder.insertNewline(_:)), editorMode != .preview else { return false }
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
        guard !isApplyingProgrammaticEdit else { return }
        document?.text = textView.string
        document?.updateChangeCount(.changeDone)
        modeController.render()
        updateCursorChrome()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit, editorMode != .preview else { return }
        modeController.render()
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

    // Dropping a markdown file always opens it. If this window's document is untitled and
    // still empty, the dropped file replaces it in place (closing this now-redundant empty
    // window) rather than leaving a stray blank window behind. Any other content-bearing
    // window is left untouched and the file opens in a new window, so existing work is
    // never silently overwritten.
    func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedMarkdownFileAt url: URL) {
        let windowToCloseIfOpenSucceeds: NSWindow? = (document?.fileURL == nil && textView.string.isEmpty) ? view.window : nil

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
        textView.font = NSFont.systemFont(ofSize: size)
        UserDefaults.standard.set(size, forKey: "editorFontPointSize")
        modeController.render()
    }
}
