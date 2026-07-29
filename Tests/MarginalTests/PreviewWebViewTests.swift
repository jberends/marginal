import XCTest
@testable import Marginal

@MainActor
final class PreviewWebViewTests: XCTestCase {

    func testDocumentHTMLCombinesRendererAndStylesheet() {
        let html = PreviewWebView.documentHTML(
            markdown: "# Title\n\nbody",
            title: "notes.md",
            fontSize: 17,
            appearance: .light
        )
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<title>notes.md</title>"), html)
        XCTAssertTrue(html.contains("<h1 data-line=\"1\">Title</h1>"), html)
        XCTAssertTrue(html.contains("font-size: 17px"), html)
        XCTAssertTrue(html.contains("#FFFEFC"), html)
    }

    func testDocumentHTMLFollowsAppearance() {
        let dark = PreviewWebView.documentHTML(markdown: "x", title: "t", fontSize: 16, appearance: .dark)
        XCTAssertTrue(dark.contains("#1E1E1D"), dark)
    }

    // The soft-newline collapse is the whole reason Preview exists — assert it end to end.
    func testHardWrappedParagraphRendersAsOneFlowingParagraph() {
        let html = PreviewWebView.documentHTML(
            markdown: "one\ntwo\nthree",
            title: "t",
            fontSize: 16,
            appearance: .light
        )
        XCTAssertTrue(html.contains("<p data-line=\"1\">one two three</p>"), html)
    }

    func testScrollScriptTargetsTheAnchorForThatLine() {
        let script = PreviewWebView.scrollScript(forSourceLine: 12)
        XCTAssertTrue(script.contains("[data-line=\"12\"]"), script)
        XCTAssertTrue(script.contains("scrollIntoView"), script)
    }

    func testTopmostVisibleLineScriptReadsADataLineAttribute() {
        XCTAssertTrue(PreviewWebView.topmostVisibleLineScript.contains("data-line"))
    }

    // A freshly built view must be usable before any load: no crash, no anchors.
    func testNewViewHasNoAnchorsYet() {
        let view = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(view.blockSourceLines, [])
    }

    func testLoadRecordsTheDocumentsBlockAnchors() {
        let view = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load(markdown: "# T\n\npara\n\n- item\n", title: "t", fontSize: 16, appearance: .light)
        XCTAssertEqual(view.blockSourceLines, [1, 3, 5])
    }

    // Switching into Preview triggers an asynchronous load, so the scroll has to be deferred
    // rather than evaluated against a DOM that does not exist yet.
    func testEnteringPreviewDefersTheScrollUntilTheDocumentLoads() {
        let view = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load(markdown: "# T\n\npara\n\n- item\n", title: "t", fontSize: 16, appearance: .light)
        // The load has not finished yet: the request must be parked, not dropped.
        view.requestScrollToSourceLine(3)
        XCTAssertEqual(view.pendingScrollLineForTesting, 3)
    }

    // A load that arrives after a parked request must invalidate it, so a stale scroll target
    // from the previous document can never land on the new one.
    func testLoadingAgainDiscardsAPendingScroll() {
        let view = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load(markdown: "# A\n\nfirst\n", title: "t", fontSize: 16, appearance: .light)
        view.requestScrollToSourceLine(3)
        view.load(markdown: "# B\n\nsecond\n", title: "t", fontSize: 16, appearance: .light)
        XCTAssertNil(view.pendingScrollLineForTesting)
    }
}
