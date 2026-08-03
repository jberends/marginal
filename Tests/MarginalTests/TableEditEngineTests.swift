import XCTest
@testable import Marginal

final class TableEditEngineTests: XCTestCase {
    func testTabWalksHeaderThenRowsThenSignalsNewRow() {
        XCTAssertEqual(TableEditEngine.nextCell(after: .init(row: nil, column: 1), columns: 2, rowCount: 1),
                       .init(row: 0, column: 0))
        XCTAssertNil(TableEditEngine.nextCell(after: .init(row: 0, column: 1), columns: 2, rowCount: 1))
    }
    func testEnterMovesDownSameColumn() {
        XCTAssertEqual(TableEditEngine.cellBelow(.init(row: nil, column: 1), rowCount: 2), .init(row: 0, column: 1))
        XCTAssertEqual(TableEditEngine.cellBelow(.init(row: 0, column: 1), rowCount: 2), .init(row: 1, column: 1))
        XCTAssertNil(TableEditEngine.cellBelow(.init(row: 1, column: 1), rowCount: 2))
    }
    func testUpdateCellAndAppendRow() {
        let t = Block(kind: .table(alignments: [.left], header: [InlineText("H")], rows: [[InlineText("a")]]))
        var doc = BlockDocument(blocks: [t])
        doc = TableEditEngine.updateCell(doc, blockID: t.id, cell: .init(row: 0, column: 0), content: InlineText("b"))
        doc = TableEditEngine.appendRow(doc, blockID: t.id)
        guard case let .table(_, _, rows) = doc.blocks[0].kind else { return XCTFail() }
        XCTAssertEqual(rows, [[InlineText("b")], [InlineText("")]])
    }
    func testUpdateCellGuardsNegativeIndices() {
        let t = Block(kind: .table(alignments: [.left], header: [InlineText("H")], rows: [[InlineText("a")]]))
        let doc = BlockDocument(blocks: [t])
        // Negative column in header should not crash; document unchanged
        let doc1 = TableEditEngine.updateCell(doc, blockID: t.id, cell: .init(row: nil, column: -1), content: InlineText("x"))
        XCTAssertEqual(doc1, doc)
        // Negative row in body should not crash; document unchanged
        let doc2 = TableEditEngine.updateCell(doc, blockID: t.id, cell: .init(row: -1, column: 0), content: InlineText("x"))
        XCTAssertEqual(doc2, doc)
        // Negative column in body should not crash; document unchanged
        let doc3 = TableEditEngine.updateCell(doc, blockID: t.id, cell: .init(row: 0, column: -1), content: InlineText("x"))
        XCTAssertEqual(doc3, doc)
    }
}
