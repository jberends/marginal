import XCTest
@testable import Marginal

final class InlineMarkdownTests: XCTestCase {
    func testParseBoldItalicCodeLink() {
        let t = InlineMarkdown.parse("a **b** *i* `c` [l](https://x.y)")
        XCTAssertEqual(t.plainText, "a b i c l")
        XCTAssertEqual(t.runs.first(where: { $0.text == "b" })?.style, .bold)
        XCTAssertEqual(t.runs.first(where: { $0.text == "i" })?.style, .italic)
        XCTAssertEqual(t.runs.first(where: { $0.text == "c" })?.style, .code)
        XCTAssertEqual(t.runs.first(where: { $0.text == "l" })?.linkURL, "https://x.y")
    }
    func testEmojiShortcodeNormalizesToCharacter() {
        XCTAssertEqual(InlineMarkdown.parse("ok :white_check_mark:").plainText, "ok ✅")
    }
    func testSerializeCanonical() {
        var t = InlineText("a ")
        t.append(InlineText(runs: [InlineRun(text: "b", style: .bold)]))
        t.append(InlineText(runs: [InlineRun(text: " ", style: []), InlineRun(text: "l", linkURL: "https://x.y")]))
        XCTAssertEqual(InlineMarkdown.serialize(t), "a **b** [l](https://x.y)")
    }
    func testRoundTripIsIdentity() {
        let sources = ["plain", "**b** mid *i*", "`code` and ~~gone~~ and <u>u</u>", "[l](https://x.y) end"]
        for s in sources {
            XCTAssertEqual(InlineMarkdown.serialize(InlineMarkdown.parse(s)), s, s)
        }
    }
    func testBoldItalicCombinedParsesToBothFlags() {
        let t = InlineMarkdown.parse("***bi***")
        XCTAssertEqual(t.runs, [InlineRun(text: "bi", style: [.bold, .italic])])
        XCTAssertEqual(InlineMarkdown.serialize(t), "***bi***")
    }
}
