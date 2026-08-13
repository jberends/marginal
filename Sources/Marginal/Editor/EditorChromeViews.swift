import AppKit

/// The left sidebar: a slightly-lighter-than-panel strip with a hairline on its trailing
/// edge, showing the caret's line number very faintly, vertically aligned with the caret's
/// own line -- and nothing at all when the cursor isn't in the text.
final class LineNumberGutterView: NSView {

    /// nil hides the number entirely (cursor not in the text).
    var lineNumber: Int? {
        didSet { needsDisplay = true }
    }

    /// Center of the caret's line, in this view's own (flipped) coordinates.
    var lineCenterY: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var fontSize: CGFloat = 11 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.surfaceGutter.setFill()
        bounds.fill()

        DesignPalette.hairline.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        guard let lineNumber else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: DesignPalette.textFaint
        ]
        let string = "\(lineNumber)" as NSString
        let size = string.size(withAttributes: attributes)
        let point = NSPoint(
            x: bounds.maxX - 9 - size.width,
            y: lineCenterY - size.height / 2
        )
        string.draw(at: point, withAttributes: attributes)
    }
}

/// The bottom status bar: markdown context breadcrumb on the left ("h1 › bold"),
/// line/column on the right ("L 24 · C 13").
/// A document's size, shown in the status bar when the indicator is toggled to counts.
struct DocumentCounts: Equatable {
    let characters: Int
    let words: Int

    /// Words are whitespace-separated runs -- the same thing a word processor counts, and what
    /// someone writing to a word limit means. Characters count the text as written, markdown
    /// markup included, since that is the file's real size.
    init(text: String) {
        characters = text.count
        words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    init(characters: Int, words: Int) {
        self.characters = characters
        self.words = words
    }
}

final class StatusBarView: NSView {

    static let height: CGFloat = 26

    private let breadcrumbLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")

    /// What the right-hand indicator is showing. Click it to swap: the caret's position is what
    /// you want while editing, the document's size is what you want while writing to a length.
    private enum Readout {
        case position
        case counts
    }
    private var readout: Readout = .position
    private var status: CursorStatus?
    private var counts: DocumentCounts?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in [breadcrumbLabel, positionLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = DesignPalette.textMuted
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            breadcrumbLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            breadcrumbLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            positionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            breadcrumbLabel.trailingAnchor.constraint(lessThanOrEqualTo: positionLabel.leadingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(with status: CursorStatus?, counts: DocumentCounts? = nil) {
        self.status = status
        if let counts { self.counts = counts }
        refresh()
    }

    private func refresh() {
        guard let status else {
            breadcrumbLabel.stringValue = ""
            positionLabel.stringValue = ""
            toolTip = nil
            return
        }
        breadcrumbLabel.stringValue = status.path.joined(separator: " › ")
        switch readout {
        case .position:
            positionLabel.stringValue = "L \(status.line) · C \(status.column)"
            toolTip = "Click to show word and character counts"
        case .counts:
            let counts = counts ?? DocumentCounts(characters: 0, words: 0)
            positionLabel.stringValue = "Chars \(counts.characters) · Words \(counts.words)"
            toolTip = "Click to show the cursor position"
        }
    }

    /// The indicator is the only thing in the status bar worth clicking, so the whole bar accepts
    /// the click rather than asking the user to hit an 11pt label exactly.
    override func mouseDown(with event: NSEvent) {
        readout = (readout == .position) ? .counts : .position
        refresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.surfaceGutter.setFill()
        bounds.fill()
        DesignPalette.hairline.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
