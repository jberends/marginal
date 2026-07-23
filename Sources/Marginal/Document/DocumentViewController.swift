import AppKit

final class DocumentViewController: NSViewController {

    private(set) var textView: MarkdownTextView!
    private var isApplyingProgrammaticEdit = false
    private var isShowingSource = false
    private var fontBeforeShowingSource: NSFont?

    weak var document: MarkdownDocument?

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = MarkdownTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.shortcutDelegate = self
        let savedSize = UserDefaults.standard.double(forKey: "editorFontPointSize")
        textView.font = NSFont.systemFont(ofSize: savedSize > 0 ? savedSize : 15)

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
        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticEdit = true
        if isShowingSource {
            // Capture the real document font before switching to plain source. NSTextView's
            // `font` getter (in rich-text mode) returns the font at the current selection
            // start, not a stable document-wide font. Once we overwrite every character
            // (including the one at the selection start) with the tiny hidden-delimiter
            // monospaced font, `textView.font` would otherwise return that corrupted font
            // and poison the subsequent restyle when toggling back off.
            let baseFont = textView.font ?? NSFont.systemFont(ofSize: 15)
            fontBeforeShowingSource = baseFont
            let plain = MarkdownStyler.plainSourceAttributedString(for: textView.string, font: baseFont)
            textView.textStorage?.setAttributedString(plain)
        } else if let baseFont = fontBeforeShowingSource {
            textView.font = baseFont
        }
        textView.setSelectedRange(selectedRange)
        isApplyingProgrammaticEdit = false
        if !isShowingSource {
            restyle(cursorLocation: currentCursorIndex())
        }
    }

    private func restyle(cursorLocation: String.Index?) {
        let text = textView.string
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(
            for: text,
            model: model,
            baseFont: textView.font ?? NSFont.systemFont(ofSize: 15),
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
        restyle(cursorLocation: currentCursorIndex())
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        restyle(cursorLocation: currentCursorIndex())
    }
}

extension DocumentViewController: MarkdownTextViewShortcutDelegate {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.increased(from: textView.font?.pointSize ?? 15))
    }

    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.decreased(from: textView.font?.pointSize ?? 15))
    }

    func markdownTextViewCopyAsMarkdown(_ textView: MarkdownTextView) {
        copyCurrentSelectionAsMarkdown()
    }

    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView) {
        toggleShowSource()
    }

    private func setFontSize(_ size: CGFloat) {
        textView.font = NSFont.systemFont(ofSize: size)
        UserDefaults.standard.set(size, forKey: "editorFontPointSize")
        restyle(cursorLocation: currentCursorIndex())
    }
}
