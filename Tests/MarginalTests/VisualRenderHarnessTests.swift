import XCTest
import AppKit
@testable import Marginal

/// Not a correctness test -- a diagnostic tool. Renders markdown through the real
/// MarkdownLayoutManager/NSTextView pipeline into an offscreen bitmap and writes it to disk, so
/// visual regressions can be inspected without touching a visible window or the real display.
final class VisualRenderHarnessTests: XCTestCase {

    @MainActor
    private func renderToPNG(text: String, fontSize: CGFloat = 15, width: CGFloat = 700, outputPath: String) throws {
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
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: baseFont, cursorLocation: nil)

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        textView.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.textContainer?.widthTracksTextView = true
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
        guard imageRange.location != NSNotFound else { throw NSError(domain: "test", code: 2) }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: imageRange, actualCharacterRange: nil)
        var fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        // The USED rect excludes the paragraphSpacingBefore leading space, so its top edge marks
        // where the reserved image band ends and the markup's text line begins.
        var used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
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
}
