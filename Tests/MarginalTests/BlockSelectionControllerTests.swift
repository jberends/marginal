import XCTest
@testable import Marginal

final class BlockSelectionControllerTests: XCTestCase {
    private func makeDoc(_ n: Int) -> BlockDocument {
        BlockDocument(blocks: (0..<n).map { Block(kind: .paragraph(InlineText("block\($0)"))) })
    }

    func testBeginSelectionForwardDragProducesContiguousDocumentOrderIDs() {
        let doc = makeDoc(4)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[1].id, extendingTo: doc.blocks[3].id, in: doc)
        XCTAssertEqual(controller.selectedBlockIDs, [doc.blocks[1].id, doc.blocks[2].id, doc.blocks[3].id])
    }

    func testBeginSelectionBackwardDragProducesSameDocumentOrderIDs() {
        let doc = makeDoc(4)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[3].id, extendingTo: doc.blocks[1].id, in: doc)
        XCTAssertEqual(controller.selectedBlockIDs, [doc.blocks[1].id, doc.blocks[2].id, doc.blocks[3].id])
    }

    func testExtendSelectionMovesFocusEndWhileKeepingAnchor() {
        let doc = makeDoc(5)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[1].id, extendingTo: doc.blocks[3].id, in: doc)
        controller.extendSelection(to: doc.blocks[2].id, in: doc)
        XCTAssertEqual(controller.selectedBlockIDs, [doc.blocks[1].id, doc.blocks[2].id])
    }

    func testExtendSelectionCanCrossBackPastAnchor() {
        let doc = makeDoc(5)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[2].id, extendingTo: doc.blocks[2].id, in: doc)
        controller.extendSelection(to: doc.blocks[0].id, in: doc)
        XCTAssertEqual(controller.selectedBlockIDs, [doc.blocks[0].id, doc.blocks[1].id, doc.blocks[2].id])
    }

    func testClearEmptiesSelection() {
        let doc = makeDoc(3)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[0].id, extendingTo: doc.blocks[1].id, in: doc)
        controller.clear()
        XCTAssertEqual(controller.selectedBlockIDs, [])
    }

    func testMarkdownForSelectionEqualsSerializerOutputForSlice() {
        let doc = makeDoc(4)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[1].id, extendingTo: doc.blocks[2].id, in: doc)
        let subDoc = BlockDocument(blocks: [doc.blocks[1], doc.blocks[2]])
        XCTAssertEqual(controller.markdownForSelection(in: doc), MarkdownSerializer.serialize(subDoc).markdown)
    }

    func testDeletingSelectionMidDocumentCaretsNeighborAfter() {
        let doc = makeDoc(4)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[1].id, extendingTo: doc.blocks[2].id, in: doc)

        let (newDoc, caret) = controller.deletingSelection(from: doc)

        XCTAssertEqual(newDoc.blocks.map(\.id), [doc.blocks[0].id, doc.blocks[3].id])
        XCTAssertEqual(caret, Caret(blockID: doc.blocks[3].id, offset: 0))
    }

    func testDeletingSelectionAtEndCaretsNeighborBefore() {
        let doc = makeDoc(4)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[2].id, extendingTo: doc.blocks[3].id, in: doc)

        let (newDoc, caret) = controller.deletingSelection(from: doc)

        XCTAssertEqual(newDoc.blocks.map(\.id), [doc.blocks[0].id, doc.blocks[1].id])
        XCTAssertEqual(caret, Caret(blockID: doc.blocks[1].id, offset: 0))
    }

    func testDeletingAllBlocksResultsInSingleEmptyParagraph() {
        let doc = makeDoc(3)
        let controller = BlockSelectionController()
        controller.beginSelection(anchor: doc.blocks[0].id, extendingTo: doc.blocks[2].id, in: doc)

        let (newDoc, caret) = controller.deletingSelection(from: doc)

        XCTAssertEqual(newDoc.blocks.count, 1)
        XCTAssertEqual(newDoc.blocks[0].kind, .paragraph(InlineText("")))
        XCTAssertEqual(caret, Caret(blockID: newDoc.blocks[0].id, offset: 0))
    }
}
