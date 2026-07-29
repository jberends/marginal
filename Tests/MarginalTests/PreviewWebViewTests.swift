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
}
