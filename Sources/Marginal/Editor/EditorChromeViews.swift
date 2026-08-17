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

    /// Top and height of the caret's whole line fragment, in this view's own (flipped)
    /// coordinates. Drives the vertical extent bar -- a normal line reads as a short tick, an
    /// image "figure card" line as a tall bar, so the gutter shows how much room the line takes.
    var lineTop: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var lineHeight: CGFloat = 0 {
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

        // A faint rounded hairline just right of the number, spanning the line's real height --
        // so a tall image line is visibly tall in the gutter. Kept subtle (textFaint, 1.5pt) so
        // it aids orientation without competing with the number or the page.
        if lineHeight > 1 {
            let barWidth: CGFloat = 1.5
            let barX = bounds.maxX - 5 - barWidth
            let bar = NSRect(x: barX, y: lineTop + 1, width: barWidth, height: max(0, lineHeight - 2))
            DesignPalette.textFaint.setFill()
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}

/// The bottom status bar: markdown context breadcrumb on the left ("h1 › bold"),
/// line/column on the right ("L 24 · C 13").
/// A document's size, plus where the caret sits in it and what is selected -- shown in the status
/// bar when the indicator is toggled to counts. "Chars 23 / 26374" answers "how far in am I?",
/// which a bare total cannot.
struct DocumentCounts: Equatable {
    let characters: Int
    let words: Int
    /// Characters and words before the caret. Zero-width selection, so this is the caret position.
    let caretCharacters: Int
    let caretWords: Int
    /// Characters and words inside the selection; both zero when nothing is selected.
    let selectedCharacters: Int
    let selectedWords: Int

    var hasSelection: Bool { selectedCharacters > 0 }

    /// Words are whitespace-separated runs -- the same thing a word processor counts, and what
    /// someone writing to a word limit means. Characters count the text as written, markdown
    /// markup included, since that is the file's real size.
    private static func wordCount(_ text: Substring) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// `selectedRange` is in UTF-16 units, as it comes from `NSTextView.selectedRange()`.
    init(text: String, selectedRange: NSRange? = nil) {
        characters = text.count
        words = Self.wordCount(text[text.startIndex..<text.endIndex])

        guard let selectedRange,
              let start = Range(NSRange(location: selectedRange.location, length: 0), in: text)?.lowerBound,
              let selection = Range(selectedRange, in: text) else {
            caretCharacters = 0
            caretWords = 0
            selectedCharacters = 0
            selectedWords = 0
            return
        }

        let prefix = text[text.startIndex..<start]
        caretCharacters = prefix.count
        caretWords = Self.wordCount(prefix)

        let selected = text[selection]
        selectedCharacters = selected.count
        selectedWords = Self.wordCount(selected)
    }

    init(characters: Int, words: Int) {
        self.characters = characters
        self.words = words
        caretCharacters = 0
        caretWords = 0
        selectedCharacters = 0
        selectedWords = 0
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
            if counts.hasSelection {
                positionLabel.stringValue = "Selected \(counts.selectedCharacters) / \(counts.characters) chars · \(counts.selectedWords) / \(counts.words) words"
            } else {
                positionLabel.stringValue = "Chars \(counts.caretCharacters) / \(counts.characters) · Words \(counts.caretWords) / \(counts.words)"
            }
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
