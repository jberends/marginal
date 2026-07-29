import XCTest
@testable import Marginal

final class MarkdownStylesheetTests: XCTestCase {

    func testScreenCSSUsesTheGivenBodySize() {
        let css = MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 18)
        XCTAssertTrue(css.contains("font-size: 18px"), css)
    }

    func testLightAndDarkDifferAndEachCarriesItsOwnPaperColour() {
        let light = MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 16)
        let dark = MarkdownStylesheet.screenCSS(appearance: .dark, bodyPointSize: 16)
        XCTAssertNotEqual(light, dark)
        // Paper, not white / ink, not black — the design system's surfaces.
        XCTAssertTrue(light.contains("#FFFEFC"), light)
        XCTAssertTrue(dark.contains("#1E1E1D"), dark)
        XCTAssertFalse(light.contains("#1E1E1D"), "light variant must not carry dark surfaces")
    }

    // Print is always on white paper, so it never follows the window's appearance.
    func testPrintCSSIsLightAndCarriesPageBreakRules() {
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("#2C2C2B"))
        XCTAssertFalse(MarkdownStylesheet.printCSS.contains("#1E1E1D"))
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("page-break-after: avoid"))
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("12pt"))
    }

    func testDocumentWrapsBodyAndEscapesTitle() {
        let html = MarkdownStylesheet.document(body: "<p>hi</p>", title: "A & B <c>", css: "body{}")
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<title>A &amp; B &lt;c&gt;</title>"), html)
        XCTAssertTrue(html.contains("<body><p>hi</p></body>"), html)
        XCTAssertTrue(html.contains("body{}"))
    }

    // The accent, inline-code and rule colours must come from one place, not be retyped
    // per call site — assert the shared token appears in both stylesheets.
    func testBothStylesheetsUseTheAccentToken() {
        XCTAssertTrue(MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 16).contains("#8E1FCB"))
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("#8E1FCB"))
    }
}
