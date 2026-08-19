import XCTest
import AppKit
@testable import Marginal

/// Not a correctness test -- a diagnostic tool. Renders markdown through the real
/// MarkdownLayoutManager/NSTextView pipeline into an offscreen bitmap and writes it to disk, so
/// visual regressions can be inspected without touching a visible window or the real display.
final class VisualRenderHarnessTests: XCTestCase {

    @MainActor
    private func renderToPNG(text: String, fontSize: CGFloat = 15, width: CGFloat = 700, cursorLocation: Int? = nil, outputPath: String) throws {
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text),
            tables: MarkdownParser.parseTables(in: text),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text),
            images: MarkdownParser.parseImages(in: text)
        )
        let baseFont = NSFont.systemFont(ofSize: fontSize)
        let cursorIndex = cursorLocation.flatMap { text.index(text.startIndex, offsetBy: $0, limitedBy: text.endIndex) }

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.textContainer?.widthTracksTextView = true

        // Styled against the real text-column width, exactly as DocumentViewController does -- table
        // columns are capped to it, so styling with an unbounded width would render a table the app
        // would never produce.
        let container = textView.textContainer
        let availableWidth = (container.map { $0.size.width - $0.lineFragmentPadding * 2 }) ?? width
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont,
                                                         cursorLocation: cursorIndex,
                                                         availableWidth: availableWidth)
        textView.textStorage?.setAttributedString(attributed)

        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else {
            XCTFail("Missing layout manager/container")
            return
        }
        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height
        let totalHeight = max(ceil(usedHeight + textView.textContainerInset.height * 2), 10)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)

        // Host in a never-shown, far-offscreen window so the view has a valid window/graphics
        // context for layout and drawing without ever appearing on the real display -- no
        // makeKeyAndOrderFront, no orderFront, nothing that could touch the real screen.
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: width, height: totalHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        textView.display()

        guard let bitmap = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            XCTFail("Could not create bitmap rep")
            return
        }
        textView.cacheDisplay(in: textView.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode PNG")
            return
        }
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        window.contentView = nil
    }

    @MainActor
    func testRenderSampleForVisualInspection() throws {
        let text = """
        # Heading 1
        ## Heading 2
        ### Heading 3

        > A quoted line of text in Notion style

        - First bullet
        - Second bullet

        This file tests the following features:

        1. Document headings from level 1 through level 6
        2. Paragraphs and line wrapping
        3. Forced line breaks
        4. Horizontal rules
        5. Bold text
        6. Italic text
        7. Bold and italic text combined
        8. Strikethrough text
        9. Underlined text using HTML
        10. Highlighted text using HTML
        11. Superscript using HTML
        12. Subscript using HTML

        | Feature | Supported | Notes |
        | --- | --- | --- |
        | Headings | Yes | Levels 1-6 |
        | Tables | Yes | Extension in many parsers |
        | Footnotes | Maybe | Depends on parser |

        | Left aligned | Center aligned | Right aligned |
        | :--- | :---: | ---: |
        | Left | Center | Right |
        | A longer value | Medium | 123.45 |

        Some body text with `inline code` for comparison.

        ```yaml
        ---
        title: Markdown Editor Feature Test Suite
        author: Example Author
        date: 2026-07-24
        tags:
          - markdown
          - editor
        draft: false
        ---
        ```

        Text after the code block.
        """
        // App Sandbox restricts writes to arbitrary paths -- the container's own home directory
        // is always writable regardless of entitlements.
        let outputPath = NSHomeDirectory() + "/render-preview.png"
        try renderToPNG(text: text, outputPath: outputPath)
        print("RENDER_PREVIEW_PATH: \(outputPath)")
    }

    /// A table wider than the text column: every cell must wrap inside its own column rather than
    /// spilling back to the left margin, and the grid must enclose the full height of a wrapped row.
    @MainActor
    func testRenderWideTableForVisualInspection() throws {
        let text = """
        ## 2. Scope

        The existing TUI defines the feature closure. KELOTS must cover what it does, and
        `kelots_core` is the layer that exposes those functions to both the web UI and the CLI:

        | Capability | TUI equivalent |
        |---|---|
        | Select a namespace | Change Namespace |
        | Deploy | Set Namespace to `present` |
        | Rolling restart | Reapply Namespace |
        | Tear down | Set Namespace to `absent` |
        | Pause the agent on a namespace | — (new; the incident brake, §5.4) |
        | Status: pods, deployments, services, ingress, events | View Namespace |

        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | 123.45 |
        """
        let outputPath = NSHomeDirectory() + "/render-wide-table.png"
        try renderToPNG(text: text, outputPath: outputPath)
        print("RENDER_WIDE_TABLE_PATH: \(outputPath)")
    }

    @MainActor
    func testRenderNestedListForVisualInspection() throws {
        let text = """
        - dit is een list
        - Dit is listitem 2
        - Dit is listitem 3
             - dit is echt een indented list
             - weten we het zeker?
        """
        let outputPath = NSHomeDirectory() + "/render-nested-list.png"
        try renderToPNG(text: text, outputPath: outputPath)
        print("RENDER_NESTED_LIST_PATH: \(outputPath)")
    }

    @MainActor
    func testRenderImageCardForVisualInspection() throws {
        // A real image so the card shows actual pixels, plus a first-line image (regression) and
        // a missing image (unavailable card) in one sheet.
        let imageURL = NSHomeDirectory() + "/marginal-card-\(UUID().uuidString).png"
        let img = NSImage(size: NSSize(width: 320, height: 180))
        img.lockFocus()
        NSColor(calibratedRed: 0.32, green: 0.28, blue: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 320, height: 180).fill()
        NSColor.white.setFill(); NSRect(x: 40, y: 40, width: 240, height: 100).fill()
        img.unlockFocus()
        try NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: imageURL))
        defer { try? FileManager.default.removeItem(atPath: imageURL) }

        let text = """
        ![Coastline at dusk](\(imageURL))

        Some body text between two figures.

        ![](\(imageURL))

        And a broken one:

        ![missing diagram](/nope/does-not-exist.png)
        """
        let outputPath = NSHomeDirectory() + "/render-image-card.png"
        try renderToPNG(text: text, outputPath: outputPath)
        print("RENDER_CARD_PATH: \(outputPath)")
    }

    /// Renders `text` like `renderToPNG` but keeps the layout alive so the caller can learn WHERE
    /// the `.marginalImage` span's reserved line fragment landed. Returns the cached bitmap plus
    /// that fragment's rect in the bitmap's own pixel coordinates (top-left origin, matching a
    /// flipped text view), so a test can sample inside the image band and outside it.
    @MainActor
    private func renderImagePlacement(text: String, width: CGFloat = 700, cursorInsideImage: Bool = false)
        throws -> (rep: NSBitmapImageRep, fullBandPixels: NSRect, textBandPixels: NSRect) {
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text),
            tables: MarkdownParser.parseTables(in: text),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text),
            images: MarkdownParser.parseImages(in: text)
        )
        let baseFont = NSFont.systemFont(ofSize: 15)
        // Placing the caret inside the image markup reveals the source (active state); the image
        // must keep painting either way.
        let cursorLocation = cursorInsideImage ? model.images.first?.fullRange.lowerBound : nil
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: cursorLocation)

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributed)

        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let storage = textView.textStorage else {
            throw NSError(domain: "test", code: 1)
        }
        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height
        let totalHeight = max(ceil(usedHeight + textView.textContainerInset.height * 2), 10)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)

        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: width, height: totalHeight),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = textView
        textView.display()

        var imageRange = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.marginalImage, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value != nil { imageRange = range; stop.pointee = true }
        }
        guard imageRange.location != NSNotFound,
              let info = storage.attribute(.marginalImage, at: imageRange.location, effectiveRange: nil) as? ImageDisplayInfo
        else { throw NSError(domain: "test", code: 2) }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: imageRange, actualCharacterRange: nil)
        var fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        // The markup line is inflated to `band + one source line`; the card occupies the top
        // `band` region and the source glyphs sit in the slot below it. `used` here marks the top
        // of that source slot (== fragment top + band), i.e. where the reserved card band ends.
        var used = fragment
        used.origin.y += info.displaySize.height
        used.size.height -= info.displaySize.height
        // Container -> view coordinates (the text view is flipped, so y grows downward from top,
        // matching the cached bitmap's top-left pixel origin).
        fragment.origin.x += textView.textContainerInset.width
        fragment.origin.y += textView.textContainerInset.height
        used.origin.x += textView.textContainerInset.width
        used.origin.y += textView.textContainerInset.height

        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            throw NSError(domain: "test", code: 3)
        }
        textView.cacheDisplay(in: textView.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / textView.bounds.height
        let fullBand = NSRect(x: fragment.minX * scale, y: fragment.minY * scale,
                              width: fragment.width * scale, height: fragment.height * scale)
        let textBand = NSRect(x: used.minX * scale, y: used.minY * scale,
                              width: used.width * scale, height: used.height * scale)
        window.contentView = nil
        return (rep, fullBand, textBand)
    }

    /// Lays out `text` (image source revealed) and returns the heights, top-to-bottom, of the line
    /// fragments the `.marginalImage` run spans -- so a test can check that only the first carries
    /// the card band and any wrapped continuation lines are a normal source-line tall.
    @MainActor
    private func imageSourceFragmentHeights(text: String, width: CGFloat) throws -> [CGFloat] {
        let model = MarkdownDocumentModel(images: MarkdownParser.parseImages(in: text))
        let baseFont = NSFont.systemFont(ofSize: 15)
        let cursor = model.images.first?.fullRange.lowerBound   // caret inside → active/revealed
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: cursor)

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributed)
        guard let lm = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage else { throw NSError(domain: "test", code: 1) }
        lm.ensureLayout(for: container)

        var imageRange = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.marginalImage, in: NSRange(location: 0, length: storage.length)) { v, r, stop in
            if v != nil { imageRange = r; stop.pointee = true }
        }
        guard imageRange.location != NSNotFound else { throw NSError(domain: "test", code: 2) }
        let glyphRange = lm.glyphRange(forCharacterRange: imageRange, actualCharacterRange: nil)
        var heights: [CGFloat] = []
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            heights.append(rect.height)
        }
        return heights
    }

    /// Regression: a long image source that WRAPS must keep its wrapped continuation lines a normal
    /// source-line tall. The card band is reserved via the paragraph's (tall) line height, which
    /// applied to every visual line; ImageWrapLineFragmentDelegate shrinks the continuations back.
    @MainActor
    func testWrappedImageSourceContinuationLinesAreNormalHeight() throws {
        // A long alt+path that must wrap at a narrow width in the revealed (monospace) source.
        let text = "![SleufScan-Icon-1024](/Users/jochem/Desktop/SleufScan-Icon-1024-with-a-really-long-name-to-force-wrapping.png)"
        let heights = try imageSourceFragmentHeights(text: text, width: 300)
        XCTAssertGreaterThanOrEqual(heights.count, 2, "the source must wrap into at least two lines at this width")

        let band = ImageCardMetrics.bandHeight(captionFontSize: 15 * 0.8)
        XCTAssertGreaterThan(heights[0], band, "the first line carries the reserved card band")
        for h in heights.dropFirst() {
            XCTAssertLessThan(h, band, "wrapped continuation lines must not carry the card band")
            XCTAssertLessThan(h, 60, "wrapped continuation lines are ~a normal text line tall")
        }
    }

    /// Regression: an image on the FIRST line reserves its full band (and draws its card), the
    /// same as a mid-document image. TextKit drops `paragraphSpacingBefore` on the first
    /// paragraph, so reserving via that (the old approach) left a first-line image with a 0-height
    /// band -- rendering as bare raw markdown. The band is now reserved via line height, which is
    /// honored on the first paragraph too.
    @MainActor
    func testFirstLineImageReservesBandLikeMidDocument() throws {
        let imageURL = NSHomeDirectory() + "/marginal-firstline-\(UUID().uuidString).png"
        let blue = NSImage(size: NSSize(width: 40, height: 40))
        blue.lockFocus(); NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: 40, height: 40).fill(); blue.unlockFocus()
        try NSBitmapImageRep(data: blue.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: imageURL))
        defer { try? FileManager.default.removeItem(atPath: imageURL) }

        let (rep, firstFull, firstText) = try renderImagePlacement(text: "![](\(imageURL))\n\nafter")
        let (_, midFull, midText) = try renderImagePlacement(text: "before\n\n![](\(imageURL))\n\nafter")

        let firstBand = firstText.minY - firstFull.minY
        let midBand = midText.minY - midFull.minY
        XCTAssertGreaterThan(firstBand, 100, "a first-line image must reserve its band, not collapse to 0")
        XCTAssertEqual(firstBand, midBand, accuracy: 2, "first-line band must match a mid-document image's band")

        // And the image actually paints inside that first-line band.
        func hasBlue(inRows rows: Range<Int>) -> Bool {
            let clamped = max(0, rows.lowerBound)..<min(rep.pixelsHigh, rows.upperBound)
            for y in clamped {
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       c.blueComponent > 0.6, c.redComponent < 0.3, c.greenComponent < 0.3 { return true }
                }
            }
            return false
        }
        XCTAssertTrue(hasBlue(inRows: Int(firstFull.minY.rounded())..<Int(firstText.minY.rounded())),
                      "the first-line image must paint inside its reserved band")
    }

    @MainActor
    func testInlineImageIsDrawn() throws {
        // A solid-blue PNG referenced by absolute path (so the styler resolves it with no document
        // base), cursor away from the span so Task 8 attributes it and Task 9 must paint it. The
        // image is on its own paragraph between "before" and "after" text lines. Verifying mere
        // PRESENCE of blue anywhere would pass even if the image drew over the text; this asserts
        // the blue lands INSIDE the reserved line-fragment band and is ABSENT from the text bands
        // above and below it -- guarding the coordinate math that is the point of this task.
        let imageURL = NSHomeDirectory() + "/marginal-blue-\(UUID().uuidString).png"
        let blue = NSImage(size: NSSize(width: 40, height: 40))
        blue.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        blue.unlockFocus()
        let bitmap = NSBitmapImageRep(data: blue.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: imageURL))
        defer { try? FileManager.default.removeItem(atPath: imageURL) }

        let (rep, fullBand, textBand) = try renderImagePlacement(text: "before\n\n![](\(imageURL))\n\nafter")

        func hasBlue(inRows rows: Range<Int>) -> Bool {
            let clamped = max(0, rows.lowerBound)..<min(rep.pixelsHigh, rows.upperBound)
            for y in clamped {
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       c.blueComponent > 0.6, c.redComponent < 0.3, c.greenComponent < 0.3 {
                        return true
                    }
                }
            }
            return false
        }

        let bandTop = Int(fullBand.minY.rounded())
        let bandBottom = Int(fullBand.maxY.rounded())
        // The reserved image space is the leading band ABOVE the markup's text used-rect.
        let reservedBottom = Int(textBand.minY.rounded())
        // (a) The image paints inside its own reserved band (the top region of the fragment).
        XCTAssertTrue(hasBlue(inRows: bandTop..<reservedBottom),
                      "the inline image should paint blue pixels inside its reserved space above the source line")
        // (b) It does NOT bleed into the "before" text band above the block...
        XCTAssertFalse(hasBlue(inRows: 0..<(bandTop - 2)),
                       "no image pixels should appear above the reserved band (over the 'before' line)")
        // ...nor into the "after" text band below it.
        XCTAssertFalse(hasBlue(inRows: (bandBottom + 2)..<rep.pixelsHigh),
                       "no image pixels should appear below the reserved band (over the 'after' line)")
    }

    @MainActor
    func testActiveImageKeepsImageDrawnWithSourceBelow() throws {
        // Cursor inside the image markup -> active/revealed state. The source "![](path)" is shown
        // small and dimmed at the bottom of the fragment; the image must STILL paint in the
        // reserved band above it and must NOT overlap the revealed source line.
        let imageURL = NSHomeDirectory() + "/marginal-blue-active-\(UUID().uuidString).png"
        let blue = NSImage(size: NSSize(width: 40, height: 40))
        blue.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        blue.unlockFocus()
        let bitmap = NSBitmapImageRep(data: blue.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: imageURL))
        defer { try? FileManager.default.removeItem(atPath: imageURL) }

        let (rep, fullBand, textBand) = try renderImagePlacement(
            text: "before\n\n![](\(imageURL))\n\nafter", cursorInsideImage: true)

        func hasBlue(inRows rows: Range<Int>) -> Bool {
            let clamped = max(0, rows.lowerBound)..<min(rep.pixelsHigh, rows.upperBound)
            for y in clamped {
                for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       c.blueComponent > 0.6, c.redComponent < 0.3, c.greenComponent < 0.3 {
                        return true
                    }
                }
            }
            return false
        }

        let bandTop = Int(fullBand.minY.rounded())
        let reservedBottom = Int(textBand.minY.rounded())
        // (a) The image still paints in the active state, inside its reserved band above the source.
        XCTAssertTrue(hasBlue(inRows: bandTop..<reservedBottom),
                      "image stays drawn in its reserved band when its source is revealed")
        // (b) The image does not overlap the revealed source line below the reserved band.
        XCTAssertFalse(hasBlue(inRows: (reservedBottom + 2)..<Int(textBand.maxY.rounded())),
                       "the image must not paint over the revealed source text line")
    }

    /// A missing/unreadable image (e.g. an absolute path the sandbox can no longer read on
    /// reopen) must not leave the reserved band visually empty -- MarkdownLayoutManager draws a
    /// placeholder box (border + "Image unavailable" text) in its place. This asserts the
    /// reserved band is NOT a blank wash of the text view's own background: some pixels differ
    /// noticeably from near-white, which only the placeholder's border/text could have painted.
    @MainActor
    func testMissingImageDrawsPlaceholderInsteadOfBlankBand() throws {
        let missingURL = NSHomeDirectory() + "/marginal-missing-\(UUID().uuidString).png"
        // Deliberately never write anything to missingURL -- it must not exist on disk.

        let (rep, fullBand, textBand) = try renderImagePlacement(text: "before\n\n![](\(missingURL))\n\nafter")

        func hasNonBackgroundPixel(inRows rows: Range<Int>) -> Bool {
            let clamped = max(0, rows.lowerBound)..<min(rep.pixelsHigh, rows.upperBound)
            for y in clamped {
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                        // Near-white background pixels have all components close to 1; anything
                        // meaningfully darker is the placeholder's border, fill tint, or text.
                        if c.redComponent < 0.9 || c.greenComponent < 0.9 || c.blueComponent < 0.9 {
                            return true
                        }
                    }
                }
            }
            return false
        }

        let bandTop = Int(fullBand.minY.rounded())
        let reservedBottom = Int(textBand.minY.rounded())
        XCTAssertTrue(hasNonBackgroundPixel(inRows: bandTop..<reservedBottom),
                      "a missing image should draw a visible placeholder in its reserved band, not leave it blank")
    }
}
