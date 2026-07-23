import XCTest
import AppKit
@testable import Marginal

final class MarkdownStylerTests: XCTestCase {

    func testBoldContentGetsBoldFont() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "world")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testHiddenDelimiterUsesTinyFont() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let openingDelimiterLocation = 6 // the first "*" of "**world**"
        let font = attributed.attribute(.font, at: openingDelimiterLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    func testCursorInsideSpanRevealsDelimiterAtFullSize() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 9) // inside "world"
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let openingDelimiterLocation = 6
        let font = attributed.attribute(.font, at: openingDelimiterLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testHeaderContentGetsLargerFontThanBase() {
        let text = "# Title\nBody"
        let model = MarkdownDocumentModel(headers: MarkdownParser.parseHeaders(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let font = attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont // inside "Title"
        XCTAssertGreaterThan(font?.pointSize ?? 0, 14)
    }

    func testStrikethroughContentGetsStrikethroughAttribute() {
        let text = "This is ~~wrong~~"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "wrong")!.lowerBound)
        let style = attributed.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testLinkGetsLinkAttributeAndURL() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "this")!.lowerBound)
        let url = attributed.attribute(.link, at: location, effectiveRange: nil) as? String
        XCTAssertEqual(url, "https://example.com")
    }
}
