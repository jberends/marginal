import AppKit

/// Renders one `.table` block as a grid of per-cell `BlockTextView`s (a header row plus body
/// rows) and owns all intra-table navigation (Tab/Shift-Tab across cells, Enter down a column).
/// `BlockTableView` is deliberately the *only* `BlockTextViewDelegate` its cells ever see -- the
/// document-level controller never wires itself directly to a cell's text view, so a cell edit
/// can never accidentally trigger the single-block split/merge semantics (`BlockEditEngine.split`
/// etc.) that a normal paragraph/heading text view would. Instead this view translates every cell
/// event into either pure intra-table focus movement (Tab/Enter between existing cells -- handled
/// entirely here, the document never changes) or one of two callbacks the document-level
/// controller supplies (`onCellEdit`, `onAppendRow`) -- the document itself stays the single
/// source of truth, this view never mutates a detached copy of the table's content.
@MainActor
final class BlockTableView: NSView {
    let blockID: UUID
    private(set) var alignments: [TableAlignment]
    private(set) var columnCount: Int
    /// Number of *body* rows (excludes the header). `TableEditEngine.Cell.row == nil` is the
    /// header; `0..<rowCount` are body rows.
    private(set) var rowCount: Int
    let baseFont: NSFont

    /// Fired when a cell's text changes (both live typing, routed through `NSTextViewDelegate`
    /// below, and a ⌘B-style toggle) -- the controller applies `TableEditEngine.updateCell` and
    /// fires `onDocumentChange`. This view's own cell text storage already shows the edit (the
    /// user just typed it); nothing here re-renders the cell from the callback's result.
    var onCellEdit: ((TableEditEngine.Cell, InlineText) -> Void)?
    /// Fired when Tab is pressed in the last cell (past the last body row's last column) --
    /// `TableEditEngine.nextCell` returned nil. The controller applies `TableEditEngine.appendRow`
    /// to the document, which changes this block's `BlockKind` and so (via
    /// `BlockEditorViewController.diffAndPatch`) rebuilds this view entirely; the *new* instance's
    /// `focus(cell:)` is what actually moves focus into the new row, not this one.
    var onAppendRow: (() -> Void)?

    private struct CellKey: Hashable {
        let row: Int  // -1 = header
        let column: Int
    }

    private var cellViews: [CellKey: BlockTextView] = [:]
    private var gridStack: NSStackView!
    private var columnWidths: [CGFloat] = []

    private static let horizontalPaddingRatio: CGFloat = 0.5625
    private static let verticalPaddingRatio: CGFloat = 0.5
    private static let minimumColumnEms: CGFloat = 3

    init(blockID: UUID, alignments: [TableAlignment], header: [InlineText], rows: [[InlineText]], baseFont: NSFont) {
        self.blockID = blockID
        self.alignments = alignments
        self.columnCount = header.count
        self.rowCount = rows.count
        self.baseFont = baseFont
        super.init(frame: .zero)

        columnWidths = Self.computeColumnWidths(header: header, rows: rows, alignments: alignments, baseFont: baseFont)

        gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.alignment = .leading
        gridStack.spacing = 0
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        // A 1px hairline frame around the grid's own content size (not `self`'s bounds, which the
        // document controller stretches to the full column width -- see
        // `BlockEditorViewController.addArrangedSubview`). Pinned to `gridStack`'s own edges so it
        // tracks the grid exactly regardless of how much extra trailing space `self` has, and
        // sits behind it in z-order so it never paints over the cells' own hairlines.
        let outline = NSView()
        outline.wantsLayer = true
        outline.layer?.borderWidth = 1
        outline.layer?.borderColor = DesignPalette.hairline.cgColor
        outline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outline)
        addSubview(gridStack)

        NSLayoutConstraint.activate([
            gridStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridStack.topAnchor.constraint(equalTo: topAnchor),
            gridStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            gridStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            outline.leadingAnchor.constraint(equalTo: gridStack.leadingAnchor),
            outline.topAnchor.constraint(equalTo: gridStack.topAnchor),
            outline.trailingAnchor.constraint(equalTo: gridStack.trailingAnchor),
            outline.bottomAnchor.constraint(equalTo: gridStack.bottomAnchor)
        ])

        let headerRow = makeRow(texts: header, row: nil, isLastRow: rows.isEmpty)
        gridStack.addArrangedSubview(headerRow)

        for (rowIndex, rowTexts) in rows.enumerated() {
            let isLast = rowIndex == rows.count - 1
            let rowView = makeRow(texts: rowTexts, row: rowIndex, isLastRow: isLast)
            gridStack.addArrangedSubview(rowView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Focus

    func focusFirstCell() {
        focus(cell: TableEditEngine.Cell(row: nil, column: 0))
    }

    @discardableResult
    func focus(cell: TableEditEngine.Cell) -> Bool {
        guard let cellTextView = textView(for: cell) else { return false }
        window?.makeFirstResponder(cellTextView)
        return true
    }

    /// Exposes a cell's text view for the document-level controller (focusing a specific cell by
    /// coordinate) and for tests asserting focus landed on the exact expected coordinate.
    func textView(for cell: TableEditEngine.Cell) -> BlockTextView? {
        cellViews[CellKey(row: cell.row ?? -1, column: cell.column)]
    }

    private func cell(for view: BlockTextView) -> TableEditEngine.Cell? {
        for (key, candidate) in cellViews where candidate === view {
            return TableEditEngine.Cell(row: key.row == -1 ? nil : key.row, column: key.column)
        }
        return nil
    }

    /// Tab order (header columns, then body rows) as a flat list -- used only for Shift-Tab,
    /// since `TableEditEngine` only defines the forward order.
    private func tabOrder() -> [TableEditEngine.Cell] {
        var order: [TableEditEngine.Cell] = (0..<columnCount).map { TableEditEngine.Cell(row: nil, column: $0) }
        for row in 0..<rowCount {
            order.append(contentsOf: (0..<columnCount).map { TableEditEngine.Cell(row: row, column: $0) })
        }
        return order
    }

    private func previousCell(before cell: TableEditEngine.Cell) -> TableEditEngine.Cell? {
        let order = tabOrder()
        guard let index = order.firstIndex(of: cell), index > 0 else { return nil }
        return order[index - 1]
    }

    // MARK: - Row construction

    private func makeRow(texts: [InlineText], row: Int?, isLastRow: Bool) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        var previousContainer: TableCellContainerView?
        var xOffset: CGFloat = 0

        for column in 0..<columnCount {
            let text = column < texts.count ? texts[column] : InlineText()
            let cellTextView = BlockTextView()
            cellTextView.blockID = blockID
            cellTextView.blockDelegate = self
            cellTextView.delegate = self
            let alignment = column < alignments.count ? alignments[column] : .left
            // Every cell renders through the plain `.paragraph` attribute set -- a table has no
            // dedicated `BlockKind` styling path of its own; the header/body weight distinction
            // is applied directly below instead.
            cellTextView.render(text, asKind: .paragraph(text), baseFont: baseFont)
            if row == nil {
                applyHeaderWeight(to: cellTextView)
            }
            cellTextView.alignment = nsAlignment(for: alignment)
            cellTextView.translatesAutoresizingMaskIntoConstraints = false

            let width = column < columnWidths.count ? columnWidths[column] : baseFont.pointSize * Self.minimumColumnEms
            let container = TableCellContainerView(
                textView: cellTextView,
                isHeader: row == nil,
                isLastColumn: column == columnCount - 1,
                isLastRow: isLastRow,
                baseFont: baseFont,
                horizontalPadding: baseFont.pointSize * Self.horizontalPaddingRatio,
                verticalPadding: baseFont.pointSize * Self.verticalPaddingRatio
            )
            container.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(container)

            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: width),
                container.topAnchor.constraint(equalTo: rowView.topAnchor),
                container.bottomAnchor.constraint(equalTo: rowView.bottomAnchor)
            ])
            if let previous = previousContainer {
                container.leadingAnchor.constraint(equalTo: previous.trailingAnchor).isActive = true
            } else {
                container.leadingAnchor.constraint(equalTo: rowView.leadingAnchor).isActive = true
            }
            if column == columnCount - 1 {
                container.trailingAnchor.constraint(equalTo: rowView.trailingAnchor).isActive = true
            }

            previousContainer = container
            xOffset += width
            cellViews[CellKey(row: row ?? -1, column: column)] = cellTextView
        }

        return rowView
    }

    /// Header cells render at `.medium` (500) weight, not the block factory's default -- tables
    /// have no dedicated `BlockKind` rendering path of their own (the factory only knows
    /// paragraph/heading/etc. weights), so this re-applies the medium weight directly over the
    /// plain-paragraph render `render(_:asKind:baseFont:)` already installed.
    private func applyHeaderWeight(to textView: BlockTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let mediumFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)
        storage.addAttribute(.font, value: mediumFont, range: NSRange(location: 0, length: storage.length))
    }

    private func nsAlignment(for alignment: TableAlignment) -> NSTextAlignment {
        switch alignment {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    // MARK: - Column sizing

    /// Each column's width is the natural width of its widest cell (header or body) plus the
    /// cell's own horizontal padding on both sides, floored at a 3em minimum.
    private static func computeColumnWidths(header: [InlineText], rows: [[InlineText]], alignments: [TableAlignment], baseFont: NSFont) -> [CGFloat] {
        let columnCount = header.count
        let horizontalPadding = baseFont.pointSize * horizontalPaddingRatio
        let minimumWidth = baseFont.pointSize * minimumColumnEms

        var widths = Array(repeating: minimumWidth, count: columnCount)
        for column in 0..<columnCount {
            var naturalWidth: CGFloat = 0
            let headerFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)
            naturalWidth = max(naturalWidth, width(of: header[column].plainText, font: headerFont))
            for row in rows where column < row.count {
                naturalWidth = max(naturalWidth, width(of: row[column].plainText, font: baseFont))
            }
            widths[column] = max(minimumWidth, naturalWidth + horizontalPadding * 2)
        }
        return widths
    }

    private static func width(of text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return ceil(attributed.size().width)
    }

}

// MARK: - BlockTextViewDelegate

extension BlockTableView: @preconcurrency BlockTextViewDelegate {
    func blockTextView(_ view: BlockTextView, didEditInlineText text: InlineText) {
        guard let cell = cell(for: view) else { return }
        onCellEdit?(cell, text)
    }

    /// Enter moves down one row in the same column (`TableEditEngine.cellBelow`); past the last
    /// row it's a no-op -- the brief only requires Tab to grow the table.
    func blockTextViewDidPressEnter(_ view: BlockTextView, atOffset offset: Int) {
        guard let cell = cell(for: view), let below = TableEditEngine.cellBelow(cell, rowCount: rowCount) else { return }
        focus(cell: below)
    }

    /// Out of scope for this task (cross-block arrow/backspace navigation into a table) --
    /// deliberately a no-op so a cell backspacing at offset 0 never triggers the single-block
    /// merge semantics a normal paragraph would.
    func blockTextViewDidBackspaceAtStart(_ view: BlockTextView) {}

    func blockTextViewDidPressTab(_ view: BlockTextView, backward: Bool) {
        guard let cell = cell(for: view) else { return }
        if backward {
            if let previous = previousCell(before: cell) {
                focus(cell: previous)
            }
            return
        }
        if let next = TableEditEngine.nextCell(after: cell, columns: columnCount, rowCount: rowCount) {
            focus(cell: next)
        } else {
            onAppendRow?()
        }
    }

    /// Out of scope for this task (focus-move out of a table into a neighboring block).
    func blockTextView(_ view: BlockTextView, moveFocusVertically up: Bool, caretX: CGFloat) {}

    /// Out of scope for this task (selection escaping a table's own bounds).
    func blockTextView(_ view: BlockTextView, selectionEscapedBoundary up: Bool) {}

    /// Out of scope for this task (whole-block selection escalation for table cells).
    func blockTextViewDidPressEscape(_ view: BlockTextView) {}

    /// Out of scope for this task (whole-block selection escalation for table cells).
    func blockTextViewDidReceiveClick(_ view: BlockTextView) {}

    /// A ⌘B/⌘I/⌘U/⌘⇧S toggle inside a cell: re-render the cell's own storage (mirroring
    /// `BlockEditorViewController`'s handling for ordinary blocks) and report the edit the same
    /// way live typing does.
    func blockTextView(_ view: BlockTextView, didToggleStyle text: InlineText, selection: NSRange) {
        view.render(text, asKind: .paragraph(text), baseFont: baseFont)
        if let cell = cell(for: view), cell.row == nil {
            applyHeaderWeight(to: view)
        }
        view.setSelectedRange(selection)
        guard let cell = cell(for: view) else { return }
        onCellEdit?(cell, text)
    }
}

// MARK: - NSTextViewDelegate

extension BlockTableView: NSTextViewDelegate {
    /// Bridges plain character insertion/deletion (which never goes through
    /// `BlockTextViewDelegate`'s command-interception hooks) into `didEditInlineText` -- mirrors
    /// `BlockEditorViewController.textDidChange(_:)` exactly, but scoped to this table's own
    /// cells so a cell edit never reaches the controller's single-block editing path.
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? BlockTextView else { return }
        blockTextView(textView, didEditInlineText: textView.currentInlineText)
    }
}

/// One cell's container: pads its `BlockTextView` by the spec's horizontal/vertical insets and
/// paints the header tint + hairline grid lines. Every cell draws its own bottom/right hairline
/// (skipped on the last row/column, where the outer 1px hairline frame `BlockTableView` draws
/// around the whole grid already provides that edge) so no line is ever double-drawn.
private final class TableCellContainerView: NSView {
    private let isHeader: Bool
    private let isLastColumn: Bool
    private let isLastRow: Bool

    init(textView: BlockTextView, isHeader: Bool, isLastColumn: Bool, isLastRow: Bool, baseFont: NSFont, horizontalPadding: CGFloat, verticalPadding: CGFloat) {
        self.isHeader = isHeader
        self.isLastColumn = isLastColumn
        self.isLastRow = isLastRow
        super.init(frame: .zero)

        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if isHeader {
            context.setFillColor(DesignPalette.surfaceCode.cgColor)
            context.fill(bounds)
        }

        context.setFillColor(DesignPalette.hairline.cgColor)
        if !isLastRow {
            context.fill(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1))
        }
        if !isLastColumn {
            context.fill(CGRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height))
        }
    }
}
