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

    func testLinkDelimitersAreHiddenWhenCursorIsElsewhere() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let openBracketLocation = text.distance(from: text.startIndex, to: text.range(of: "[")!.lowerBound)
        let font = attributed.attribute(.font, at: openBracketLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    func testLinkDelimitersAreRevealedWhenCursorIsInside() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 10) // inside "this"
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let openBracketLocation = text.distance(from: text.startIndex, to: text.range(of: "[")!.lowerBound)
        let font = attributed.attribute(.font, at: openBracketLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testUnorderedListMarkerGetsGlyphSubstitutionAttribute() {
        let text = "- one\n- two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
        XCTAssertNotNil(glyphInfo, "Unordered marker should carry a glyph-substitution attribute")
        // The underlying string must stay the literal marker character -- this is the whole point.
        XCTAssertEqual(attributed.string.first, "-")
    }

    func testOrderedListMarkerGetsNoGlyphSubstitution() {
        let text = "1. one\n2. two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
        XCTAssertNil(glyphInfo, "Ordered markers keep their literal digits/period, no glyph substitution")
    }

    func testInlineCodeGetsMonospaceFontAndBackground() {
        let text = "Use `npm install` now"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "npm")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
        let background = attributed.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(background)
    }

    func testBlockquoteMarkerIsHiddenWhenCursorIsElsewhereAndMarkedForLayoutManager() {
        let text = "> Quoted text"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
        let contentLocation = text.distance(from: text.startIndex, to: text.range(of: "Quoted")!.lowerBound)
        let marker = attributed.attribute(.marginalBlockquoteMarker, at: contentLocation, effectiveRange: nil)
        XCTAssertNotNil(marker, "Content range must carry the layout-manager key so MarkdownLayoutManager can draw the bar")
    }

    func testBlockquoteMarkerIsRevealedWhenCursorIsInside() {
        let text = "> Quoted text"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 5)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    // Regression: the blockquote loop ran after the inlineStyles loop and unconditionally
    // overwrote .font across the whole blockquote content range, clobbering bold (and
    // un-hiding its ** delimiters, since the blanket italic font replaced the hidden-size
    // font). Repro shape matches the user's exact report (bold inside a blockquote).
    func testBoldInsideBlockquoteKeepsBoldFontAndHidesDelimiters() {
        let text = "> **Bold** rest of quote"
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let boldContentLocation = text.distance(from: text.startIndex, to: text.range(of: "Bold")!.lowerBound)
        let boldFont = attributed.attribute(.font, at: boldContentLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false, "Bold inside a blockquote must stay bold")

        let openingDelimiterLocation = text.distance(from: text.startIndex, to: text.range(of: "**Bold")!.lowerBound)
        let delimiterFont = attributed.attribute(.font, at: openingDelimiterLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(delimiterFont?.pointSize, MarkdownStyler.hiddenDelimiterFontSize, "Bold delimiters inside a blockquote must stay hidden")

        let restLocation = text.distance(from: text.startIndex, to: text.range(of: "rest")!.lowerBound)
        let restFont = attributed.attribute(.font, at: restLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(restFont?.fontDescriptor.symbolicTraits.contains(.italic) ?? false, "Non-bold blockquote content stays italic")
    }

    func testHorizontalRuleLineIsHiddenWhenCursorIsElsewhereAndMarkedForLayoutManager() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let ruleLocation = text.distance(from: text.startIndex, to: text.range(of: "---")!.lowerBound)
        let font = attributed.attribute(.font, at: ruleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
        let marker = attributed.attribute(.marginalHorizontalRuleMarker, at: ruleLocation, effectiveRange: nil)
        XCTAssertNotNil(marker, "Rule line must carry the layout-manager key so MarkdownLayoutManager draws the line")
    }

    func testHorizontalRuleLineIsRevealedWhenCursorIsOnIt() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 7)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let ruleLocation = text.distance(from: text.startIndex, to: text.range(of: "---")!.lowerBound)
        let font = attributed.attribute(.font, at: ruleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testCodeBlockContentGetsMonospaceFontAndBackground() {
        let text = "```\nplain content\n```"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let contentLocation = text.distance(from: text.startIndex, to: text.range(of: "plain")!.lowerBound)
        let font = attributed.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
        let background = attributed.attribute(.backgroundColor, at: contentLocation, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(background)
    }

    func testCodeBlockFencesAreHiddenWhenCursorIsElsewhere() {
        let text = "```\nplain content\n```\nafter"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    func testCodeBlockHighlightTokensGetColored() {
        let text = "```\nlet s = \"hi\"\n```"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let stringLocation = text.distance(from: text.startIndex, to: text.range(of: "\"hi\"")!.lowerBound)
        let color = attributed.attribute(.foregroundColor, at: stringLocation, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.labelColor, "The string literal should get a distinct highlight color, not the default text color")
    }

    // MARK: - Code block content must not be reinterpreted by other parsers.
    //
    // These regression tests build a model with BOTH `codeBlocks:` AND another span type
    // parsed from the SAME text, since the bug only manifests when both see the same
    // document (a fenced code block and an unrelated span that happens to land inside it).

    func testLinkInsideCodeBlockDoesNotGetLinkStyling() {
        let text = "```\n[docs](http://example.com)\n```"
        let model = MarkdownDocumentModel(
            links: MarkdownParser.parseLinks(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "docs")!.lowerBound)
        XCTAssertNil(attributed.attribute(.link, at: location, effectiveRange: nil), "A literal link inside a code block must not become a live link")
        let color = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.linkColor, "Code block content must not be recolored as a link")
        let underline = attributed.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int
        XCTAssertNil(underline, "Code block content must not be underlined as a link")
    }

    func testHorizontalRuleInsideCodeBlockDoesNotGetMarkedForLayoutManager() {
        let text = "```\n---\n```"
        let model = MarkdownDocumentModel(
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let ruleLocation = text.distance(from: text.startIndex, to: text.range(of: "---")!.lowerBound)
        let marker = attributed.attribute(.marginalHorizontalRuleMarker, at: ruleLocation, effectiveRange: nil)
        XCTAssertNil(marker, "A '---' shown as example code must not get a drawn divider line")
    }

    func testBlockquoteInsideCodeBlockDoesNotGetMarkedForLayoutManager() {
        let text = "```\n> quoted\n```"
        let model = MarkdownDocumentModel(
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "quoted")!.lowerBound)
        let marker = attributed.attribute(.marginalBlockquoteMarker, at: location, effectiveRange: nil)
        XCTAssertNil(marker, "A '> quoted' line shown as example code must not get a drawn blockquote bar")
    }

    func testStrikethroughInsideCodeBlockDoesNotGetStrikethroughStyling() {
        let text = "```\n~~strikethrough~~\n```"
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "strikethrough")!.lowerBound)
        let style = attributed.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int
        XCTAssertNil(style, "'~~strikethrough~~' shown as example code must not be struck through")
    }

    func testUnderlineInsideCodeBlockDoesNotGetUnderlineStyling() {
        // Underline in this codebase's markdown dialect is written as inline HTML `<u>...</u>`
        // (see MarkdownParser's doc comment), not `__...__` -- double-underscore maps to bold.
        let text = "```\n<u>underline</u>\n```"
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "underline")!.lowerBound)
        let style = attributed.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int
        XCTAssertNil(style, "'<u>underline</u>' shown as example code must not be underlined")
    }

    func testListItemInsideCodeBlockDoesNotGetBulletGlyphSubstitution() {
        let text = "```\n- item\n```"
        let model = MarkdownDocumentModel(
            listItems: MarkdownParser.parseListItems(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "- item")!.lowerBound)
        let glyphInfo = attributed.attribute(.glyphInfo, at: location, effectiveRange: nil) as? NSGlyphInfo
        XCTAssertNil(glyphInfo, "A '- item' line shown as example code must not get bullet glyph substitution")
        let color = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.secondaryLabelColor, "Code block content must not be recolored as a list marker")
    }
}
