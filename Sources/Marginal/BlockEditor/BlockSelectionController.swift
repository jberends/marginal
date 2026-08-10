import Foundation

/// Whole-block selection: escalating from ordinary in-block text selection to selecting one or
/// more entire blocks (Shift+Up/Down past a block's own bounds, or Escape). Pure model/logic --
/// no AppKit -- so it's unit-testable on its own; `BlockEditorViewController` owns an instance and
/// wires it to the AppKit-side escalation triggers, selection overlay, delete, and copy.
final class BlockSelectionController {
    /// The selected blocks' ids, always in document order and always a contiguous run --
    /// regardless of whether the anchor/focus drag ran forward or backward through the document.
    private(set) var selectedBlockIDs: [UUID] = []

    /// The block the selection is anchored at (the one that does not move as the selection is
    /// extended). `nil` when there is no active selection.
    private var anchorID: UUID?

    /// Starts a whole-block selection running from `anchor` to `focus` inclusive (either order).
    func beginSelection(anchor: UUID, extendingTo focus: UUID, in doc: BlockDocument) {
        anchorID = anchor
        updateSelectedRange(anchor: anchor, focus: focus, in: doc)
    }

    /// Moves the non-anchor end of an already-begun selection to `focus`. If no selection is
    /// active yet, behaves like `beginSelection(anchor: focus, extendingTo: focus, in:)`.
    func extendSelection(to focus: UUID, in doc: BlockDocument) {
        guard let anchor = anchorID else {
            beginSelection(anchor: focus, extendingTo: focus, in: doc)
            return
        }
        updateSelectedRange(anchor: anchor, focus: focus, in: doc)
    }

    /// Ends whole-block selection (returns to normal text editing).
    func clear() {
        selectedBlockIDs = []
        anchorID = nil
    }

    private func updateSelectedRange(anchor: UUID, focus: UUID, in doc: BlockDocument) {
        guard let anchorIndex = doc.index(of: anchor), let focusIndex = doc.index(of: focus) else {
            selectedBlockIDs = []
            return
        }
        let lower = min(anchorIndex, focusIndex)
        let upper = max(anchorIndex, focusIndex)
        selectedBlockIDs = doc.blocks[lower...upper].map(\.id)
    }

    /// The selection's canonical markdown: builds a sub-document of exactly the selected blocks
    /// (already in document order) and serializes it exactly as `MarkdownSerializer` would for
    /// that slice on its own.
    func markdownForSelection(in doc: BlockDocument) -> String {
        let blocks = selectedBlockIDs.compactMap { doc[$0] }
        let subDoc = BlockDocument(blocks: blocks)
        return MarkdownSerializer.serialize(subDoc).markdown
    }

    /// Removes the selected blocks from `doc`, returning the new document and a `Caret` on the
    /// nearest surviving neighbor: the block that is now at the deleted range's start index (i.e.
    /// the block that was immediately after the deleted range) if one exists, otherwise the block
    /// immediately before it. If deleting everything, the new document is a single empty
    /// `.paragraph` -- an editor always has a block to type into -- and the caret points at it.
    func deletingSelection(from doc: BlockDocument) -> (BlockDocument, Caret) {
        let selected = Set(selectedBlockIDs)
        let selectedIndices = doc.blocks.indices.filter { selected.contains(doc.blocks[$0].id) }

        guard let firstIndex = selectedIndices.first, let lastIndex = selectedIndices.last else {
            let fallback = doc.blocks.first
            return (doc, Caret(blockID: fallback?.id ?? UUID(), offset: 0))
        }

        var newBlocks = doc.blocks
        newBlocks.removeSubrange(firstIndex...lastIndex)

        if newBlocks.isEmpty {
            let empty = Block(kind: .paragraph(InlineText("")))
            return (BlockDocument(blocks: [empty]), Caret(blockID: empty.id, offset: 0))
        }

        let neighborIndex = min(firstIndex, newBlocks.count - 1)
        let neighbor = newBlocks[neighborIndex]
        return (BlockDocument(blocks: newBlocks), Caret(blockID: neighbor.id, offset: 0))
    }
}
