import AppKit

/// Renders a `BlockDocument` as a vertical stack of per-block views and routes every editing
/// gesture (Enter, backspace-at-start, Tab/backtab, live typing, shorthand/autoformat
/// conversion) through the Phase-1 engine (`Sources/Marginal/Blocks`) -- this controller never
/// mutates block structure itself, it only asks the engine for the next `BlockEditEngine.Outcome`
/// and reconciles the view stack to match.
@MainActor
final class BlockEditorViewController: NSViewController {
    private(set) var document: BlockDocument
    let baseFont: NSFont
    var onDocumentChange: ((BlockDocument) -> Void)?
    private(set) var focusedBlockID: UUID?

    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    /// Each block's wrapper view (as returned by `BlockViewFactory.view`), keyed by block id --
    /// the single source of truth this controller's view-stack diffing reads/writes.
    private var blockViews: [UUID: NSView] = [:]
    /// Ids whose wrapper already has its full-width constraint against `stackView` installed --
    /// a fresh wrapper's width anchor has no common ancestor with the stack until *after*
    /// `addArrangedSubview`, but re-adding an already-constrained wrapper (e.g. reordering
    /// during a diff) must not install a second, redundant constraint.
    private var widthConstrainedIDs: Set<UUID> = []
    /// Plain text of each block as of its last edit, keyed by block id -- lets
    /// `didEditInlineText` tell an insertion apart from a deletion (shorthand must only fire on
    /// insertion of a trailing trigger character, never on a delete that happens to land on a
    /// shorthand-shaped string; see the doc comment there).
    private var previousPlainText: [UUID: String] = [:]

    init(document: BlockDocument, baseFont: NSFont) {
        self.document = document
        self.baseFont = baseFont
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        // The document view is a plain container whose width tracks the scroll view's clip
        // view (so blocks reflow on window resize) and whose height is whatever autolayout
        // computes from the stack's arranged subviews -- the stack itself sits inset by 40pt
        // horizontal / 24pt vertical, matching the old markdown editor's textContainerInset.
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 40),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -40)
        ])

        scrollView.documentView = documentView
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        self.scrollView = scrollView
        self.stackView = stackView
        self.view = container

        renderAll()
    }

    // MARK: - Public API

    /// Full re-render: tears down every block view and rebuilds the stack from `doc` in order.
    /// Used on mode switch (source -> block editor) and when opening a different document --
    /// no view is assumed reusable across a `setDocument` call.
    func setDocument(_ doc: BlockDocument) {
        document = doc
        focusedBlockID = nil
        renderAll()
    }

    func focusBlock(_ id: UUID, caretOffset: Int) {
        guard let textView = textView(for: id) else { return }
        view.window?.makeFirstResponder(textView)
        textView.caretOffset = caretOffset
        focusedBlockID = id
    }

    // MARK: - Rendering

    private func renderAll() {
        for arranged in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        blockViews.removeAll()
        widthConstrainedIDs.removeAll()

        for block in document.blocks {
            let wrapper = makeView(for: block)
            blockViews[block.id] = wrapper
            addArrangedSubview(wrapper, blockID: block.id)
        }
        updateListMarkers()
    }

    private func makeView(for block: Block) -> NSView {
        let wrapper = BlockViewFactory.view(for: block, baseFont: baseFont, textDelegate: self)
        if let textView = BlockViewFactory.textView(in: wrapper) {
            textView.delegate = self
        }
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        return wrapper
    }

    /// Every block's wrapper spans the stack's full width ("full-width blocks" -- `NSStackView`'s
    /// `.leading` alignment only pins the leading edge, it doesn't stretch the cross axis on its
    /// own). Must run *after* `wrapper` is an arranged subview -- the width anchor has no common
    /// ancestor with the stack view until then; `widthConstrainedIDs` guards against installing
    /// a second constraint on a wrapper that's simply being repositioned.
    private func addArrangedSubview(_ wrapper: NSView, blockID: UUID) {
        stackView.addArrangedSubview(wrapper)
        guard !widthConstrainedIDs.contains(blockID) else { return }
        wrapper.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
        widthConstrainedIDs.insert(blockID)
    }

    private func textView(for blockID: UUID) -> BlockTextView? {
        guard let wrapper = blockViews[blockID] else { return nil }
        return BlockViewFactory.textView(in: wrapper)
    }

    /// Reconciles the view stack to `outcome.document`, then focuses `outcome.caret` -- the
    /// single path every structural engine call (split/backspace/indent/shorthand) funnels
    /// through.
    private func apply(_ outcome: BlockEditEngine.Outcome) {
        let oldBlocks = document.blocks
        document = outcome.document
        diffAndPatch(old: oldBlocks, new: document.blocks)
        updateListMarkers()
        onDocumentChange?(document)
        focusBlock(outcome.caret.blockID, caretOffset: outcome.caret.offset)
    }

    /// Diffs `old` and `new` by block id: drops views for ids no longer present, recreates the
    /// view for any surviving id whose `Block.kind` changed (an `Equatable` compare -- catches
    /// both structural changes, e.g. paragraph -> heading, and plain text changes on a merge/
    /// split, since `BlockKind`'s associated `InlineText` is part of that comparison), and
    /// leaves untouched views for ids whose kind is bit-for-bit identical. Views are always
    /// re-added to the stack in `new`'s order, since this is also how blocks get inserted or
    /// reordered.
    private func diffAndPatch(old: [Block], new: [Block]) {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newIDs = Set(new.map(\.id))

        for goneID in Set(blockViews.keys).subtracting(newIDs) {
            blockViews[goneID]?.removeFromSuperview()
            blockViews.removeValue(forKey: goneID)
            widthConstrainedIDs.remove(goneID)
            previousPlainText.removeValue(forKey: goneID)
        }

        for block in new {
            if let previous = oldByID[block.id], previous.kind != block.kind {
                blockViews[block.id]?.removeFromSuperview()
                blockViews.removeValue(forKey: block.id)
                widthConstrainedIDs.remove(block.id)
            }
        }

        for arranged in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        for block in new {
            let wrapper: NSView
            if let existing = blockViews[block.id] {
                wrapper = existing
            } else {
                wrapper = makeView(for: block)
                blockViews[block.id] = wrapper
            }
            addArrangedSubview(wrapper, blockID: block.id)
        }
    }

    /// Ordered-list display numbers: walks `document.blocks` tracking the indent level of the
    /// most recently seen ordered item; an ordered item at the same indent as its immediate
    /// predecessor continues that run, anything else (a different indent, a non-ordered list
    /// item, a non-list block) restarts the count at 1.
    private func updateListMarkers() {
        var previousOrderedIndent: Int?
        var runningNumber = 0

        for block in document.blocks {
            guard case .listItem(let style, let indent, _) = block.kind,
                  let wrapper = blockViews[block.id] as? ListItemWrapperView else {
                previousOrderedIndent = nil
                continue
            }

            switch style {
            case .ordered:
                runningNumber = (previousOrderedIndent == indent) ? runningNumber + 1 : 1
                wrapper.markerText = "\(runningNumber)."
                previousOrderedIndent = indent
            case .bullet, .task:
                wrapper.markerText = BlockViewFactory.markerText(for: style)
                previousOrderedIndent = nil
            }
        }
    }
}

// MARK: - BlockTextViewDelegate

extension BlockEditorViewController: @preconcurrency BlockTextViewDelegate {
    /// A shorthand/autoformat trigger is *only* ever the trailing character that was just
    /// inserted (a space closes `"# "`/`"- "`/`"1. "`/etc., a dash closes `"---"`, a backtick
    /// closes `` ` `` /``` ``` ``` ```, and an asterisk/tilde closes an inline
    /// `**bold**`/`*italic*`/`~~strikethrough~~` pattern for `InlineAutoformat`). Gating on
    /// this (plus the edit having been a net insertion, not a deletion) is what stops a
    /// backspace that happens to land on a shorthand-shaped string -- e.g. deleting
    /// "answer- " down to "- " -- from spuriously converting the block. Accepting "*"/"~" here
    /// is safe for block-level shorthand too: `BlockEditEngine.shorthandKind` never matches a
    /// plain text ending in either, so it's a no-op for that path and only unlocks
    /// `InlineAutoformat.convertCompletedPattern` below.
    private static func isShorthandTriggerChar(_ character: Character?) -> Bool {
        character == " " || character == "-" || character == "`" || character == "*" || character == "~"
    }

    func blockTextView(_ view: BlockTextView, didEditInlineText text: InlineText) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }

        // Code blocks have no `InlineText` representation (`replacingInlineText` is a no-op for
        // them) but their `BlockTextView` is real and editable, so persisting a typed edit means
        // rebuilding the `.codeBlock` case directly from the text view's raw string. Shorthand/
        // autoformat never apply inside a code block.
        if case .codeBlock(let language, _) = document.blocks[index].kind {
            var blocks = document.blocks
            blocks[index].kind = .codeBlock(language: language, view.string)
            document = BlockDocument(blocks: blocks)
            previousPlainText[blockID] = view.string
            onDocumentChange?(document)
            return
        }

        let oldPlainText = previousPlainText[blockID] ?? document.blocks[index].kind.inlineText?.plainText ?? ""
        let newPlainText = text.plainText
        previousPlainText[blockID] = newPlainText
        let isTriggerInsertion = newPlainText.count > oldPlainText.count
            && Self.isShorthandTriggerChar(newPlainText.last)

        var blocks = document.blocks
        blocks[index].kind = blocks[index].kind.replacingInlineText(text)
        document = BlockDocument(blocks: blocks)
        onDocumentChange?(document)

        if isTriggerInsertion, let outcome = BlockEditEngine.applyShorthand(document, in: blockID) {
            previousPlainText[outcome.caret.blockID] = outcome.document[outcome.caret.blockID]?.kind.inlineText?.plainText ?? ""
            apply(outcome)
            return
        }

        if isTriggerInsertion, let (converted, caret) = InlineAutoformat.convertCompletedPattern(in: text, caret: view.caretOffset) {
            guard let idx = document.index(of: blockID) else { return }
            var convertedBlocks = document.blocks
            convertedBlocks[idx].kind = convertedBlocks[idx].kind.replacingInlineText(converted)
            document = BlockDocument(blocks: convertedBlocks)
            previousPlainText[blockID] = converted.plainText
            onDocumentChange?(document)
            view.render(converted, asKind: document.blocks[idx].kind, baseFont: baseFont)
            view.caretOffset = caret
        }
    }

    func blockTextViewDidPressEnter(_ view: BlockTextView, atOffset offset: Int) {
        guard let blockID = view.blockID else { return }
        apply(BlockEditEngine.split(document, at: Caret(blockID: blockID, offset: offset)))
    }

    func blockTextViewDidBackspaceAtStart(_ view: BlockTextView) {
        guard let blockID = view.blockID else { return }
        apply(BlockEditEngine.backspaceAtStart(document, in: blockID))
    }

    func blockTextViewDidPressTab(_ view: BlockTextView, backward: Bool) {
        guard let blockID = view.blockID else { return }
        apply(BlockEditEngine.indent(document, blockID: blockID, by: backward ? -1 : 1))
    }

    func blockTextView(_ view: BlockTextView, moveFocusVertically up: Bool, caretX: CGFloat) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }

        var targetIndex = up ? index - 1 : index + 1
        while targetIndex >= 0 && targetIndex < document.blocks.count {
            let candidate = document.blocks[targetIndex]
            if candidate.kind.inlineText != nil, let targetView = textView(for: candidate.id) {
                let pointInWindow = view.convert(CGPoint(x: caretX, y: 0), to: nil)
                let localX = targetView.convert(pointInWindow, from: nil).x
                let localY: CGFloat = up ? targetView.bounds.maxY - 1 : 1
                let charIndex = targetView.characterIndexForInsertion(at: CGPoint(x: localX, y: localY))
                focusBlock(candidate.id, caretOffset: charIndex)
                return
            }
            targetIndex += up ? -1 : 1
        }
    }

    func blockTextView(_ view: BlockTextView, selectionEscapedBoundary up: Bool) {
        // Selection escalation across block boundaries is Task 14 -- stubbed for now.
    }

    /// Persists a ⌘B/⌘I/⌘U/⌘⇧S style toggle's already-computed `text` into the document model,
    /// then re-renders `view` (through `BlockViewFactory`, via `render(_:asKind:baseFont:)`) so
    /// the new styling is actually visible, and restores `selection` -- `render` replaces the
    /// text storage wholesale, which would otherwise silently collapse the selection to nothing.
    /// No shorthand/autoformat check here: a style toggle never changes `plainText`, so none of
    /// those triggers can apply.
    func blockTextView(_ view: BlockTextView, didToggleStyle text: InlineText, selection: NSRange) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }
        var blocks = document.blocks
        blocks[index].kind = blocks[index].kind.replacingInlineText(text)
        document = BlockDocument(blocks: blocks)
        previousPlainText[blockID] = text.plainText
        onDocumentChange?(document)
        view.render(text, asKind: document.blocks[index].kind, baseFont: baseFont)
        view.setSelectedRange(selection)
    }
}

// MARK: - NSTextViewDelegate

extension BlockEditorViewController: NSTextViewDelegate {
    /// The only bridge from AppKit's own text-change notification to `BlockTextViewDelegate`'s
    /// `didEditInlineText` -- `BlockTextView` intercepts *structural* commands itself (Enter,
    /// backspace-at-start, Tab, arrows) via `doCommand(by:)`, but plain character insertion/
    /// deletion has no such hook, so ordinary typing is picked up here instead.
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? BlockTextView else { return }
        blockTextView(textView, didEditInlineText: textView.currentInlineText)
    }
}
