import XCTest
@testable import Marginal

final class BlockModelTests: XCTestCase {
    func testSplitInMiddleOfStyledRuns() {
        let text = InlineText(runs: [InlineRun(text: "ab"), InlineRun(text: "cd", style: .bold)])
        let (left, right) = text.split(at: 3)
        XCTAssertEqual(left.runs, [InlineRun(text: "ab"), InlineRun(text: "c", style: .bold)])
        XCTAssertEqual(right.runs, [InlineRun(text: "d", style: .bold)])
    }
    func testSplitAtZeroAndAtEnd() {
        let text = InlineText("abc")
        XCTAssertEqual(text.split(at: 0).0, InlineText(""))
        XCTAssertEqual(text.split(at: 3).1, InlineText(""))
    }
    func testAppendMergesEqualStyledNeighbors() {
        var a = InlineText("ab")
        a.append(InlineText("cd"))
        XCTAssertEqual(a.runs, [InlineRun(text: "abcd")])
    }
    func testInitNormalizesEmptyRuns() {
        let t = InlineText(runs: [InlineRun(text: ""), InlineRun(text: "x")])
        XCTAssertEqual(t.runs, [InlineRun(text: "x")])
    }
    func testReplacingInlineTextIsNoOpForDivider() {
        XCTAssertEqual(BlockKind.divider.replacingInlineText(InlineText("x")), .divider)
        XCTAssertNil(BlockKind.divider.inlineText)
    }
    func testDocumentIndexAndSubscript() {
        let b = Block(kind: .paragraph(InlineText("hi")))
        let doc = BlockDocument(blocks: [b])
        XCTAssertEqual(doc.index(of: b.id), 0)
        XCTAssertEqual(doc[b.id], b)
    }
}
