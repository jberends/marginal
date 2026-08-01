import Foundation

enum TableEditEngine {
    struct Cell: Equatable {
        var row: Int?  // nil = header row
        var column: Int
    }

    /// Tab walks header left-to-right, then body rows row-major.
    /// Returns nil when past the LAST body cell (caller appends a row).
    static func nextCell(after cell: Cell, columns: Int, rowCount: Int) -> Cell? {
        if cell.row == nil {
            // In header; move to next header column or to body row 0, column 0
            if cell.column + 1 < columns {
                // Next column in header
                return Cell(row: nil, column: cell.column + 1)
            } else {
                // End of header; move to row 0, column 0
                return Cell(row: 0, column: 0)
            }
        } else {
            // In body; move to next cell in row-major order
            let currentRow = cell.row!
            if cell.column + 1 < columns {
                // Next column in same row
                return Cell(row: currentRow, column: cell.column + 1)
            } else if currentRow + 1 < rowCount {
                // Next row, column 0
                return Cell(row: currentRow + 1, column: 0)
            } else {
                // Past the last body cell
                return nil
            }
        }
    }

    /// Enter moves down one row in the same column.
    /// Returns nil when past the last row.
    static func cellBelow(_ cell: Cell, rowCount: Int) -> Cell? {
        if cell.row == nil {
            // Header to row 0, same column
            return Cell(row: 0, column: cell.column)
        } else {
            // Body row to next row, same column
            let currentRow = cell.row!
            if currentRow + 1 < rowCount {
                return Cell(row: currentRow + 1, column: cell.column)
            } else {
                // Past the last row
                return nil
            }
        }
    }

    /// Update a cell's content. Ignores non-table block IDs.
    static func updateCell(_ doc: BlockDocument, blockID: UUID, cell: Cell, content: InlineText) -> BlockDocument {
        guard let index = doc.index(of: blockID) else { return doc }
        guard case .table(let alignments, var header, var rows) = doc.blocks[index].kind else { return doc }

        if cell.row == nil {
            // Update header cell
            if cell.column < header.count {
                header[cell.column] = content
            }
        } else {
            // Update body cell
            let row = cell.row!
            if row < rows.count && cell.column < rows[row].count {
                rows[row][cell.column] = content
            }
        }

        var updatedDoc = doc
        updatedDoc.blocks[index].kind = .table(alignments: alignments, header: header, rows: rows)
        return updatedDoc
    }

    /// Append a row of empty cells matching the column count. Ignores non-table block IDs.
    static func appendRow(_ doc: BlockDocument, blockID: UUID) -> BlockDocument {
        guard let index = doc.index(of: blockID) else { return doc }
        guard case .table(let alignments, let header, var rows) = doc.blocks[index].kind else { return doc }

        let columnCount = header.count
        let newRow = Array(repeating: InlineText(""), count: columnCount)
        rows.append(newRow)

        var updatedDoc = doc
        updatedDoc.blocks[index].kind = .table(alignments: alignments, header: header, rows: rows)
        return updatedDoc
    }
}
