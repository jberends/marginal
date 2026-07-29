import XCTest
import PDFKit
@testable import Marginal

/// End-to-end: markdown -> HTML -> WKWebView -> paginated PDF on disk.
final class PDFExporterIntegrationTests: XCTestCase {

    @MainActor
    func testExportProducesAReadablePDF() {
        let markdown = """
        # Export test

        Some **bold** text, `inline code`, and a list:

        - one
        - two
        """
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/pdf-export-test.pdf")
        try? FileManager.default.removeItem(at: url)

        let done = expectation(description: "export completes")
        PDFExporter.shared.export(markdown: markdown, title: "Export test", to: url) { error in
            XCTAssertNil(error, "Export reported an error: \(String(describing: error))")
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        guard let document = PDFDocument(url: url) else {
            return XCTFail("No readable PDF was written at \(url.path)")
        }
        XCTAssertGreaterThan(document.pageCount, 0)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("Export test"), "PDF text content should contain the heading")
        try? FileManager.default.removeItem(at: url)
    }
}
