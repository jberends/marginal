import XCTest
@testable import Marginal

final class InlineAutoformatTests: XCTestCase {
    func testCompletedBoldConverts() {
        let out = InlineAutoformat.convertCompletedPattern(in: InlineText("a **b**"), caret: 7)
        XCTAssertEqual(out?.0.runs, [InlineRun(text: "a "), InlineRun(text: "b", style: .bold)])
        XCTAssertEqual(out?.caret, 3)
    }
    func testIncompleteOrEmptyPatternsDoNotConvert() {
        XCTAssertNil(InlineAutoformat.convertCompletedPattern(in: InlineText("a **b*"), caret: 6))
        XCTAssertNil(InlineAutoformat.convertCompletedPattern(in: InlineText("a ****"), caret: 6))
        XCTAssertNil(InlineAutoformat.convertCompletedPattern(in: InlineText("a *b"), caret: 4))
    }
    func testSingleStarItalicAndBacktickCode() {
        XCTAssertEqual(InlineAutoformat.convertCompletedPattern(in: InlineText("x *i*"), caret: 5)?.0.runs.last,
                       InlineRun(text: "i", style: .italic))
        XCTAssertEqual(InlineAutoformat.convertCompletedPattern(in: InlineText("x `c`"), caret: 5)?.0.runs.last,
                       InlineRun(text: "c", style: .code))
    }
    func testToggleBoldOnRangeAndOff() {
        let once = InlineAutoformat.toggling(InlineText("abc"), range: 1..<2, style: .bold)
        XCTAssertEqual(once.runs, [InlineRun(text: "a"), InlineRun(text: "b", style: .bold), InlineRun(text: "c")])
        XCTAssertEqual(InlineAutoformat.toggling(once, range: 1..<2, style: .bold), InlineText("abc"))
    }
}
