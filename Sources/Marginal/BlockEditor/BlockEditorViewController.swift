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

    /// Whole-block selection (Task 14): escalates from ordinary in-block text selection to
    /// selecting one or more entire blocks. This controller wires the AppKit-side triggers
    /// (Shift+Up/Down past a block's bounds, Escape, ⌫, ⌘C, click/typing) to the pure
    /// `BlockSelectionController`, and keeps the selection overlay (`DesignPalette.selection`)
    /// on each selected block's wrapper view in sync with it.
    let selectionController = BlockSelectionController()

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

    // MARK: - Task 15: document-level undo

    /// A point-in-time capture of everything needed to fully restore the editor: the model plus
    /// enough UI state (focused block + its caret) to put the cursor back where the user was.
    /// `BlockDocument` is a small value type, so snapshotting the whole thing is simpler and just
    /// as cheap as computing/inverting a structural diff.
    private struct Snapshot {
        let document: BlockDocument
        let focusedBlockID: UUID?
        let caretOffset: Int
    }

    /// Guards `restore(_:)` against re-registering an undo step while an undo/redo is already in
    /// flight -- without this, `restore` mutating `document` would itself push a fresh snapshot
    /// through the next coalescence boundary and corrupt the undo stack (or, if `restore` pushed
    /// its own redo unconditionally without the guard, would double-push).
    private var isRestoring = false

    /// Identifies the edit target a typing burst is currently coalescing into (a block id string
    /// for ordinary text blocks, or a block+cell composite for table cells -- see
    /// `pushTypingCoalescenceSnapshotIfNeeded`). Plain typing pushes exactly one undo snapshot per
    /// *burst* rather than per keystroke: the snapshot is taken lazily, at the first edit to a
    /// given target since the last coalescence boundary (a structural op, a switch to a different
    /// target, or a pause -- see that method's doc comment for how the pause falls out of
    /// `typingCoalescenceDeadline` without a live timer).
    private var typingCoalescenceKey: String?
    private var typingCoalescenceDeadline: Date?

    /// How long a pause in typing within the same block must be before the next keystroke there
    /// starts a fresh undo step, per the brief's "1s pause" coalescence rule.
    private static let typingCoalescenceWindow: TimeInterval = 1.0

    /// The window's `NSUndoManager`, falling back to the responder chain's default -- and, on
    /// first use, switched out of `groupsByEvent` mode. AppKit's default coalesces every undo
    /// registration made during a single `NSEvent` dispatch into one group, which is the wrong
    /// granularity here (this controller already does its own explicit typing-burst
    /// coalescescing, see `pushTypingCoalescenceSnapshotIfNeeded`) and, more importantly, makes
    /// undo non-deterministic for anything that registers snapshots outside a live AppKit run
    /// loop (as the smoke tests below do) -- `groupsByEvent = false` plus this controller's own
    /// coalescing logic is what makes each `undo()`/`redo()` call step exactly one burst/op at a
    /// time, in both the app and the tests.
    private var didConfigureUndoManager = false
    private var undoManager_: UndoManager? {
        let manager = view.window?.undoManager ?? undoManager
        if let manager, !didConfigureUndoManager {
            manager.groupsByEvent = false
            didConfigureUndoManager = true
        }
        return manager
    }

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

    // MARK: - Task 15: document-level undo

    /// Captures the document plus enough UI state to restore the cursor: the focused block (if
    /// any has an inline-text caret to read) and its caret offset. Table-cell focus has no single
    /// caret offset to capture here -- restoring into a table block simply leaves nothing
    /// focused, which is an acceptable degradation since no test exercises table-cell undo.
    private func currentSnapshot() -> Snapshot {
        let caretOffset = focusedBlockID.flatMap { textView(for: $0)?.caretOffset } ?? 0
        return Snapshot(document: document, focusedBlockID: focusedBlockID, caretOffset: caretOffset)
    }

    /// Registers `snapshot` as the target of the next undo -- a no-op while `restore(_:)` is
    /// itself applying an undo/redo step (`isRestoring`), which would otherwise push a spurious
    /// extra step onto the stack. Wraps the registration in its own explicit
    /// `beginUndoGrouping`/`endUndoGrouping` pair so each push forms exactly one undo step no
    /// matter how `groupsByEvent` is configured or whether a live AppKit run loop is driving
    /// event-based grouping (it isn't, in the smoke tests) -- two `pushUndoSnapshot` calls back to
    /// back always produce two independently-undoable groups, never one merged group.
    private func pushUndoSnapshot(_ snapshot: Snapshot) {
        guard !isRestoring, let manager = undoManager_ else { return }
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: self) { vc in vc.restore(snapshot) }
        manager.endUndoGrouping()
    }

    /// Snapshot boundary for any discrete, atomic mutation (structural engine outcomes, style
    /// toggles, block-selection delete, table row append): always pushes, and closes out any
    /// in-flight typing-coalescence burst so the next keystroke starts a fresh one.
    private func pushStructuralUndoSnapshot() {
        guard !isRestoring else { return }
        pushUndoSnapshot(currentSnapshot())
        typingCoalescenceKey = nil
        typingCoalescenceDeadline = nil
    }

    /// Snapshot boundary for continuous typing: pushes only at the *start* of a typing burst --
    /// the first edit to land under `key` since the last coalescence boundary (a structural op, a
    /// switch to editing a different block/cell, or a pause of `typingCoalescenceWindow` or more)
    /// -- rather than once per keystroke. This is the standard editor UX (undo reverts a whole
    /// burst of typing, not one character at a time) and sidesteps needing a live coalescing
    /// timer: the "pause" rule falls out naturally because the deadline is only extended while
    /// typing continues, so the next keystroke after a real pause finds `now >= deadline` and
    /// starts a new burst/snapshot.
    ///
    /// - Parameters:
    ///   - key: identifies the coalescence target -- a block id's string for ordinary text
    ///     blocks, or a block+cell composite for table cells (see call sites).
    ///   - snapshot: the pre-edit state to restore to if this call starts a new burst. Ignored if
    ///     this edit coalesces into the current burst.
    private func pushTypingCoalescenceSnapshotIfNeeded(key: String, snapshot: @autoclosure () -> Snapshot) {
        guard !isRestoring else { return }
        let now = Date()
        if typingCoalescenceKey == key, let deadline = typingCoalescenceDeadline, now < deadline {
            typingCoalescenceDeadline = now.addingTimeInterval(Self.typingCoalescenceWindow)
            return
        }
        pushUndoSnapshot(snapshot())
        typingCoalescenceKey = key
        typingCoalescenceDeadline = now.addingTimeInterval(Self.typingCoalescenceWindow)
    }

    /// Restores `snapshot`'s document and focus/caret, then symmetrically registers the state
    /// *as it was just before this restore* as the redo step -- this is what makes `redo()` work
    /// through `NSUndoManager`'s normal grouping: each undo, when it runs, pushes the mirror-image
    /// redo, and vice versa.
    ///
    /// Tests never call this directly -- they drive undo/redo through
    /// `view.window?.undoManager`, exactly like a real keyboard shortcut would, and this is the
    /// target `registerUndo` invokes. Kept private (matching `Snapshot`'s access level) since
    /// nothing outside this file needs to name either type.
    private func restore(_ snapshot: Snapshot) {
        let redoSnapshot = currentSnapshot()
        isRestoring = true
        document = snapshot.document
        renderAll()
        if let id = snapshot.focusedBlockID, document[id]?.kind.inlineText != nil {
            focusBlock(id, caretOffset: snapshot.caretOffset)
        } else {
            focusedBlockID = nil
        }
        typingCoalescenceKey = nil
        typingCoalescenceDeadline = nil
        isRestoring = false
        onDocumentChange?(document)
        if let manager = undoManager_ {
            manager.beginUndoGrouping()
            manager.registerUndo(withTarget: self) { vc in vc.restore(redoSnapshot) }
            manager.endUndoGrouping()
        }
    }

    /// Focuses one cell of a `.table` block by coordinate -- tables have no single text view
    /// (`BlockViewFactory.textView(in:)` returns nil for them), so `focusBlock(_:caretOffset:)`
    /// can't reach into one; this is the table-specific equivalent.
    func focusTableCell(_ blockID: UUID, _ cell: TableEditEngine.Cell) {
        guard let tableView = tableView(for: blockID) else { return }
        tableView.focus(cell: cell)
        focusedBlockID = blockID
    }

    /// The `BlockTableView` wrapper for a `.table` block, if `blockID` names one -- exposed so
    /// tests (and this controller's own table-editing callbacks) can reach cell-level state
    /// without knowing every other block kind's wrapper shape.
    func tableView(for blockID: UUID) -> BlockTableView? {
        blockViews[blockID] as? BlockTableView
    }

    // MARK: - Whole-block selection (Task 14)

    /// Starts (or restarts) whole-block selection from `anchor` to `focus` inclusive, applies the
    /// selection overlay, and makes this controller the window's first responder so it can
    /// intercept ⌫/⌘C/Escape while the selection is active (see `keyDown(with:)`/`copy(_:)`
    /// below) -- no block's text view stays focused during whole-block selection.
    func beginBlockSelection(anchor: UUID, extendingTo focus: UUID) {
        selectionController.beginSelection(anchor: anchor, extendingTo: focus, in: document)
        applySelectionOverlay()
        focusedBlockID = nil
        view.window?.makeFirstResponder(self)
    }

    /// Ends whole-block selection and removes the overlay -- returns to normal text editing.
    func clearBlockSelection() {
        guard !selectionController.selectedBlockIDs.isEmpty else { return }
        selectionController.clear()
        applySelectionOverlay()
    }

    /// ⌫ with a block selection active: removes the selected blocks, reconciles the view stack,
    /// fires `onDocumentChange`, clears the selection, and focuses the returned caret's block.
    func deleteBlockSelection() {
        guard !selectionController.selectedBlockIDs.isEmpty else { return }
        pushStructuralUndoSnapshot()
        let oldBlocks = document.blocks
        let (newDocument, caret) = selectionController.deletingSelection(from: document)
        document = newDocument
        diffAndPatch(old: oldBlocks, new: document.blocks)
        updateListMarkers()
        selectionController.clear()
        applySelectionOverlay()
        onDocumentChange?(document)
        focusBlock(caret.blockID, caretOffset: caret.offset)
    }

    /// ⌘C with a block selection active: puts the selection's canonical markdown on the general
    /// pasteboard as plain text. A plain `@objc` responder action (like the style toggles on
    /// `BlockTextView`) rather than AppDelegate/menu wiring -- menu integration is Task 16.
    @objc func copy(_ sender: Any?) {
        guard !selectionController.selectedBlockIDs.isEmpty else { return }
        let markdown = selectionController.markdownForSelection(in: document)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }

    override var acceptsFirstResponder: Bool { true }

    /// While a block selection is active this controller is the first responder (see
    /// `beginBlockSelection`), so real ⌫/Escape key events land here instead of in any text
    /// view.
    override func keyDown(with event: NSEvent) {
        guard !selectionController.selectedBlockIDs.isEmpty else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117: // delete/backspace, forward-delete
            deleteBlockSelection()
        case 53: // escape
            clearBlockSelection()
        default:
            if let characters = printableCharacters(for: event) {
                typeIntoSelection(characters)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    /// `event`'s typed characters, if it represents an ordinary printable keystroke that should
    /// clear an active block selection and land in a text block -- i.e. not a Command-modified
    /// shortcut (⌘C etc, which have their own handling/menu routing) and not an empty/control
    /// string (arrow keys, function keys and similar report `characters` as non-nil but empty or
    /// control-only; those fall through to `super.keyDown` unchanged).
    private func printableCharacters(for event: NSEvent) -> String? {
        guard !event.modifierFlags.contains(.command),
              let characters = event.characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return characters
    }

    /// A real printable keystroke while a block selection is active (the "selection mode eats
    /// keystrokes" fix): clears the selection, focuses the first selected block's text view at
    /// its end, and inserts the typed characters there -- so the keystroke lands in a real block
    /// instead of being silently dropped by `super.keyDown` walking past this controller with no
    /// text view in the responder chain to receive it.
    private func typeIntoSelection(_ characters: String) {
        guard let targetBlockID = selectionController.selectedBlockIDs.first else { return }
        clearBlockSelection()
        guard let textView = textView(for: targetBlockID) else { return }
        view.window?.makeFirstResponder(textView)
        textView.caretOffset = textView.string.count
        focusedBlockID = targetBlockID
        textView.insertText(characters, replacementRange: textView.selectedRange())
    }

    /// Re-applies the selection overlay to exactly `selectionController.selectedBlockIDs`,
    /// clearing it from every other block's wrapper view.
    private func applySelectionOverlay() {
        let selected = Set(selectionController.selectedBlockIDs)
        for (id, wrapper) in blockViews {
            wrapper.wantsLayer = true
            wrapper.layer?.backgroundColor = selected.contains(id) ? DesignPalette.selection.cgColor : nil
        }
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
        if let tableView = wrapper as? BlockTableView {
            let blockID = block.id
            tableView.onCellEdit = { [weak self] cell, text in
                self?.applyTableCellEdit(blockID: blockID, cell: cell, text: text)
            }
            tableView.onAppendRow = { [weak self] in
                self?.appendTableRow(blockID: blockID)
            }
        }
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        return wrapper
    }

    /// A table cell's edit: applies `TableEditEngine.updateCell` and fires `onDocumentChange` --
    /// the cell's own text storage already shows the edit (the user just typed it), so unlike
    /// `apply(_:)` there is nothing to re-render or refocus here.
    private func applyTableCellEdit(blockID: UUID, cell: TableEditEngine.Cell, text: InlineText) {
        let key = "\(blockID.uuidString)#\(cell.row.map(String.init) ?? "header")-\(cell.column)"
        pushTypingCoalescenceSnapshotIfNeeded(
            key: key,
            snapshot: Snapshot(document: document, focusedBlockID: blockID, caretOffset: 0)
        )
        document = TableEditEngine.updateCell(document, blockID: blockID, cell: cell, content: text)
        onDocumentChange?(document)
    }

    /// Tab past a table's last cell: applies `TableEditEngine.appendRow` to the document. That
    /// changes the block's `BlockKind` (one more row), so `diffAndPatch` tears down the old
    /// `BlockTableView` and rebuilds a fresh one straight from the updated document -- the new
    /// instance already has the appended row's (empty) cell views built in, so all that's left is
    /// focusing its first cell.
    private func appendTableRow(blockID: UUID) {
        pushStructuralUndoSnapshot()
        let oldBlocks = document.blocks
        document = TableEditEngine.appendRow(document, blockID: blockID)
        diffAndPatch(old: oldBlocks, new: document.blocks)
        updateListMarkers()
        onDocumentChange?(document)
        guard case .table(_, _, let rows) = document[blockID]?.kind else { return }
        tableView(for: blockID)?.focus(cell: TableEditEngine.Cell(row: rows.count - 1, column: 0))
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
        pushStructuralUndoSnapshot()
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
        clearBlockSelection()
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }

        // Code blocks have no `InlineText` representation (`replacingInlineText` is a no-op for
        // them) but their `BlockTextView` is real and editable, so persisting a typed edit means
        // rebuilding the `.codeBlock` case directly from the text view's raw string. Shorthand/
        // autoformat never apply inside a code block.
        if case .codeBlock(let language, _) = document.blocks[index].kind {
            let code = view.string
            let oldCode = previousPlainText[blockID] ?? code
            let codeLengthDelta = code.count - oldCode.count
            let preEditCaretOffset = max(0, view.caretOffset - max(0, codeLengthDelta))
            pushTypingCoalescenceSnapshotIfNeeded(
                key: blockID.uuidString,
                snapshot: Snapshot(document: document, focusedBlockID: blockID, caretOffset: preEditCaretOffset)
            )
            var blocks = document.blocks
            blocks[index].kind = .codeBlock(language: language, code)
            document = BlockDocument(blocks: blocks)
            previousPlainText[blockID] = code
            BlockViewFactory.applyCodeHighlighting(to: view, code: code)
            onDocumentChange?(document)
            return
        }

        let oldPlainText = previousPlainText[blockID] ?? document.blocks[index].kind.inlineText?.plainText ?? ""
        let newPlainText = text.plainText
        let plainLengthDelta = newPlainText.count - oldPlainText.count
        let preEditCaretOffset = max(0, view.caretOffset - max(0, plainLengthDelta))
        pushTypingCoalescenceSnapshotIfNeeded(
            key: blockID.uuidString,
            snapshot: Snapshot(document: document, focusedBlockID: blockID, caretOffset: preEditCaretOffset)
        )
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

    /// A code block has no `InlineText` -- `BlockEditEngine.split` treats it (like any block
    /// whose `inlineText` is nil) as a no-op, so Enter inside one is special-cased here to insert
    /// a literal newline instead: `insertText` goes through the real `NSTextView` insertion path
    /// (moving the caret past the inserted character itself) and fires `textDidChange`, which
    /// routes into `blockTextView(_:didEditInlineText:)`'s `.codeBlock` branch above to persist
    /// the new string and re-run syntax highlighting -- the same path ordinary typing uses, so
    /// there is nothing extra to reconcile here.
    func blockTextViewDidPressEnter(_ view: BlockTextView, atOffset offset: Int) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }
        if case .codeBlock = document.blocks[index].kind {
            view.insertText("\n", replacementRange: NSRange(location: offset, length: 0))
            return
        }
        apply(BlockEditEngine.split(document, at: Caret(blockID: blockID, offset: offset)))
    }

    /// Backspace at offset 0 of a code block converts it in place to a `.paragraph` holding the
    /// code's raw text -- unlike a normal paragraph/heading/quote, it never merges into the
    /// previous block here (`BlockEditEngine.backspaceAtStart`'s own `previous.kind.inlineText`
    /// guard already treats a *previous* code block this way; this is the symmetric case where
    /// the block *being backspaced into* is itself a code block).
    func blockTextViewDidBackspaceAtStart(_ view: BlockTextView) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }
        if case .codeBlock(_, let code) = document.blocks[index].kind {
            pushStructuralUndoSnapshot()
            let oldBlocks = document.blocks
            var blocks = document.blocks
            blocks[index].kind = .paragraph(InlineText(code))
            document = BlockDocument(blocks: blocks)
            diffAndPatch(old: oldBlocks, new: document.blocks)
            updateListMarkers()
            previousPlainText[blockID] = code
            onDocumentChange?(document)
            focusBlock(blockID, caretOffset: 0)
            return
        }

        let outcome = BlockEditEngine.backspaceAtStart(document, in: blockID)
        // The Task 5 edge: the outcome carets onto a block whose kind has no inline text
        // (divider/table/code block) because it can't merge into that block -- there is no text
        // view to focus there, so enter whole-block selection on it instead.
        if outcome.document[outcome.caret.blockID]?.kind.inlineText == nil {
            pushStructuralUndoSnapshot()
            let oldBlocks = document.blocks
            document = outcome.document
            diffAndPatch(old: oldBlocks, new: document.blocks)
            updateListMarkers()
            onDocumentChange?(document)
            beginBlockSelection(anchor: outcome.caret.blockID, extendingTo: outcome.caret.blockID)
            return
        }
        apply(outcome)
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

    /// Shift+Up at the focused block's first visual line, or Shift+Down at its last visual line
    /// (see `BlockTextView.moveUpAndModifySelection`/`moveDownAndModifySelection`): the text
    /// selection has run out of room to grow inside this block, so it escalates to whole-block
    /// selection spanning the focused block and its neighbor in that direction. No-op if there is
    /// no neighbor that way (already at the document's edge).
    func blockTextView(_ view: BlockTextView, selectionEscapedBoundary up: Bool) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }
        let neighborIndex = up ? index - 1 : index + 1
        guard neighborIndex >= 0, neighborIndex < document.blocks.count else { return }
        beginBlockSelection(anchor: blockID, extendingTo: document.blocks[neighborIndex].id)
    }

    /// Escape while `view` is focused selects `view`'s whole block (a single-block selection).
    func blockTextViewDidPressEscape(_ view: BlockTextView) {
        guard let blockID = view.blockID else { return }
        beginBlockSelection(anchor: blockID, extendingTo: blockID)
    }

    /// Any click clears an active whole-block selection and returns to normal text editing.
    func blockTextViewDidReceiveClick(_ view: BlockTextView) {
        clearBlockSelection()
    }

    /// Persists a ⌘B/⌘I/⌘U/⌘⇧S style toggle's already-computed `text` into the document model,
    /// then re-renders `view` (through `BlockViewFactory`, via `render(_:asKind:baseFont:)`) so
    /// the new styling is actually visible, and restores `selection` -- `render` replaces the
    /// text storage wholesale, which would otherwise silently collapse the selection to nothing.
    /// No shorthand/autoformat check here: a style toggle never changes `plainText`, so none of
    /// those triggers can apply.
    func blockTextView(_ view: BlockTextView, didToggleStyle text: InlineText, selection: NSRange) {
        guard let blockID = view.blockID, let index = document.index(of: blockID) else { return }
        pushStructuralUndoSnapshot()
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
