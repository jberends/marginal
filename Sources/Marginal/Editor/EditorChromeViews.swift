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
final class StatusBarView: NSView {

    static let height: CGFloat = 26

    private let breadcrumbLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")

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

    func update(with status: CursorStatus?) {
        guard let status else {
            breadcrumbLabel.stringValue = ""
            positionLabel.stringValue = ""
            return
        }
        breadcrumbLabel.stringValue = status.path.joined(separator: " › ")
        positionLabel.stringValue = "L \(status.line) · C \(status.column)"
    }

    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.surfaceGutter.setFill()
        bounds.fill()
        DesignPalette.hairline.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
