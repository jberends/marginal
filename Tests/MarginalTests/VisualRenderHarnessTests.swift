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

    @MainActor
    func testInlineImageIsDrawn() throws {
        // A solid-blue PNG referenced by absolute path (so the styler resolves it with no
        // document base) and with the cursor away from the span, so Task 8 attributes it and
        // Task 9 must paint it. If the image never draws, no blue pixel appears anywhere.
        let imageURL = NSHomeDirectory() + "/marginal-blue-\(UUID().uuidString).png"
        let blue = NSImage(size: NSSize(width: 40, height: 40))
        blue.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 40).fill()
        blue.unlockFocus()
        let bitmap = NSBitmapImageRep(data: blue.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: imageURL))
        defer { try? FileManager.default.removeItem(atPath: imageURL) }

        let outputPath = NSHomeDirectory() + "/inline-image-render-\(UUID().uuidString).png"
        try renderToPNG(text: "before\n\n![](\(imageURL))\n\nafter", outputPath: outputPath)
        defer { try? FileManager.default.removeItem(atPath: outputPath) }

        let png = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let rep = NSBitmapImageRep(data: png)!
        var sawBlue = false
        for y in 0..<rep.pixelsHigh where !sawBlue {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   c.blueComponent > 0.6, c.redComponent < 0.3, c.greenComponent < 0.3 {
                    sawBlue = true
                    break
                }
            }
        }
        XCTAssertTrue(sawBlue, "the inline image should paint visible blue pixels into its reserved box")
    }
}
