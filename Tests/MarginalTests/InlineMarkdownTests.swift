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

    // MARK: - Blocking 3: intraword `_`/`__` must never rewrite the user's file

    /// A snake_case identifier's underscores must never be misdetected as italic -- every
    /// underscore in it has letters on both sides, so parse -> serialize must be a byte-for-byte
    /// identity (no delimiters dropped, nothing re-emitted as `*`).
    func testSnakeCaseWordRoundTripsUnchanged() {
        let source = "my_function_name"
        let parsed = InlineMarkdown.parse(source)
        XCTAssertEqual(parsed.plainText, source, "the underscores must not be consumed as delimiters")
        XCTAssertEqual(InlineMarkdown.serialize(parsed), source)
    }

    /// A bare URL containing underscores must round-trip unchanged for the same reason.
    func testURLWithUnderscoresRoundTripsUnchanged() {
        let source = "https://x.y/a_b_c"
        let parsed = InlineMarkdown.parse(source)
        XCTAssertEqual(parsed.plainText, source)
        XCTAssertEqual(InlineMarkdown.serialize(parsed), source)
    }

    /// The corruption repro: a block whose entire text is a dunder-style identifier must not be
    /// misdetected as bold and rewritten to `**init**` on save. Unlike the snake_case case, there
    /// is no letter *inside* this token immediately touching either `__` run from the outside --
    /// both runs sit at the token's own edges -- so this specifically exercises the stricter,
    /// real-boundary-character guard on the bold pattern (see the comment in
    /// `MarkdownParser.parseInlineStyles`), not just the italic guard.
    func testIsolatedDunderIdentifierRoundTripsUnchanged() {
        let source = "__init__"
        let parsed = InlineMarkdown.parse(source)
        XCTAssertEqual(parsed.plainText, source, "must not be consumed as bold delimiters")
        XCTAssertEqual(InlineMarkdown.serialize(parsed), source, "must not be rewritten to **init**")
    }

    /// Legitimate underscore emphasis at a real word boundary (surrounded by other text, matching
    /// `MarkdownParserTests.testParsesItalicWithSingleUnderscore` / `testParsesBoldWithUnderscores`)
    /// must still work -- the intraword guards must be a pure tightening, not a behavior change
    /// for the happy path.
    func testUnderscoreEmphasisAtWordBoundaryStillParses() {
        let italic = InlineMarkdown.parse("Hello _world_ today")
        XCTAssertTrue(italic.runs.contains { $0.text == "world" && $0.style.contains(.italic) },
                      "expected _world_ surrounded by spaces to still parse as italic, got \(italic.runs)")

        let bold = InlineMarkdown.parse("Hello __world__ today")
        XCTAssertTrue(bold.runs.contains { $0.text == "world" && $0.style.contains(.bold) },
                      "expected __world__ surrounded by spaces to still parse as bold, got \(bold.runs)")
    }
}
