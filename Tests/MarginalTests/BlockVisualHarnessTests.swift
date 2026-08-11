import XCTest
import AppKit
@testable import Marginal

/// Not a correctness test -- a diagnostic tool, mirroring the retired `VisualRenderHarnessTests`
/// but rendering the new `BlockEditorViewController` (Live mode) instead of the old
/// MarkdownStyler/MarkdownLayoutManager WYSIWYG pipeline. Renders a document exercising every
/// block kind offscreen to a PNG, so a human can eyeball it against
/// `specs/notion-design-tokens.md`.
final class BlockVisualHarnessTests: XCTestCase {

    @MainActor
    func testRenderSampleForVisualInspection() throws {
        let markdown = """
        # Heading 1

        ## Heading 2

        ### Heading 3

        A paragraph with **bold**, *italic*, ***bold italic***, ~~strikethrough~~, <u>underline</u>, and `inline code`.

        > A quoted line of text in Notion style.

        - First bullet
        - Second bullet
          - Nested bullet

        1. First ordered item
        2. Second ordered item

        - [ ] An open task
        - [x] A completed task

        ---

        ```swift
        func greet(_ name: String) -> String {
            "Hello, \\(name)!"
        }
        ```

        | Feature | Supported | Notes |
        | --- | --- | --- |
        | Headings | Yes | Levels 1-6 |
        | Tables | Yes | Alignment supported |
        """

        let document = MarkdownBlockParser.parse(markdown)
        let baseFont = NSFont.systemFont(ofSize: 16)
        let vc = BlockEditorViewController(document: document, baseFont: baseFont)

        // Host in a never-shown, far-offscreen window so the view has a valid window/graphics
        // context for layout and drawing without ever appearing on the real display -- no
        // makeKeyAndOrderFront, no orderFront, nothing that could touch the real screen.
        let width: CGFloat = 760
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: width, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        vc.view.layoutSubtreeIfNeeded()

        // Grow the view to fit its full stack of block content before capturing -- the scroll
        // view otherwise clips to the window's initial (arbitrary) height.
        //
        // The width has to be pinned *first*: block text wraps to the view's width, so measuring
        // the fitting height at the window's initial width under-measures once the real width
        // re-wraps the text, and the top of the document ends up cropped out of the capture.
        window.setContentSize(NSSize(width: width, height: 600))
        vc.view.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        vc.view.layoutSubtreeIfNeeded()

        // The container's own fitting height is useless here: it holds a scroll view pinned to
        // its edges, and a scroll view is happy at any size regardless of how tall its content
        // is -- which silently cropped the top of the document out of the capture. The real
        // document height is the *scrolled* document view's.
        let documentHeight = vc.view.firstScrollViewDocumentView?.fittingSize.height ?? 0
        let totalHeight = max(ceil(max(documentHeight, vc.view.fittingSize.height)), 600)
        window.setContentSize(NSSize(width: width, height: totalHeight))
        vc.view.frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)
        vc.view.layoutSubtreeIfNeeded()
        vc.view.display()

        guard let bitmap = vc.view.bitmapImageRepForCachingDisplay(in: vc.view.bounds) else {
            XCTFail("Could not create bitmap rep")
            return
        }
        vc.view.cacheDisplay(in: vc.view.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode PNG")
            return
        }

        // App Sandbox restricts writes to arbitrary paths -- the container's own home directory
        // is always writable regardless of entitlements.
        let outputPath = NSHomeDirectory() + "/block-render-preview.png"
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        window.contentViewController = nil
        print("RENDER_PREVIEW_PATH: \(outputPath)")
    }
}

private extension NSView {
    /// The document view of the first `NSScrollView` anywhere in this view's subtree -- the view
    /// whose height is the full laid-out block document, as opposed to the scroll view's own
    /// (arbitrary) viewport height.
    var firstScrollViewDocumentView: NSView? {
        if let scrollView = self as? NSScrollView { return scrollView.documentView }
        for subview in subviews {
            if let found = subview.firstScrollViewDocumentView { return found }
        }
        return nil
    }
}
