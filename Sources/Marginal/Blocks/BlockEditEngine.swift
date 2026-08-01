import Foundation

enum BlockEditEngine {
    struct Outcome: Equatable {
        var document: BlockDocument
        var caret: Caret
    }

    // MARK: - Split (rows 1, 4, 5, 7)

    static func split(_ doc: BlockDocument, at caret: Caret) -> Outcome {
        guard let index = doc.index(of: caret.blockID) else {
            return Outcome(document: doc, caret: caret)
        }
        let block = doc.blocks[index]
        guard let inlineText = block.kind.inlineText else {
            return Outcome(document: doc, caret: caret)
        }

        let (left, right) = inlineText.split(at: caret.offset)

        let firstKind = block.kind.replacingInlineText(left)

        let secondKind: BlockKind
        if case .heading = block.kind {
            secondKind = .paragraph(right)
        } else {
            secondKind = block.kind.replacingInlineText(right)
        }

        var newBlocks = doc.blocks
        newBlocks[index].kind = firstKind
        let secondBlock = Block(kind: secondKind)
        newBlocks.insert(secondBlock, at: index + 1)

        let newDoc = BlockDocument(blocks: newBlocks)
        return Outcome(document: newDoc, caret: Caret(blockID: secondBlock.id, offset: 0))
    }

    // MARK: - Backspace at start (rows 2, 9, 10)

    static func backspaceAtStart(_ doc: BlockDocument, in blockID: UUID) -> Outcome {
        guard let index = doc.index(of: blockID) else {
            return Outcome(document: doc, caret: Caret(blockID: blockID, offset: 0))
        }
        guard index > 0 else {
            // First block: complete no-op.
            return Outcome(document: doc, caret: Caret(blockID: blockID, offset: 0))
        }

        let previous = doc.blocks[index - 1]
        let current = doc.blocks[index]

        guard let previousInline = previous.kind.inlineText else {
            // Previous block has no inline text (divider/table/codeBlock): no merge,
            // caret targets the previous block so the view layer can select it.
            return Outcome(document: doc, caret: Caret(blockID: previous.id, offset: 0))
        }

        if case .listItem(let style, let indent, let text) = current.kind {
            // List items don't merge on backspace-at-start; they convert to paragraph in place.
            _ = style
            _ = indent
            var newBlocks = doc.blocks
            newBlocks[index].kind = .paragraph(text)
            let newDoc = BlockDocument(blocks: newBlocks)
            return Outcome(document: newDoc, caret: Caret(blockID: current.id, offset: 0))
        }

        guard let currentInline = current.kind.inlineText else {
            // Shouldn't really happen (would've been caught by listItem or nil inline handling),
            // but guard defensively: no-op.
            return Outcome(document: doc, caret: Caret(blockID: blockID, offset: 0))
        }

        // Merge: current's content is appended to previous, and the previous block's kind
        // is what survives (heading/quote content adopts the previous block's kind).
        let mergeOffset = previousInline.length
        var mergedInline = previousInline
        mergedInline.append(currentInline)
        let mergedKind = previous.kind.replacingInlineText(mergedInline)

        var newBlocks = doc.blocks
        newBlocks[index - 1].kind = mergedKind
        newBlocks.remove(at: index)

        let newDoc = BlockDocument(blocks: newBlocks)
        return Outcome(document: newDoc, caret: Caret(blockID: previous.id, offset: mergeOffset))
    }

    // MARK: - Shorthand (row 3)

    static func applyShorthand(_ doc: BlockDocument, in blockID: UUID) -> Outcome? {
        guard let index = doc.index(of: blockID) else { return nil }
        let block = doc.blocks[index]
        guard let plainText = block.kind.inlineText?.plainText else { return nil }

        guard let newKind = shorthandKind(for: plainText) else { return nil }

        var newBlocks = doc.blocks
        newBlocks[index].kind = newKind
        let newDoc = BlockDocument(blocks: newBlocks)
        return Outcome(document: newDoc, caret: Caret(blockID: block.id, offset: 0))
    }

    private static func shorthandKind(for plainText: String) -> BlockKind? {
        if plainText == "---" {
            return .divider
        }
        if plainText.hasPrefix("```") {
            let rest = String(plainText.dropFirst(3))
            return .codeBlock(language: rest.isEmpty ? nil : rest, "")
        }
        if plainText == "- " || plainText == "* " {
            return .listItem(style: .bullet, indent: 0, InlineText(""))
        }
        if plainText == "[] " {
            return .listItem(style: .task(done: false), indent: 0, InlineText(""))
        }
        if plainText == "> " {
            return .quote(InlineText(""))
        }
        if plainText.hasSuffix(" ") {
            let withoutTrailingSpace = String(plainText.dropLast())
            if !withoutTrailingSpace.isEmpty,
               withoutTrailingSpace.count <= 6,
               withoutTrailingSpace.allSatisfy({ $0 == "#" }) {
                return .heading(level: withoutTrailingSpace.count, InlineText(""))
            }
            if !withoutTrailingSpace.isEmpty,
               withoutTrailingSpace.last == ".",
               withoutTrailingSpace.count > 1 {
                let digits = withoutTrailingSpace.dropLast()
                if !digits.isEmpty && digits.allSatisfy({ $0.isNumber }) {
                    return .listItem(style: .ordered, indent: 0, InlineText(""))
                }
            }
        }
        return nil
    }

    // MARK: - Indent (row 6)

    static func indent(_ doc: BlockDocument, blockID: UUID, by delta: Int) -> Outcome {
        guard let index = doc.index(of: blockID) else {
            return Outcome(document: doc, caret: Caret(blockID: blockID, offset: 0))
        }
        let block = doc.blocks[index]
        guard case .listItem(let style, let indent, let text) = block.kind else {
            return Outcome(document: doc, caret: Caret(blockID: blockID, offset: 0))
        }

        let newIndent = max(0, indent + delta)
        var newBlocks = doc.blocks
        newBlocks[index].kind = .listItem(style: style, indent: newIndent, text)
        let newDoc = BlockDocument(blocks: newBlocks)
        return Outcome(document: newDoc, caret: Caret(blockID: block.id, offset: text.length))
    }
}
