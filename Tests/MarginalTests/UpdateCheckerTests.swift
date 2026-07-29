import XCTest
@testable import Marginal

final class UpdateCheckerTests: XCTestCase {

    func testNewerVersionsCompareAsNewer() {
        XCTAssertTrue(UpdateChecker.isVersion("0.2.0", newerThan: "0.1.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.0", newerThan: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.1"), "Segments compare numerically, not lexically")
        XCTAssertTrue(UpdateChecker.isVersion("1.0.1", newerThan: "1.0"), "A missing segment counts as zero")
    }

    func testEqualAndOlderVersionsDoNotCompareAsNewer() {
        XCTAssertFalse(UpdateChecker.isVersion("0.1.0", newerThan: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", newerThan: "1.0.0"), "Trailing zero segments are equal")
        XCTAssertFalse(UpdateChecker.isVersion("0.9.9", newerThan: "1.0.0"))
    }

    func testReleaseDecodingStripsTagPrefix() throws {
        let json = Data("""
        {"tag_name": "v0.1.0", "html_url": "https://github.com/jberends/marginal/releases/tag/v0.1.0"}
        """.utf8)
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: json)
        XCTAssertEqual(release.version, "0.1.0")
    }
}

final class PDFExporterHTMLTests: XCTestCase {

    @MainActor
    func testPageHTMLContainsRenderedBodyAndEscapedTitle() {
        let html = PDFExporter.pageHTML(markdown: "# Hi\n\nSome **bold** text.", title: "a<b & c")
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<title>a&lt;b &amp; c</title>"))
    }
}
