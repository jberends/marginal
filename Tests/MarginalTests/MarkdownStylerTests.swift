import XCTest
import AppKit
@testable import Marginal

final class MarkdownStylerTests: XCTestCase {

    func testBoldContentGetsSemiboldFont() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "world")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        // Semibold (600), not full bold -- 600 is the heaviest weight in the product.
        XCTAssertEqual(fontWeight(of: font), NSFont.Weight.semibold.rawValue, accuracy: 0.01)
    }

    private func fontWeight(of font: NSFont?) -> CGFloat {
        let traits = font?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? 0
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

    // Related pre-existing bug found while investigating the bold/blockquote regressions:
    // inlineStyles runs after headers and hard-codes baseFont for its trait conversion, so a
    // bold/italic span nested inside a header shrank back down to editor-content size instead
    // of keeping the header's larger font.
    func testBoldNestedInsideHeaderKeepsHeaderFontSize() {
        let text = "# **Bold Header**"
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "Bold")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(fontWeight(of: font), NSFont.Weight.semibold.rawValue, accuracy: 0.01)
        XCTAssertGreaterThan(font?.pointSize ?? 0, 14, "Bold text nested inside a header must keep the header's larger font size")
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

    func testUnorderedListMarkerGetsBulletDrawingMarkerAndIsHidden() {
        let text = "- one\n- two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let marker = attributed.attribute(.marginalListBulletMarker, at: 0, effectiveRange: nil)
        XCTAssertNotNil(marker, "Marker character must carry the layout-manager key so MarkdownLayoutManager can draw the bullet")
        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear, "The literal marker character must be invisible -- the layout manager draws the actual bullet")
        // The underlying string must stay the literal marker character -- this is the whole point.
        XCTAssertEqual(attributed.string.first, "-")
    }

    func testOrderedListMarkerGetsNoBulletDrawingMarker() {
        let text = "1. one\n2. two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let marker = attributed.attribute(.marginalListBulletMarker, at: 0, effectiveRange: nil)
        XCTAssertNil(marker, "Ordered markers keep their literal digits/period, no bullet drawn")
    }

    // A wrapped continuation line of a list item should indent under the item's text, not
    // wrap back to the paragraph's left margin -- headIndent matches the marker's own
    // rendered width so wrapped lines align exactly under where the content starts.
    func testListItemGetsHangingIndentMatchingMarkerWidth() {
        let text = "- one\n- two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.firstLineHeadIndent, 0, "First visual line starts at the marker, unindented")
        let expectedIndent = ("- " as NSString).size(withAttributes: [.font: baseFont]).width
        XCTAssertEqual(style?.headIndent ?? -1, expectedIndent, accuracy: 0.01, "Wrapped lines must indent to align under the marker's text, not the marker's own width")
    }

    // A lazily-continued line (no blank line separating it from the list item) must be fully
    // indented from its own first character, matching a wrapped continuation line -- not flush
    // left, which is what made "Normal paragraph after..." wrongly hug the margin before this fix.
    func testLazyContinuationLineIsFullyIndentedNotFlushLeft() {
        let text = "- one\ncontinued text"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let continuationLocation = text.distance(from: text.startIndex, to: text.range(of: "continued")!.lowerBound)
        let style = attributed.attribute(.paragraphStyle, at: continuationLocation, effectiveRange: nil) as? NSParagraphStyle
        let expectedIndent = ("- " as NSString).size(withAttributes: [.font: baseFont]).width
        XCTAssertEqual(style?.firstLineHeadIndent ?? -1, expectedIndent, accuracy: 0.01)
        XCTAssertEqual(style?.headIndent ?? -1, expectedIndent, accuracy: 0.01)
    }

    func testOrderedListItemGetsHangingIndentMatchingItsWiderMarker() {
        let text = "10. ten"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let expectedIndent = ("10." as NSString).size(withAttributes: [.font: baseFont]).width + MarkdownStyler.orderedMarkerContentGap(for: baseFont)
        XCTAssertEqual(style?.headIndent ?? -1, expectedIndent, accuracy: 0.01)
    }

    // Regression: each item previously computed its own headIndent from its own marker's width,
    // so "1." and "10." in the same list misaligned their content start.
    func testOrderedListItemsInSameGroupShareIndentOfTheWidestMarker() {
        let text = "1. one\n2. two\n3. three\n4. four\n5. five\n6. six\n7. seven\n8. eight\n9. nine\n10. ten"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let expectedIndent = ("10." as NSString).size(withAttributes: [.font: baseFont]).width + MarkdownStyler.orderedMarkerContentGap(for: baseFont)

        let firstItemLocation = text.distance(from: text.startIndex, to: text.range(of: "1. one")!.lowerBound)
        let tenthItemLocation = text.distance(from: text.startIndex, to: text.range(of: "10. ten")!.lowerBound)
        let firstStyle = attributed.attribute(.paragraphStyle, at: firstItemLocation, effectiveRange: nil) as? NSParagraphStyle
        let tenthStyle = attributed.attribute(.paragraphStyle, at: tenthItemLocation, effectiveRange: nil) as? NSParagraphStyle

        XCTAssertEqual(firstStyle?.headIndent ?? -1, expectedIndent, accuracy: 0.01, "Item 1 must share the group's widest indent, not its own narrower marker width")
        XCTAssertEqual(tenthStyle?.headIndent ?? -1, expectedIndent, accuracy: 0.01)
    }

    // CommonMark/GFM convention: within one contiguous run of ordered items, the displayed
    // number auto-increments from the first item's own stated number, regardless of what
    // digits the source repeats -- matching the "1./1./1." authoring idiom.
    func testRepeatedOneAutoIncrementsWithinAContiguousGroup() {
        let text = "1. one\n1. two\n1. three"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let firstLocation = text.distance(from: text.startIndex, to: text.range(of: "1. one")!.lowerBound)
        let secondLocation = text.distance(from: text.startIndex, to: text.range(of: "1. two")!.lowerBound)
        let thirdLocation = text.distance(from: text.startIndex, to: text.range(of: "1. three")!.lowerBound)

        XCTAssertEqual(attributed.attribute(.marginalOrderedListMarkerText, at: firstLocation, effectiveRange: nil) as? String, "1.")
        XCTAssertEqual(attributed.attribute(.marginalOrderedListMarkerText, at: secondLocation, effectiveRange: nil) as? String, "2.")
        XCTAssertEqual(attributed.attribute(.marginalOrderedListMarkerText, at: thirdLocation, effectiveRange: nil) as? String, "3.")
        // The literal source digit must stay hidden -- the drawn text carries the real value.
        let firstColor = attributed.attribute(.foregroundColor, at: firstLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(firstColor, NSColor.clear)
    }

    func testOrderedGroupStartingAtFiveContinuesFromFive() {
        let text = "5. five\n6. six\n7. seven"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let firstLocation = text.distance(from: text.startIndex, to: text.range(of: "5. five")!.lowerBound)
        let thirdLocation = text.distance(from: text.startIndex, to: text.range(of: "7. seven")!.lowerBound)
        XCTAssertEqual(attributed.attribute(.marginalOrderedListMarkerText, at: firstLocation, effectiveRange: nil) as? String, "5.")
        XCTAssertEqual(attributed.attribute(.marginalOrderedListMarkerText, at: thirdLocation, effectiveRange: nil) as? String, "7.")
    }

    // A blank line breaks the group -- the second list restarts renumbering from its own first
    // item rather than continuing the first list's sequence.
    func testRenumberingResetsAcrossABlankLineGap() {
        let text = "1. one\n2. two\n\n1. three"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let thirdLocation = text.distance(from: text.startIndex, to: text.range(of: "1. three")!.lowerBound)
        XCTAssertEqual(attributed.attribute(.marginalOrderedListMarkerText, at: thirdLocation, effectiveRange: nil) as? String, "1.", "New list after a blank line must restart from its own first item, not continue the previous list's count")
    }

    // Regression: right-aligning the drawn number flush against headIndent (zero gap) relied on
    // trailing-space measurement for spacing and read as the number colliding with the text.
    func testOrderedMarkerReservesAnExplicitGapBeforeContent() {
        let text = "1. one"
        let baseFont = NSFont.systemFont(ofSize: 14)
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let markerWidth = ("1." as NSString).size(withAttributes: [.font: baseFont]).width
        XCTAssertEqual(style?.headIndent ?? -1, markerWidth + MarkdownStyler.orderedMarkerContentGap(for: baseFont), accuracy: 0.01)
    }

    // Regression (the "1.Document" mess): the literal marker text is transparent but was still
    // laid out at its own natural width, so each item's content started at a different x (a
    // "2. " item's content further left than a "10. " item's) while the drawn replacement
    // digits right-aligned against the group's shared headIndent -- overlapping the content.
    // The content itself must land exactly on the group's shared tab stop (headIndent).
    func testOrderedListContentStartsExactlyAtSharedTabStopAcrossMarkerWidths() {
        let text = (1...12).map { "\($0). item" }.joined(separator: "\n")
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 15)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)

        var lineStart = 0
        for number in 1...12 {
            let marker = "\(number). "
            let contentLocation = lineStart + marker.count
            let style = attributed.attribute(.paragraphStyle, at: lineStart, effectiveRange: nil) as? NSParagraphStyle
            let markerRenderedWidth = attributed
                .attributedSubstring(from: NSRange(location: lineStart, length: marker.count))
                .size().width
            let contentX = (style?.firstLineHeadIndent ?? 0) + markerRenderedWidth
            XCTAssertEqual(contentX, style?.headIndent ?? -1, accuracy: 0.5,
                           "Item \(number)'s content must start exactly at the group's shared tab stop")
            lineStart = contentLocation + "item\n".count
        }
    }

    // Nested unordered lists: each deeper level shifts both the marker and its content one
    // more indent slot to the right, and cycles the drawn shape (filled circle / hollow
    // circle / filled square) rather than repeating the same bullet at every depth.
    func testNestedListLevelsGetIncreasingIndentAndCyclingShapes() {
        let text = "- level0\n  - level1\n    - level2\n      - level3"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let unitWidth = ("- " as NSString).size(withAttributes: [.font: baseFont]).width

        let locations = ["level0", "level1", "level2", "level3"].map {
            text.distance(from: text.startIndex, to: text.range(of: $0)!.lowerBound)
        }
        let styles = locations.map { attributed.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle }

        for (level, style) in styles.enumerated() {
            XCTAssertEqual(style?.firstLineHeadIndent ?? -1, CGFloat(level) * unitWidth, accuracy: 0.01, "level \(level) marker position")
            XCTAssertEqual(style?.headIndent ?? -1, CGFloat(level + 1) * unitWidth, accuracy: 0.01, "level \(level) content start")
        }

        let markerLocations = ["- level0", "- level1", "- level2", "- level3"].map {
            text.distance(from: text.startIndex, to: text.range(of: $0)!.lowerBound)
        }
        let shapeIndices = markerLocations.map { attributed.attribute(.marginalListBulletMarker, at: $0, effectiveRange: nil) as? Int }
        XCTAssertEqual(shapeIndices, [0, 1, 2, 0], "Shape must cycle filled circle / hollow circle / filled square / repeat")
    }

    func testNestedListIndentationIsHiddenFromDisplay() {
        let text = "- one\n  - nested"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let nestedMarkerLineStart = text.distance(from: text.startIndex, to: text.range(of: "  - nested")!.lowerBound)
        let font = attributed.attribute(.font, at: nestedMarkerLineStart, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize, "Leading indentation whitespace must be hidden; visual indent comes from paragraph style")
    }

    func testIncompleteTaskCheckboxIsHiddenAndMarkedForLayoutManager() {
        let text = "- [ ] Incomplete task"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let checkboxLocation = text.distance(from: text.startIndex, to: text.range(of: "[ ]")!.lowerBound)
        let color = attributed.attribute(.foregroundColor, at: checkboxLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear, "Literal checkbox brackets must be hidden -- the layout manager draws the actual checkbox")
        let marker = attributed.attribute(.marginalTaskCheckboxMarker, at: checkboxLocation, effectiveRange: nil) as? Bool
        XCTAssertEqual(marker, false)

        // No regular bullet dot should be drawn for a task item.
        let bulletMarker = attributed.attribute(.marginalListBulletMarker, at: 0, effectiveRange: nil)
        XCTAssertNil(bulletMarker, "A task item must not also get the regular bullet shape")

        let taskTextLocation = text.distance(from: text.startIndex, to: text.range(of: "Incomplete task")!.lowerBound)
        let strikethrough = attributed.attribute(.strikethroughStyle, at: taskTextLocation, effectiveRange: nil)
        XCTAssertNil(strikethrough, "Incomplete task text must not be struck through")
    }

    func testHiddenHorizontalRuleLineKeepsAClickableLineHeight() {
        let text = "above\n\n---\n\nbelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let baseFont = NSFont.systemFont(ofSize: 16)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)

        let ruleLocation = text.distance(from: text.startIndex, to: text.range(of: "---")!.lowerBound)
        let style = attributed.attribute(.paragraphStyle, at: ruleLocation, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.minimumLineHeight, baseFont.pointSize * 1.5, "The hidden rule line must keep a normal, clickable height")
    }

    func testCursorOnTaskLineRevealsLiteralCheckboxSource() {
        let text = "- [ ] Incomplete task\nOther line"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let cursor = text.range(of: "Incomplete")!.lowerBound
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)

        let checkboxLocation = text.distance(from: text.startIndex, to: text.range(of: "[ ]")!.lowerBound)
        XCTAssertNil(attributed.attribute(.marginalTaskCheckboxMarker, at: checkboxLocation, effectiveRange: nil), "No checkbox is drawn while the cursor is on the line")
        let markerColor = attributed.attribute(.foregroundColor, at: checkboxLocation, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(markerColor, NSColor.clear, "The literal [ ] source is visible while editing the line")
        let bulletColor = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(bulletColor, NSColor.clear, "The literal - marker is visible while editing the line")
    }

    func testCursorOnOtherLineKeepsTaskCheckboxHidden() {
        // The blank line matters: a directly-following line would be a lazy continuation
        // of the list item, making the cursor count as on the item's own line.
        let text = "- [ ] Incomplete task\n\nOther line"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let cursor = text.range(of: "Other")!.lowerBound
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)

        let checkboxLocation = text.distance(from: text.startIndex, to: text.range(of: "[ ]")!.lowerBound)
        XCTAssertEqual(attributed.attribute(.marginalTaskCheckboxMarker, at: checkboxLocation, effectiveRange: nil) as? Bool, false)
    }

    func testCompletedTaskGetsCheckedMarkerAndStrikethroughText() {
        let text = "- [x] Completed task"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let checkboxLocation = text.distance(from: text.startIndex, to: text.range(of: "[x]")!.lowerBound)
        let marker = attributed.attribute(.marginalTaskCheckboxMarker, at: checkboxLocation, effectiveRange: nil) as? Bool
        XCTAssertEqual(marker, true)

        let taskTextLocation = text.distance(from: text.startIndex, to: text.range(of: "Completed task")!.lowerBound)
        let strikethrough = attributed.attribute(.strikethroughStyle, at: taskTextLocation, effectiveRange: nil) as? Int
        XCTAssertEqual(strikethrough, NSUnderlineStyle.single.rawValue)
        let color = attributed.attribute(.foregroundColor, at: taskTextLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.secondaryLabelColor)
    }

    func testBoldNestedInsideCompletedTaskKeepsBoldFont() {
        let text = "- [x] **Completed** task"
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            listItems: MarkdownParser.parseListItems(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "Completed")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(fontWeight(of: font), NSFont.Weight.semibold.rawValue, accuracy: 0.01, "Nested bold must survive the completed-task color/strikethrough pass, which only touches color and strikethrough, not font")
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

    // A proper gap between the drawn bar and the quoted text, instead of content butting
    // right up against the container edge where the bar is drawn.
    func testBlockquoteContentGetsIndentGapFromTheBar() {
        let text = "> Quoted text"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let baseFont = NSFont.systemFont(ofSize: 14)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(style?.firstLineHeadIndent ?? 0, 0)
        XCTAssertEqual(style?.headIndent, style?.firstLineHeadIndent, "Wrapped lines should stay aligned with the first line's indent")
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
        XCTAssertEqual(fontWeight(of: boldFont), NSFont.Weight.semibold.rawValue, accuracy: 0.01, "Bold inside a blockquote must stay bold (semibold -- the product's heaviest weight)")

        let openingDelimiterLocation = text.distance(from: text.startIndex, to: text.range(of: "**Bold")!.lowerBound)
        let delimiterFont = attributed.attribute(.font, at: openingDelimiterLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(delimiterFont?.pointSize, MarkdownStyler.hiddenDelimiterFontSize, "Bold delimiters inside a blockquote must stay hidden")

        let restLocation = text.distance(from: text.startIndex, to: text.range(of: "rest")!.lowerBound)
        let restFont = attributed.attribute(.font, at: restLocation, effectiveRange: nil) as? NSFont
        XCTAssertFalse(restFont?.fontDescriptor.symbolicTraits.contains(.italic) ?? true, "Notion quotes keep the regular weight -- not italic")
        let restColor = attributed.attribute(.foregroundColor, at: restLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(restColor, NSColor.labelColor, "Notion quotes keep the normal text color -- not gray")
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

    // Notion sizes code at ~85% of the body size; an earlier version rendered it LARGER than
    // body text (pointSize + 1), which read as shouting. The background is no longer a
    // per-glyph .backgroundColor slab -- the layout manager draws a rounded card behind the
    // whole block, keyed off .marginalCodeBlockMarker spanning fences and content.
    func testCodeBlockContentGetsSmallerMonospaceFontAndCardMarker() {
        let text = "```\nplain content\n```"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let contentLocation = text.distance(from: text.startIndex, to: text.range(of: "plain")!.lowerBound)
        let font = attributed.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
        XCTAssertEqual(font?.pointSize ?? 0, 14 * 0.85, accuracy: 0.01, "Code renders at ~85% of body size, matching Notion")
        XCTAssertNotNil(attributed.attribute(.marginalCodeBlockMarker, at: contentLocation, effectiveRange: nil))
        XCTAssertNotNil(attributed.attribute(.marginalCodeBlockMarker, at: 0, effectiveRange: nil), "The card must span the fences too, so they act as vertical padding bands")
        XCTAssertNil(attributed.attribute(.backgroundColor, at: contentLocation, effectiveRange: nil), "No per-glyph background -- the layout manager draws the rounded card")

        // Content is inset from the card's edge, Notion-style.
        let style = attributed.attribute(.paragraphStyle, at: contentLocation, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.firstLineHeadIndent ?? 0, MarkdownStyler.codeBlockContentInset(for: .systemFont(ofSize: 14)), accuracy: 0.01)
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

    func testListItemInsideCodeBlockDoesNotGetBulletMarker() {
        let text = "```\n- item\n```"
        let model = MarkdownDocumentModel(
            listItems: MarkdownParser.parseListItems(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "- item")!.lowerBound)
        let marker = attributed.attribute(.marginalListBulletMarker, at: location, effectiveRange: nil)
        XCTAssertNil(marker, "A '- item' line shown as example code must not get a drawn bullet")
        let color = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.secondaryLabelColor, "Code block content must not be recolored as a list marker")
    }

    func testImageRunCarriesReserveAttributeWhenCursorOutside() {
        let text = "![a](x.png)\nnext"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 13) // in "next", outside the image
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
        var found = false
        attributed.enumerateAttribute(.marginalImage, in: NSRange(location: 0, length: attributed.length)) { v, _, _ in
            if let info = v as? ImageDisplayInfo {
                found = true
                XCTAssertEqual(info.resolvedURL, URL(fileURLWithPath: "/tmp/x.png"))
            }
        }
        XCTAssertTrue(found, "image run must carry .marginalImage when cursor is outside")
    }

    /// The image is now ALWAYS anchored (`.marginalImage` always attached, revealed or not) --
    /// "revealed" means the markup shows as a small dimmed monospace font instead of the hidden
    /// 0.1pt font, not that the image stops drawing. These helpers check the font swap instead
    /// of `.marginalImage` presence/absence.
    private func isActiveSourceFont(_ attributed: NSAttributedString, at location: Int) -> Bool {
        guard let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont else { return false }
        return font.isFixedPitch && font.pointSize > MarkdownStyler.hiddenDelimiterFontSize
    }

    func testImageSourceRevealedWhenCursorInside() {
        let text = "![a](x.png)"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 3) // inside the image markup
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
        XCTAssertNotNil(attributed.attribute(.marginalImage, at: 0, effectiveRange: nil), "image is always anchored, revealed or not")
        XCTAssertTrue(isActiveSourceFont(attributed, at: 0), "raw source is revealed as small dimmed monospace when cursor is inside")
    }

    func testImageSourceRevealedWhenSelectionIntersectsImage() {
        let text = "before ![a](x.png) after"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        // A non-empty selection spanning the whole document (e.g. Cmd-A), which intersects the
        // image's fullRange without the caret being a single point inside it.
        let selection = text.startIndex..<text.endIndex
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: nil, selectedRange: selection, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
        let imageLocation = text.distance(from: text.startIndex, to: text.range(of: "![a](x.png)")!.lowerBound)
        XCTAssertTrue(isActiveSourceFont(attributed, at: imageLocation), "a selection intersecting the image reveals its source")
    }

    func testImageStaysHiddenWhenSelectionDoesNotIntersectImage() {
        let text = "before ![a](x.png) after"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        // A non-empty selection entirely within "after", not touching the image's fullRange.
        let selectionStart = text.range(of: "after")!.lowerBound
        let selection = selectionStart..<text.endIndex
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: nil, selectedRange: selection, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
        let imageLocation = text.distance(from: text.startIndex, to: text.range(of: "![a](x.png)")!.lowerBound)
        XCTAssertNotNil(attributed.attribute(.marginalImage, at: imageLocation, effectiveRange: nil))
        XCTAssertFalse(isActiveSourceFont(attributed, at: imageLocation), "a selection that doesn't intersect the image must not over-reveal it")
    }

    func testImageSourceRevealedWhenSelectionIsCaretInsideImage() {
        let text = "![a](x.png)"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        // A zero-length selection (plain caret) inside the image's markup -- the pre-existing
        // click-to-edit path -- must still reveal, matching testImageSourceRevealedWhenCursorInside.
        let caret = text.index(text.startIndex, offsetBy: 3)
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: caret, selectedRange: caret..<caret, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
        XCTAssertTrue(isActiveSourceFont(attributed, at: 0), "a zero-length selection (caret) inside the image still reveals its source")
    }

    func testImageRunHidesMarkupAndReservesCardBandAbove() {
        let text = "![a](x.png)\nnext"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 13) // in "next", outside the image
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: URL(fileURLWithPath: "/tmp/"))

        let imageRange = text.range(of: "![a](x.png)")!
        let location = text.distance(from: text.startIndex, to: imageRange.lowerBound)

        // The literal "![a](x.png)" markup must be hidden with the same shrunk
        // hidden-delimiter font every other marker uses -- not just left at normal size with
        // color cleared -- since Task 9's drawing depends on the source glyphs being invisible
        // but still present/selectable.
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)

        // The run reserves the full figure-card band (image + caption + padding) ABOVE the source
        // by inflating the line to `band + one source line` and pushing the source glyphs into the
        // bottom slot via a negative baseline offset. (Line height, not paragraphSpacingBefore,
        // because the latter is dropped by TextKit for a first-line image.) The card-tall caret is
        // clamped by MarkdownTextView.drawInsertionPoint, not by keeping the line short here.
        let expectedBand = ImageCardMetrics.bandHeight(captionFontSize: 16 * 0.8)
        XCTAssertGreaterThan(expectedBand, ImageCardMetrics.imageAreaHeight, "band includes caption + padding")
        let paragraphStyle = attributed.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(paragraphStyle?.maximumLineHeight ?? 0, expectedBand, "line inflated to band + a source line")
        XCTAssertEqual(paragraphStyle?.minimumLineHeight ?? 0, paragraphStyle?.maximumLineHeight ?? -1,
                       "min == max so the band height is exact")
        let baselineOffset = attributed.attribute(.baselineOffset, at: location, effectiveRange: nil) as? CGFloat
        XCTAssertEqual(baselineOffset ?? 0, -expectedBand, accuracy: 0.5, "source glyphs pushed into the bottom slot")
    }

    func testInactiveImageReservesSpaceAboveAndHidesMarkupAtNormalLineHeight() {
        let text = "![a](/tmp/x.png)\nnext"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 18) // in "next", image inactive
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: URL(fileURLWithPath: "/tmp/"))

        let expectedBand = ImageCardMetrics.bandHeight(captionFontSize: 16 * 0.8)
        let ps = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(ps?.maximumLineHeight ?? 0, expectedBand, "line inflated to reserve the card band")
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize ?? 99, MarkdownStyler.hiddenDelimiterFontSize, accuracy: 0.001)
        // The caption defaults to the filename stem when alt is empty; here alt is "a".
        let info = attributed.attribute(.marginalImage, at: 0, effectiveRange: nil) as? ImageDisplayInfo
        XCTAssertEqual(info?.caption, "a")
    }

    // The image line is inflated to hold the card, so its raw insertion-point rect is card-tall.
    // MarkdownTextView.drawInsertionPoint clamps it to a normal source-line height at the bottom.
    @MainActor
    func testCaretOnImageLineIsClampedToNormalHeight() {
        let text = "![a](/tmp/x.png)"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: text.startIndex, documentBaseURL: URL(fileURLWithPath: "/tmp/"))

        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        tv.textStorage?.setAttributedString(attributed)
        tv.setSelectedRange(NSRange(location: 3, length: 0)) // inside the image markup

        let band = ImageCardMetrics.bandHeight(captionFontSize: 16 * 0.8)
        // A card-tall raw caret must be shrunk to (rawHeight - band) and moved to the bottom.
        let raw = NSRect(x: 10, y: 5, width: 2, height: band + 20)
        let clamped = tv.clampedImageInsertionRect(raw)
        XCTAssertEqual(clamped.height, 20, accuracy: 0.5, "caret is one source line tall, not card-tall")
        XCTAssertEqual(clamped.maxY, raw.maxY, accuracy: 0.5, "caret sits at the bottom of the fragment")
        XCTAssertLessThan(clamped.height, band, "caret must never be as tall as the card")
    }

    func testImageCaptionFallsBackToFilenameStemWhenAltEmpty() {
        let text = "![](/tmp/holiday.png)"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: nil, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
        let info = attributed.attribute(.marginalImage, at: 0, effectiveRange: nil) as? ImageDisplayInfo
        XCTAssertEqual(info?.caption, "holiday", "empty alt → caption is the filename without extension")
    }

    func testActiveImageShowsSmallDimmedMonospaceSourceAndStillDrawsImage() {
        let text = "![a](/tmp/x.png)"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 3) // inside → active
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: URL(fileURLWithPath: "/tmp/"))

        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertLessThan(font!.pointSize, 16, "active source is smaller than body")
        XCTAssertGreaterThan(font!.pointSize, MarkdownStyler.hiddenDelimiterFontSize, "not the 0.1pt hidden font")
        XCTAssertTrue(font!.isFixedPitch, "active source is monospace")
        let color = attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, .secondaryLabelColor)
        XCTAssertNotNil(attributed.attribute(.marginalImage, at: 0, effectiveRange: nil), "image still drawn when active")
    }

    func testImageWithAbsolutePathResolvesWithoutDocumentBaseURL() {
        let text = "![a](/tmp/abs.png)\nnext"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 20) // in "next", outside the image
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: nil)

        var found = false
        attributed.enumerateAttribute(.marginalImage, in: NSRange(location: 0, length: attributed.length)) { v, _, _ in
            if let info = v as? ImageDisplayInfo {
                found = true
                XCTAssertEqual(info.resolvedURL, URL(fileURLWithPath: "/tmp/abs.png"))
            }
        }
        XCTAssertTrue(found, "an absolute image path must resolve even with no documentBaseURL -- this is the path untitled/draft docs use")
    }

    func testImageWithRelativePathAndNoDocumentBaseURLIsSkipped() {
        let text = "![a](rel.png)\nnext"
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 15) // in "next", outside the image
        let attributed = MarkdownStyler.attributedString(
            for: text, model: model, baseFont: .systemFont(ofSize: 16),
            cursorLocation: cursor, documentBaseURL: nil)

        var found = false
        attributed.enumerateAttribute(.marginalImage, in: NSRange(location: 0, length: attributed.length)) { v, _, _ in
            if v != nil { found = true }
        }
        XCTAssertFalse(found, "an unresolvable relative path with no documentBaseURL must be skipped -- plain text, no half-hidden state")
    }
}

final class MarkdownStylerTableTests: XCTestCase {

    private func model(for text: String) -> MarkdownDocumentModel {
        MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            tables: MarkdownParser.parseTables(in: text)
        )
    }

    // Medium (500), not bold -- Notion's measured header row weight.
    func testTableHeaderRowGetsMediumWeightFont() {
        let text = "| Feature | Notes |\n|---|---|\n| Headings | Levels 1-6 |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "Feature")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        // Asserts the *weight*, not a particular family: the editor's typeface is chosen in
        // EditorFont and has changed once already, but "header row is medium, not bold" is the
        // rule Notion's measured design actually specifies.
        XCTAssertEqual(font, EditorFont.medium(14))

        let bodyLocation = text.distance(from: text.startIndex, to: text.range(of: "Headings")!.lowerBound)
        let bodyFont = attributed.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(bodyFont, NSFont.systemFont(ofSize: 14), "Body rows keep the regular base font")
    }

    func testTablePipesAreHiddenAndSeparatorRowIsFullyHidden() {
        let text = "| A | B |\n|---|---|\n| 1 | 2 |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let pipeLocation = text.distance(from: text.startIndex, to: text.range(of: "|")!.lowerBound)
        let color = attributed.attribute(.foregroundColor, at: pipeLocation, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear)

        let separatorLocation = text.distance(from: text.startIndex, to: text.range(of: "|---|---|")!.lowerBound)
        let separatorFont = attributed.attribute(.font, at: separatorLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(separatorFont?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    // The first column is always left-aligned by default and its slot always starts at x=0, so
    // the kern needed on every row's very first pipe (to reach the shared cellPadding constant)
    // must be identical regardless of that row's own content -- a solid, font-metric-independent
    // check that the kern algorithm is actually computing a shared target position, not just
    // echoing each row's own natural width back at itself.
    func testFirstColumnKernIsIdenticalAcrossRowsRegardlessOfContentLength() {
        let text = "| A | much longer header |\n|---|---|\n| much longer body cell | B |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let headerPipeLocation = text.distance(from: text.startIndex, to: text.range(of: "| A")!.lowerBound)
        let bodyPipeLocation = text.distance(from: text.startIndex, to: text.range(of: "| much longer body")!.lowerBound)
        let headerKern = attributed.attribute(.kern, at: headerPipeLocation, effectiveRange: nil) as? CGFloat
        let bodyKern = attributed.attribute(.kern, at: bodyPipeLocation, effectiveRange: nil) as? CGFloat
        XCTAssertNotNil(headerKern)
        XCTAssertEqual(headerKern, bodyKern, "Column 0 always starts at the same x position, so its leading kern must be identical across rows")
    }

    // Regression (columns drifting right, content crossing grid lines): the kern math never
    // accounted for the hidden pipes' own advance width, so every column's content drifted
    // right by one more pipe-width than the last. Left-aligned cell content must land exactly
    // at its column's grid boundary plus the shared cell padding -- measured from the actual
    // attributed runs (fonts, kerns, hidden delimiters), not assumed.
    func testCellContentStartsExactlyAtColumnBoundaryPlusPadding() {
        let text = "| Feature | Supported | Notes |\n|---|---|---|\n| Headings | Yes | Levels 1-6 |\n| Tables | Yes | Extension in many parsers |"
        let baseFont = NSFont.systemFont(ofSize: 15)
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: baseFont, cursorLocation: nil)
        let padding = MarkdownStyler.tableCellPadding(for: baseFont)
        let ns = text as NSString

        let probes: [(cellText: String, column: Int)] = [
            ("Feature", 0), ("Supported", 1), ("Notes", 2),
            ("Headings", 0), ("Levels 1-6", 2),
            ("Extension in many parsers", 2)
        ]
        for probe in probes {
            let cellLocation = ns.range(of: probe.cellText).location
            let lineRange = ns.lineRange(for: NSRange(location: cellLocation, length: 0))
            guard let gridInfo = attributed.attribute(.marginalTableGridMarker, at: lineRange.location, effectiveRange: nil) as? TableGridInfo else {
                XCTFail("Missing grid info for row containing \(probe.cellText)"); continue
            }
            let renderedX = attributed
                .attributedSubstring(from: NSRange(location: lineRange.location, length: cellLocation - lineRange.location))
                .size().width
            XCTAssertEqual(renderedX, gridInfo.columnBoundaries[probe.column] + padding, accuracy: 0.5,
                           "\(probe.cellText) must start exactly at its column boundary plus padding")
        }
    }

    // The user's exact reported case: an escaped pipe inside a cell must not become a hidden
    // "column boundary" -- it should render as ordinary (visible) text.
    func testEscapedPipeInsideACellStaysVisible() {
        let text = "| Expression | Meaning |\n|---|---|\n| A \\| B | A literal pipe |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let escapedPipeLocation = text.distance(from: text.startIndex, to: text.range(of: "\\|")!.lowerBound) + 1
        let color = attributed.attribute(.foregroundColor, at: escapedPipeLocation, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.clear, "An escaped pipe must stay visible, not be hidden as a column separator")
    }

    // The user's exact reported case: empty cells must not crash or corrupt the grid.
    func testEmptyCellsDoNotCrashAndStillProduceAGrid() {
        let text = "| Column A | Column B | Column C |\n|---|---|---|\n| Value | | Value |\n| | | |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "| | | |")!.lowerBound)
        let gridInfo = attributed.attribute(.marginalTableGridMarker, at: location, effectiveRange: nil) as? TableGridInfo
        XCTAssertEqual(gridInfo?.columnBoundaries.count, 4, "3 columns need 4 boundaries")
    }

    func testBoldNestedInsideTableCellKeepsBoldFont() {
        let text = "| Type | Example |\n|---|---|\n| Bold | **Bold text** |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "Bold text")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false, "Nested bold inside a cell must survive the table pass, which runs before inlineStyles")
    }

    func testGridMarkerDistinguishesHeaderFromBodyRows() {
        let text = "| A |\n|---|\n| 1 |"
        let attributed = MarkdownStyler.attributedString(for: text, model: model(for: text), baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let headerLocation = text.distance(from: text.startIndex, to: text.range(of: "| A |")!.lowerBound)
        let bodyLocation = text.distance(from: text.startIndex, to: text.range(of: "| 1 |")!.lowerBound)
        let headerGrid = attributed.attribute(.marginalTableGridMarker, at: headerLocation, effectiveRange: nil) as? TableGridInfo
        let bodyGrid = attributed.attribute(.marginalTableGridMarker, at: bodyLocation, effectiveRange: nil) as? TableGridInfo
        XCTAssertEqual(headerGrid?.isHeaderRow, true)
        XCTAssertEqual(bodyGrid?.isHeaderRow, false)
    }
}

final class MarkdownStylerEmojiShortcodeTests: XCTestCase {

    func testShortcodeTextIsHiddenAndMarkedForLayoutManager() {
        let text = "Done :white_check_mark: today"
        let model = MarkdownDocumentModel(emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)

        let shortcodeRange = text.range(of: ":white_check_mark:")!
        let location = text.distance(from: text.startIndex, to: shortcodeRange.lowerBound)
        let color = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, NSColor.clear, "Literal shortcode text must be hidden -- the layout manager draws the actual emoji")
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
        let marker = attributed.attribute(.marginalEmojiShortcode, at: location, effectiveRange: nil) as? EmojiGlyphInfo
        XCTAssertEqual(marker?.emoji, "✅")

        // A kern on the run's last character reserves exactly the emoji's own width, rather than
        // the (often much longer) shortcode text's own width leaving a big dead gap around it.
        let lastCharLocation = text.distance(from: text.startIndex, to: text.index(before: shortcodeRange.upperBound))
        let kern = attributed.attribute(.kern, at: lastCharLocation, effectiveRange: nil) as? CGFloat
        XCTAssertNotNil(kern)
        XCTAssertGreaterThan(kern ?? 0, 0)

        // The underlying string must stay the literal shortcode -- copy/paste/export must see it.
        XCTAssertEqual(String(text[shortcodeRange]), ":white_check_mark:")
    }

    func testUnrecognizedShortcodeIsNotHidden() {
        let text = "This is :not_a_real_emoji_alias: here"
        let model = MarkdownDocumentModel(emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: ":not_a_real_emoji_alias:")!.lowerBound)
        let color = attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.clear)
    }
}
