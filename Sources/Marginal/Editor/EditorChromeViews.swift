import AppKit

/// The left sidebar: a slightly-lighter-than-panel strip with a hairline on its trailing
/// edge, showing the caret's line number very faintly, vertically aligned with the caret's
/// own line -- and nothing at all when the cursor isn't in the text.
final class LineNumberGutterView: NSView {

    /// One drawn line number: which line, where its text baseline centres, and whether it's the
    /// caret's own line (drawn brighter).
    struct GutterLine: Equatable {
        let number: Int
        let centerY: CGFloat
        let isCurrent: Bool
    }

    /// The line numbers to draw. Empty draws the strip and nothing else — which is what Live
    /// mode wants when the cursor is elsewhere, and what Preview never sees because the whole
    /// gutter hides.
    var lines: [GutterLine] = [] {
        didSet { needsDisplay = true }
    }

    var fontSize: CGFloat = 11 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // AppKit always has a current graphics context during a real drawing pass; calling
        // draw(_:) directly (as a unit test does, with no backing window) does not, and every
        // NSColor.setFill()/NSRect.fill() below traps on a null CGContext. Guarding here keeps
        // that path a harmless no-op instead of a crash, with no effect on real on-screen drawing.
        guard NSGraphicsContext.current != nil else { return }

        DesignPalette.surfaceGutter.setFill()
        bounds.fill()

        DesignPalette.hairline.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        guard !lines.isEmpty else { return }
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: DesignPalette.textMuted
        ]
        let otherAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: DesignPalette.textFaint
        ]
        for line in lines {
            let attributes = line.isCurrent ? currentAttributes : otherAttributes
            let string = "\(line.number)" as NSString
            let size = string.size(withAttributes: attributes)
            string.draw(
                at: NSPoint(x: bounds.maxX - 9 - size.width, y: line.centerY - size.height / 2),
                withAttributes: attributes
            )
        }
    }
}

/// The bottom status bar: markdown context breadcrumb on the left ("h1 › bold"),
/// line/column on the right ("L 24 · C 13").
final class StatusBarView: NSView {

    static let height: CGFloat = 26

    private let breadcrumbLabel = NSTextField(labelWithString: "")
    private let positionLabel = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl()

    /// Called when the user picks a mode in the control.
    var onModeChange: ((EditorMode) -> Void)?

    /// In Preview there is no caret, so the breadcrumb slot carries word count / reading time
    /// and the line-column slot stays empty.
    var isShowingDocumentStatistics = false

    var selectedMode: EditorMode {
        get {
            let index = modeControl.selectedSegment
            guard EditorMode.allCases.indices.contains(index) else { return .live }
            return EditorMode.allCases[index]
        }
        set {
            modeControl.selectedSegment = EditorMode.allCases.firstIndex(of: newValue) ?? 1
        }
    }

    var modeControlForTesting: NSSegmentedControl { modeControl }
    var breadcrumbTextForTesting: String { breadcrumbLabel.stringValue }
    var positionTextForTesting: String { positionLabel.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in [breadcrumbLabel, positionLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = DesignPalette.textMuted
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.segmentStyle = .texturedRounded
        modeControl.trackingMode = .selectOne
        modeControl.segmentCount = EditorMode.allCases.count
        modeControl.controlSize = .small
        modeControl.font = NSFont.systemFont(ofSize: 10)
        for (index, mode) in EditorMode.allCases.enumerated() {
            modeControl.setLabel(mode.title, forSegment: index)
            modeControl.setImage(
                NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title),
                forSegment: index
            )
            modeControl.setImageScaling(.scaleProportionallyDown, forSegment: index)
            modeControl.setWidth(0, forSegment: index)   // 0 = size to fit
        }
        modeControl.selectedSegment = EditorMode.allCases.firstIndex(of: .live) ?? 1
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged(_:))
        addSubview(modeControl)

        NSLayoutConstraint.activate([
            breadcrumbLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            breadcrumbLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            modeControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            modeControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            positionLabel.trailingAnchor.constraint(equalTo: modeControl.leadingAnchor, constant: -12),
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            breadcrumbLabel.trailingAnchor.constraint(lessThanOrEqualTo: positionLabel.leadingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        onModeChange?(selectedMode)
    }

    func update(with status: CursorStatus?) {
        guard !isShowingDocumentStatistics else { return }
        guard let status else {
            breadcrumbLabel.stringValue = ""
            positionLabel.stringValue = ""
            return
        }
        breadcrumbLabel.stringValue = status.path.joined(separator: " › ")
        positionLabel.stringValue = "L \(status.line) · C \(status.column)"
    }

    /// Preview's readout: word count and reading time in place of the caret breadcrumb.
    func update(with statistics: DocumentStatistics) {
        breadcrumbLabel.stringValue = statistics.statusText
        positionLabel.stringValue = ""
    }

    override func draw(_ dirtyRect: NSRect) {
        DesignPalette.surfaceGutter.setFill()
        bounds.fill()
        DesignPalette.hairline.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
