import XCTest
@testable import Marginal

@MainActor
final class EditorChromeViewsTests: XCTestCase {

    // MARK: - Status bar

    func testSegmentedControlCarriesAllThreeModesInOrder() {
        let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 600, height: StatusBarView.height))
        let segmented = bar.modeControlForTesting
        XCTAssertEqual(segmented.segmentCount, 3)
        for (index, mode) in EditorMode.allCases.enumerated() {
            XCTAssertEqual(segmented.label(forSegment: index), mode.title)
            XCTAssertNotNil(segmented.image(forSegment: index), "\(mode) has no icon")
        }
    }

    func testSelectedModeRoundTripsThroughTheControl() {
        let bar = StatusBarView(frame: .zero)
        bar.selectedMode = .preview
        XCTAssertEqual(bar.modeControlForTesting.selectedSegment, 2)
        XCTAssertEqual(bar.selectedMode, .preview)
    }

    func testClickingASegmentReportsTheModeOnce() {
        let bar = StatusBarView(frame: .zero)
        var reported: [EditorMode] = []
        bar.onModeChange = { reported.append($0) }
        bar.modeControlForTesting.selectedSegment = 0
        bar.modeControlForTesting.performClick(nil)
        XCTAssertEqual(reported, [.code])
    }

    func testPreviewVariantShowsStatisticsAndHidesTheCaretReadouts() {
        let bar = StatusBarView(frame: .zero)
        bar.update(with: CursorStatus(line: 24, column: 13, path: ["h1", "bold"]))
        bar.isShowingDocumentStatistics = true
        bar.update(with: DocumentStatistics.statistics(for: "one two three"))
        XCTAssertEqual(bar.breadcrumbTextForTesting, "3 words · 1 min read")
        XCTAssertEqual(bar.positionTextForTesting, "")
    }

    func testLeavingPreviewRestoresTheCaretReadouts() {
        let bar = StatusBarView(frame: .zero)
        bar.isShowingDocumentStatistics = true
        bar.update(with: DocumentStatistics.statistics(for: "one"))
        bar.isShowingDocumentStatistics = false
        bar.update(with: CursorStatus(line: 7, column: 3, path: ["h2"]))
        XCTAssertEqual(bar.breadcrumbTextForTesting, "h2")
        XCTAssertEqual(bar.positionTextForTesting, "L 7 · C 3")
    }

    // MARK: - Gutter

    func testGutterHoldsEveryVisibleLineAndMarksTheCurrentOne() {
        let gutter = LineNumberGutterView(frame: NSRect(x: 0, y: 0, width: 44, height: 200))
        gutter.lines = [
            .init(number: 4, centerY: 10, isCurrent: false),
            .init(number: 5, centerY: 30, isCurrent: true),
            .init(number: 6, centerY: 50, isCurrent: false)
        ]
        XCTAssertEqual(gutter.lines.count, 3)
        XCTAssertEqual(gutter.lines.filter(\.isCurrent).map(\.number), [5])
    }

    func testEmptyLinesDrawsNothingAndDoesNotCrash() {
        let gutter = LineNumberGutterView(frame: NSRect(x: 0, y: 0, width: 44, height: 200))
        gutter.lines = []
        gutter.draw(gutter.bounds)   // must not crash
        XCTAssertTrue(gutter.lines.isEmpty)
    }
}
