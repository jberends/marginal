import AppKit

final class DocumentViewController: NSViewController {

    private(set) var textView: MarkdownTextView!
    private var gutterView: LineNumberGutterView!
    private var statusBar: StatusBarView!
    private var latestModel: MarkdownDocumentModel?
    private var firstResponderObservation: NSKeyValueObservation?
    private var isApplyingProgrammaticEdit = false
    private var isShowingSource = false

    // Single source of truth for the editor's base font size. NSTextView's `font` getter
    // (in rich-text mode) returns whatever attribute sits at the current selection/cursor —
    // which restyle() may have set to the near-invisible hidden-delimiter size (see
    // MarkdownStyler.hiddenDelimiterFontSize) — so it must never be read back as "the base
    // font"; this property is the only thing restyle()/toggleShowSource()/font-size
    // adjustment consult or mutate.
    // 16px body -- the design system's base size (headings scale 1.25/1.5/1.875 from it).
    private var editorFontSize: CGFloat = 16

    weak var document: MarkdownDocument?

    private lazy var imageStore = DocumentImageStore()
    // Not private: tests replace this with an injectable-prompt instance to drive the
    // granted/declined paths without a real NSOpenPanel.
    lazy var imageFolderAccess = DocumentFolderAccess()
    // Tests set this to suppress the real NSAlert `prepareForSave` shows on declined/failed access.
    var suppressSaveWarningForTests = false

    // Ends the retained read-path folder scope (see `beginRetainedFolderAccessIfFileBacked`)
    // exactly once, when this controller -- and with it, the document window -- is truly gone.
    //
    // `deinit`, not `viewWillDisappear`/`viewDidDisappear`: documents can tab together in one
    // NSWindow (see `MarkdownDocument.makeWindowControllers`'s `tabbingMode = .preferred`), and
    // switching away from a tab orders its window out, which fires the disappearance hooks on a
    // view controller that is still very much open -- ending the scope there would silently break
    // image reads on switching back to that tab. `deinit` only runs once the view controller (and
    // its window/document) is actually deallocated, which is the one event that really means
    // "this document is closed."
    deinit {
        MainActor.assumeIsolated {
            imageFolderAccess.endRetainedAccess()
        }
    }

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
        // NSTextView paints its own attributes over any range carrying `.link` -- blue text with
        // a full-strength underline by default -- which overrode the accent colour the styler
        // applies and left links reading as system-blue with a purple underline. Restating the
        // link appearance here keeps AppKit's rendering identical to MarkdownStyler's.
        textView.linkTextAttributes = [
            .foregroundColor: DesignPalette.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: DesignPalette.accent.withAlphaComponent(0.35),
            .cursor: NSCursor.pointingHand
        ]
        textView.linkActivationHandler = { [weak self] value in
            self?.activateLink(value) ?? false
        }
        textView.registerForDraggedTypes([.fileURL])
        let savedSize = UserDefaults.standard.double(forKey: "editorFontPointSize")
        editorFontSize = savedSize > 0 ? savedSize : 16
        textView.font = EditorFont.body(editorFontSize)

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
        let text = textView.string
        let cursorInText = view.window?.firstResponder === textView

        // Counts describe the whole document, so they stay accurate even when the caret is
        // elsewhere -- the status bar keeps showing whichever readout the user clicked to.
        let counts = DocumentCounts(text: text, selectedRange: textView.selectedRange())

        guard cursorInText, let cursor = currentCursorIndex() else {
            gutterView.lineNumber = nil
            statusBar.update(with: nil, counts: counts)
            return
        }

        let model = latestModel ?? MarkdownDocumentModel()
        let status = CursorStatus.status(for: text, model: model, cursor: cursor)
        statusBar.update(with: status, counts: counts)

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
        gutterView.lineTop = rectInGutter.minY
        gutterView.lineHeight = rectInGutter.height
    }

    func loadInitialText(_ text: String) {
        textView.string = text
        restyle(cursorLocation: nil)
        beginRetainedFolderAccessIfFileBacked()
    }

    /// Reopens the document folder's security scope (if a bookmark was stored for it, e.g. from
    /// a prior save) for the life of this controller, so `ImageCache` reads of a relocated
    /// `<doc>.assets/` sidecar image succeed on reopen. Called once, right after `loadInitialText`
    /// sets up the editor -- by then `document?.fileURL` is already populated for a document
    /// opened from disk (NSDocument sets it before `makeWindowControllers`/this call), and still
    /// nil for a fresh untitled document, for which this is a no-op.
    ///
    /// Never prompts (see `DocumentFolderAccess.beginRetainedAccess`): no bookmark simply means
    /// images silently fail to decode, which is acceptable graceful degradation rather than
    /// interrupting opening a document with a folder picker.
    private func beginRetainedFolderAccessIfFileBacked() {
        guard let fileURL = document?.fileURL else { return }
        let folder = fileURL.deletingLastPathComponent()
        imageFolderAccess.beginRetainedAccess(toFolder: folder)
        beginRetainedAccessForLinkedImages(fileURL: fileURL, folder: folder)
    }

    /// Reopens the per-file security scope (see `DocumentFolderAccess.storeSecurityScopedBookmark`)
    /// for every Finder-dragged, linked (absolute-path) image the document references, so
    /// `ImageCache` can read them back after reopen -- opening a document only grants sandbox
    /// access to that one file, never to sibling files elsewhere on disk, so each linked image
    /// needs its own reopened scope. Images inside the document's own `<doc>.assets/` folder are
    /// already covered by `beginRetainedAccess(toFolder:)` above and are skipped here. Never
    /// prompts: an image with no stored bookmark (e.g. dropped before this shipped) is simply
    /// left unreadable rather than interrupting reopen with a picker.
    private func beginRetainedAccessForLinkedImages(fileURL: URL, folder: URL) {
        let docName = fileURL.deletingPathExtension().lastPathComponent
        let assetsPrefix = folder.appendingPathComponent("\(docName).assets", isDirectory: true)
            .standardizedFileURL.path + "/"
        for image in MarkdownParser.parseImages(in: textView.string) {
            guard image.path.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: image.path)
            guard !url.standardizedFileURL.path.hasPrefix(assetsPrefix) else { continue }
            imageFolderAccess.beginRetainedAccess(to: url)
        }
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
        let html = htmlForCopy(of: String(textView.string[range]))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
    }

    /// HTML for the pasteboard: like MarkdownHTMLRenderer.html, but every local <img> is inlined
    /// as a data: URI so the copied fragment is self-contained (pasting into Mail/Notes/Word shows
    /// the image without the original file). The search key mirrors MarkdownHTMLRenderer's own
    /// src emission exactly: percent-encode with .urlPathAllowed, then escape "&" to "&amp;" --
    /// otherwise the replace silently no-ops for any path containing an ampersand or other
    /// percent-encoded character.
    func htmlForCopy(of markdown: String) -> String {
        let base = document?.fileURL?.deletingLastPathComponent()
        return MarkdownHTMLRenderer.htmlEmbeddingLocalImages(fromMarkdown: markdown, baseURL: base)
    }

    static func mimeType(forExtension ext: String) -> String {
        MarkdownHTMLRenderer.mimeType(forExtension: ext)
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
                baseURL: self.document?.fileURL?.deletingLastPathComponent(),
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

    func toggleShowSource() {
        isShowingSource.toggle()
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
    }

    // Re-applies the plain monospace source rendering, preserving the selection across the
    // text storage mutation. Used both when Show Source is first toggled on and whenever a
    // delegate callback (selection change, text change, font size change) would otherwise
    // have called restyle() while still in Show Source mode.
    private func applyPlainSourceRendering() {
        let plain = MarkdownStyler.plainSourceAttributedString(for: textView.string, font: NSFont.systemFont(ofSize: editorFontSize))
        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticEdit = true
        textView.textStorage?.setAttributedString(plain)
        // setSelectedRange must run before isApplyingProgrammaticEdit is cleared: it
        // synchronously fires textViewDidChangeSelection, which would otherwise run
        // unguarded and stomp the render this method just applied.
        textView.setSelectedRange(selectedRange)
        isApplyingProgrammaticEdit = false
    }

    /// AppKit's own link click. Always reports the link as handled so NSTextView never falls
    /// back to opening it with LaunchServices.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        activateLink(link)
    }

    /// Handles a link the user activated (⌘-click, or AppKit's own link click). Returns true
    /// when it dealt with the link, which also stops AppKit falling back to LaunchServices --
    /// that fallback is what produced a "The application can't be opened. -50" dialog for an
    /// in-document "#anchor", which is not something the Finder can open.
    @discardableResult
    func activateLink(_ value: Any) -> Bool {
        let raw: String
        switch value {
        case let url as URL: raw = url.absoluteString
        case let string as String: raw = string
        default: return false
        }

        // In-document anchor: scroll to the heading whose GitHub-style slug matches.
        if raw.hasPrefix("#") {
            let wanted = String(raw.dropFirst()).lowercased()
            let text = textView.string
            for header in MarkdownParser.parseHeaders(in: text)
            where Self.anchorSlug(for: String(text[header.contentRange])) == wanted {
                let target = NSRange(header.contentRange, in: text)
                textView.setSelectedRange(NSRange(location: target.location, length: 0))
                textView.scrollRangeToVisible(target)
                textView.window?.makeFirstResponder(textView)
                return true
            }
            // Unknown anchor: swallow it anyway rather than handing "#missing" to the Finder.
            return true
        }

        if let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return true
        }

        // A relative path (./notes.md, ../parent) resolves against the document on disk.
        if let documentURL = (view.window?.windowController?.document as? NSDocument)?.fileURL {
            let resolved = URL(fileURLWithPath: raw, relativeTo: documentURL.deletingLastPathComponent()).standardizedFileURL
            if FileManager.default.fileExists(atPath: resolved.path) {
                NSWorkspace.shared.open(resolved)
                return true
            }
        }
        return true
    }

    /// GitHub's heading-anchor slug: lowercased, punctuation dropped, spaces to hyphens. This is
    /// the form "[Heading Level 1](#heading-level-1)" in a hand-written table of contents assumes.
    static func anchorSlug(for headingText: String) -> String {
        let lowered = headingText.trimmingCharacters(in: .whitespaces).lowercased()
        let stripped = lowered.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            if character == "-" || character == " " { return character }
            return "\u{0}"
        }
        return String(stripped).replacingOccurrences(of: "\u{0}", with: "")
            .replacingOccurrences(of: " ", with: "-")
    }

    private func restyle(cursorLocation: String.Index?) {
        let text = textView.string
        // Explicit [text](url) links first, then bare URLs/emails in the prose. An autolink also
        // suppresses any inline emphasis the parser found *inside* it: a URL like
        // ".../some_path/file_name" otherwise reads as italic to the underscore rule, which both
        // mis-styles it and hides the underscores as if they were delimiters.
        let explicitLinks = MarkdownParser.parseLinks(in: text)
        let allInlineStyles = MarkdownParser.parseInlineStyles(in: text)
        let inlineCodeRanges = allInlineStyles
            .filter { $0.kind == .code }
            .map { $0.openingDelimiterRange.lowerBound..<$0.closingDelimiterRange.upperBound }
        let autolinks = MarkdownParser.parseAutolinks(
            in: text,
            excluding: explicitLinks.map(\.fullRange) + inlineCodeRanges
        )
        let inlineStyles = allInlineStyles.filter { style in
            let styleRange = style.openingDelimiterRange.lowerBound..<style.closingDelimiterRange.upperBound
            return !autolinks.contains { $0.fullRange.lowerBound < styleRange.upperBound && $0.fullRange.upperBound > styleRange.lowerBound }
        }

        let model = MarkdownDocumentModel(
            inlineStyles: inlineStyles,
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: explicitLinks + autolinks,
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text),
            tables: MarkdownParser.parseTables(in: text),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text),
            images: MarkdownParser.parseImages(in: text)
        )
        latestModel = model
        let attributed = MarkdownStyler.attributedString(
            for: text,
            model: model,
            baseFont: NSFont.systemFont(ofSize: editorFontSize),
            cursorLocation: cursorLocation,
            selectedRange: Range(textView.selectedRange(), in: text),
            documentBaseURL: document?.fileURL?.deletingLastPathComponent()
        )

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
        // therefore shifts every line below it -- unlike headers/blockquotes, where only a
        // marker prefix toggles size while the line's content stays at content size, so line
        // height never changes. Found via manual GUI verification: NSTextView's automatic
        // display invalidation after the in-place setAttributes calls above redraws only the
        // stale (pre-shift) region, leaving lines below a revealed/hidden rule visually blank
        // until some other event (e.g. a selection change) forces a full redraw. The layout
        // itself is always correct (verified with a standalone NSLayoutManager harness); only
        // the drawn pixels go stale. Forcing a full-view redraw after every restyle fixes it.
        textView.needsDisplay = true
    }
}

extension DocumentViewController: NSTextViewDelegate {
    // Return inside a list item continues the list ("- ", "4. ", "- [ ] " on the new
    // line); Return on an empty item outdents one level, then leaves the list.
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)), !isShowingSource else { return false }
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
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
        updateCursorChrome()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
        updateCursorChrome()
    }
}

extension DocumentViewController {
    /// Whether the document references any externally-linked image -- an absolute-path image that
    /// isn't one of Marginal's managed temp files. Used to decide whether to offer the Save panel's
    /// "also copy linked images" checkbox: a paste-only document has nothing external to copy.
    func hasExternallyLinkedImages() -> Bool {
        MarkdownParser.parseImages(in: textView.string).contains { span in
            span.path.hasPrefix("/") && !imageStore.isManagedTemp(URL(fileURLWithPath: span.path))
        }
    }

    /// Called just before the document writes to `targetURL`. Moves managed temp images into
    /// <doc>.assets/ and rewrites their absolute temp paths in the text to relative. Updates both
    /// the text view storage and document.text so the written file and the open editor agree.
    /// No-op when the document has no managed (temp) images -- linked/absolute paths are left as-is.
    ///
    /// Writing a sibling ".assets" folder needs write access to the target folder itself, which
    /// under the sandbox a save panel does NOT grant (it grants access only to the named file) --
    /// so this acquires folder access via `imageFolderAccess` first. If access is declined or the
    /// relocation fails, the temp paths are left untouched (never rewritten to a dead reference)
    /// and a visible warning is shown instead of a silent beep-and-swallow.
    func prepareForSave(to targetURL: URL, now: Date, copyLinkedImages: Bool = false) {
        let docName = targetURL.deletingPathExtension().lastPathComponent
        let folder = targetURL.deletingLastPathComponent()
        let assetsDir = folder.appendingPathComponent("\(docName).assets", isDirectory: true)

        let text = textView.string
        let spans = MarkdownParser.parseImages(in: text)
        // Collect managed temp URLs referenced in the document.
        let managed = spans.compactMap { span -> (ImageSpan, URL)? in
            let url = URL(fileURLWithPath: span.path)
            return imageStore.isManagedTemp(url) ? (span, url) : nil
        }

        // Externally-linked images: absolute paths that are neither managed temp files nor
        // already inside `<doc>.assets/`. Copying these in is opt-in via the Save panel's
        // accessory checkbox (`copyLinkedImages`) -- collected up front so the `withAccess`
        // closure below can act on them without re-parsing.
        let assetsPrefix = assetsDir.standardizedFileURL.path + "/"
        let linked = spans.compactMap { span -> (ImageSpan, URL)? in
            guard span.path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: span.path)
            guard !imageStore.isManagedTemp(url) else { return nil }
            guard !url.standardizedFileURL.path.hasPrefix(assetsPrefix) else { return nil }
            return (span, url)
        }

        // Nothing to do unless there are managed images to relocate, or linked images the user
        // opted to copy in. A linked-only document (only absolute Finder-dragged paths) must NOT
        // short-circuit here when copy-in is requested -- that was the bug where ticking the
        // checkbox did nothing for such a document.
        guard !managed.isEmpty || (copyLinkedImages && !linked.isEmpty) else { return }

        // Two spans can reference the same managed temp file (e.g. duplicated markdown) --
        // relocate each distinct URL only once, or a second moveItem on an already-moved
        // source would throw and abort the whole save-prep after the first move already
        // happened on disk. Dedupe while preserving first-occurrence order: relocateTempFiles'
        // clash-avoidance (appending "-2", "-3", ...) is order-dependent when several images
        // share the same `now` timestamp, and a Set's iteration order is unspecified, so simply
        // deduping via Set would make which file gets the plain name vs. "-2" nondeterministic.
        var seenManagedURLs = Set<URL>()
        let uniqueManagedURLs = managed.map { $0.1 }.filter { seenManagedURLs.insert($0).inserted }

        let reason = "Marginal needs permission to save this document's images in this folder."
        // `relocateTempFiles` throws; the closure swallows that into an empty map (rather than
        // propagating an optional out of `withAccess`, which returns T? itself -- doing the
        // try/catch here keeps this a single-level optional instead of a [URL: URL]?? that would
        // need an extra flatten) and an empty map is then treated the same as a decline below.
        //
        // Linked-image copying happens in this same `withAccess` scope so the copy write is
        // covered by the just-acquired folder access. Unreadable sources are skipped (left as
        // absolute paths) rather than thrown -- a valid outcome, not data loss.
        let result: (moveMap: [URL: URL], linkedMap: [URL: URL])? = imageFolderAccess.withAccess(toFolder: folder, reason: reason) { _ in
            let moveMap = (try? imageStore.relocateTempFiles(uniqueManagedURLs, into: assetsDir, now: now)) ?? [:]
            var linkedMap: [URL: URL] = [:]
            if copyLinkedImages {
                var seenLinkedURLs = Set<URL>()
                let uniqueLinkedURLs = linked.map { $0.1 }.filter { seenLinkedURLs.insert($0).inserted }
                for source in uniqueLinkedURLs {
                    // A Finder-dragged image outside the sandbox needs its own security scope to
                    // be readable here; a per-file bookmark was stored when it was dropped, so
                    // (re)open it. Idempotent, and a no-op/false for paths already reachable.
                    imageFolderAccess.beginRetainedAccess(to: source)
                    guard FileManager.default.isReadableFile(atPath: source.path) else { continue }
                    if let dest = try? imageStore.copyExternalFile(at: source, into: assetsDir, now: now) {
                        linkedMap[source] = dest
                    }
                }
            }
            return (moveMap, linkedMap)
        }

        guard let result else {
            // Access was declined: keep the temp paths (the text still saves, and images still
            // resolve from temp this session) and warn -- never a silent dead reference.
            warnImagesNotSaved()
            return
        }
        // Managed images existed but none relocated -> the move itself failed; warn and keep the
        // temp paths. A linked-only document legitimately has an empty moveMap (nothing managed to
        // move), so an empty moveMap alone must NOT warn -- only warn when there was managed work
        // that produced nothing.
        if !uniqueManagedURLs.isEmpty && result.moveMap.isEmpty {
            warnImagesNotSaved()
            return
        }
        let moveMap = result.moveMap
        let linkedMap = result.linkedMap

        // The resolved image paths below switch from temp (always readable) to the relocated
        // `<doc>.assets/` path -- hold the folder's scope open for the rest of this session so
        // `ImageCache` can read them back immediately, not just on a future reopen.
        imageFolderAccess.beginRetainedAccess(toFolder: folder)

        // Rewrite paths back-to-front so earlier ranges stay valid. Managed and linked rewrites
        // are merged into one descending-range pass so ranges from one kind don't get shifted by
        // the other.
        var mutable = text
        var rewrites: [(range: Range<String.Index>, url: URL, newURL: URL)] =
            managed.map { (span: $0.0, url: $0.1) }.map { ($0.span.pathRange, $0.url, moveMap[$0.url]) }
                .compactMap { range, url, newURL in newURL.map { (range, url, $0) } }
        rewrites += linked.map { (span: $0.0, url: $0.1) }.map { ($0.span.pathRange, $0.url, linkedMap[$0.url]) }
                .compactMap { range, url, newURL in newURL.map { (range, url, $0) } }
        for (range, _, newURL) in rewrites.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            let relative = "\(docName).assets/\(newURL.lastPathComponent)"
            mutable.replaceSubrange(range, with: relative)
        }

        // Keep the open editor and the document text in agreement with what we write.
        textView.string = mutable
        document?.text = mutable
        restyle(cursorLocation: currentCursorIndex())
    }

    /// Shown when `prepareForSave` cannot relocate images (declined access, or the move itself
    /// failed) -- surfaces the loss instead of leaving it as a silent beep. Suppressed in tests,
    /// where driving a real `NSAlert` sheet headlessly isn't meaningful.
    private func warnImagesNotSaved() {
        guard !suppressSaveWarningForTests else { return }
        let alert = NSAlert()
        alert.messageText = "Images were not saved alongside the document"
        alert.informativeText = "Folder access was declined, so pasted images remain temporary and may be lost. Save again and grant access to keep them."
        alert.alertStyle = .warning
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// Writes managed image data into the temp container and returns the absolute temp path to
    /// embed. Always temp+absolute, regardless of whether the document is untitled or already
    /// saved: relocating into `<doc>.assets/` requires folder write access that only an explicit
    /// save can acquire (see `prepareForSave`), so every insert -- paste or drop -- lands here
    /// first and is relocated later, at save time.
    func insertImageData(_ data: Data, sourceExtension: String, now: Date) -> String? {
        let ext = Self.normalizedImageExtension(sourceExtension)
        do {
            // Always buffer managed images in the temp container. Writing directly beside a saved
            // document is impossible under the sandbox (a save panel grants access to the named
            // file only, not to create sibling files), so relocation into <doc>.assets/ is deferred
            // to an explicit user save (see prepareForSave), which acquires folder access first.
            let written = try imageStore.writeToTemp(data: data, ext: ext, now: now)
            return written.path
        } catch {
            NSSound.beep()
            return nil
        }
    }

    /// Strips `]` from a filename-derived alt-text stem: `MarkdownParser.parseImages`'s alt group
    /// is `[^\]]*`, so a raw `]` inside the alt (e.g. from a source file named `IMG[final].png`)
    /// prematurely closes the `[...]` and breaks parsing of the whole image span. `[` is left
    /// alone -- the regex tolerates it just fine.
    static func sanitizedAltText(_ stem: String) -> String {
        stem.replacingOccurrences(of: "]", with: "")
    }

    /// PNG for raw bitmap/tiff; keep known compressed formats as-is.
    static func normalizedImageExtension(_ ext: String) -> String {
        let known: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]
        let lower = ext.lowercased()
        return known.contains(lower) ? lower : "png"
    }

    /// Returns (bytes, extension) for the best image on the pasteboard, or nil.
    static func imageDataFromPasteboard(_ pb: NSPasteboard) -> (Data, String)? {
        if let png = pb.data(forType: .png) { return (png, "png") }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        // A file URL to an image counts as a paste of an existing file → treat as managed copy.
        if let url = NSURL(from: pb) as URL?,
           MarkdownTextView.pasteImageFileExtensions.contains(url.pathExtension.lowercased()),
           let data = try? Data(contentsOf: url) {
            return (data, url.pathExtension)
        }
        return nil
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
        toggleShowSource()
    }

    func markdownTextViewInsertPastedImage(_ textView: MarkdownTextView) -> Bool {
        insertPastedImage(from: NSPasteboard.general, into: textView)
    }

    /// The "image unavailable" placeholder was clicked: offers a choice of scope -- just the
    /// image's folder, or the whole Home folder (covers every image under it, so the user isn't
    /// asked again) -- then confirms via the sanctioned NSOpenPanel -> security-scoped-bookmark
    /// flow. The panel confirm is REQUIRED by the sandbox: a valid security-scoped bookmark can
    /// only be made for a folder the user selects through powerbox, so the alert's buttons merely
    /// pre-navigate the panel to the right starting folder; they can't grant access by themselves.
    /// Real-app-only: driving a real NSAlert/NSOpenPanel sheet headlessly isn't meaningful in a
    /// unit test.
    func markdownTextViewRequestImageAccess(_ textView: MarkdownTextView, resolvedURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Show this image?"
        alert.informativeText = "Marginal needs permission to read this image. You can grant " +
            "access to just the image's folder, or to your whole Home folder -- Home covers " +
            "everything under it, so you won't be asked again for other images."
        alert.addButton(withTitle: "Grant This Folder")
        alert.addButton(withTitle: "Grant Home Folder")
        alert.addButton(withTitle: "Cancel")

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.acquireScopedFolder(startingAt: resolvedURL.deletingLastPathComponent(),
                                          prompt: "Grant Access")
            case .alertSecondButtonReturn:
                self.acquireScopedFolder(startingAt: FileManager.default.homeDirectoryForCurrentUser,
                                          prompt: "Grant Home Access")
            default:
                break  // Cancel: do nothing.
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(alert.runModal())
        }
    }

    /// Shows an NSOpenPanel pre-navigated to `directoryURL` and, if the user confirms a folder,
    /// records a security-scoped bookmark for it and forces a re-render so any now-accessible
    /// image loads. Shared by both buttons in `markdownTextViewRequestImageAccess`.
    private func acquireScopedFolder(startingAt directoryURL: URL, prompt: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL
        panel.prompt = prompt

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let chosenURL = panel.url, let self else { return }
            self.imageFolderAccess.storeSecurityScopedBookmark(for: chosenURL)
            self.imageFolderAccess.beginRetainedAccess(to: chosenURL)
            // ImageCache never caches a failed decode (see its type doc), so the next
            // drawBackground pass simply retries the read now that access is granted --
            // forcing a redraw is enough, no cache entry needs to be dropped first.
            self.textView.needsDisplay = true
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    /// Testable core of the paste-image flow: takes an injectable pasteboard so tests never
    /// have to touch the global `NSPasteboard.general`.
    func insertPastedImage(from pb: NSPasteboard, into textView: MarkdownTextView) -> Bool {
        // Prefer file promises / file URLs handled by the drag path; here handle raw image data.
        guard let (data, ext) = Self.imageDataFromPasteboard(pb) else { return false }
        guard let path = insertImageData(data, sourceExtension: ext, now: Date()) else { return true }
        let alt = Self.sanitizedAltText(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
        let markup = "![\(alt)](\(path))"
        let sel = textView.selectedRange()
        if textView.shouldChangeText(in: sel, replacementString: markup) {
            textView.insertText(markup, replacementRange: sel)
            textView.didChangeText()
        }
        return true
    }

    // Dropping a markdown file always opens it. If this window's document is untitled and
    // still empty, the dropped file replaces it in place (closing this now-redundant empty
    // window) rather than leaving a stray blank window behind. Any other content-bearing
    // window is left untouched and the file opens in a new window, so existing work is
    // never silently overwritten.
    /// Linked image drop: absolute path, never copied into the document's assets folder. The
    /// drag session grants sandbox read access only for its own duration, so a per-file
    /// security-scoped bookmark is captured here (drop time is the only moment access is
    /// guaranteed) to let a later reopen reactivate it via `beginRetainedAccessForLinkedImages`.
    func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedImageFileAt url: URL, atCharacterIndex characterIndex: Int) {
        let markup = "![\(Self.sanitizedAltText(url.deletingPathExtension().lastPathComponent))](\(url.path))"
        let range = NSRange(location: characterIndex, length: 0)
        if textView.shouldChangeText(in: range, replacementString: markup) {
            textView.insertText(markup, replacementRange: range)
            textView.didChangeText()
        }
        imageFolderAccess.storeSecurityScopedBookmark(for: url)
    }

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
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
    }
}
