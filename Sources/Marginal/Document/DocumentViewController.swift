import AppKit

final class DocumentViewController: NSViewController {

    private(set) var textView: MarkdownTextView!
    private var isApplyingProgrammaticEdit = false
    private var isShowingSource = false

    // Single source of truth for the editor's base font size. NSTextView's `font` getter
    // (in rich-text mode) returns whatever attribute sits at the current selection/cursor —
    // which restyle() may have set to the near-invisible hidden-delimiter size (see
    // MarkdownStyler.hiddenDelimiterFontSize) — so it must never be read back as "the base
    // font"; this property is the only thing restyle()/toggleShowSource()/font-size
    // adjustment consult or mutate.
    private var editorFontSize: CGFloat = 15

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
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.shortcutDelegate = self
        textView.registerForDraggedTypes([.fileURL])
        let savedSize = UserDefaults.standard.double(forKey: "editorFontPointSize")
        editorFontSize = savedSize > 0 ? savedSize : 15
        textView.font = NSFont.systemFont(ofSize: editorFontSize)

        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.textView = textView
        self.view = containerView
    }

    func loadInitialText(_ text: String) {
        textView.string = text
        restyle(cursorLocation: nil)
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

    private func restyle(cursorLocation: String.Index?) {
        let text = textView.string
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text)
        )
        let attributed = MarkdownStyler.attributedString(
            for: text,
            model: model,
            baseFont: NSFont.systemFont(ofSize: editorFontSize),
            cursorLocation: cursorLocation
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
    }
}

extension DocumentViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        document?.text = textView.string
        document?.updateChangeCount(.changeDone)
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
    }
}

extension DocumentViewController: MarkdownTextViewShortcutDelegate {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.increased(from: editorFontSize))
    }

    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.decreased(from: editorFontSize))
    }

    func markdownTextViewCopyAsMarkdown(_ textView: MarkdownTextView) {
        copyCurrentSelectionAsMarkdown()
    }

    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView) {
        toggleShowSource()
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
        if isShowingSource {
            applyPlainSourceRendering()
        } else {
            restyle(cursorLocation: currentCursorIndex())
        }
    }
}
