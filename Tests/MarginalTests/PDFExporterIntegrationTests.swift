import XCTest
import PDFKit
import AppKit
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
        PDFExporter.shared.export(markdown: markdown, title: "Export test", baseURL: nil, to: url) { error in
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

    /// Regression/verification for the file:// subresource loading gap: WKWebView's
    /// loadHTMLString(_:baseURL:) generally does not grant read access to file:// subresources,
    /// so relatively- and absolutely-linked local images previously rendered blank in exported
    /// PDFs. PDFExporter must embed local images as data URIs (like copy-as-HTML already does)
    /// so exported PDFs are self-contained regardless of WebKit's subresource sandboxing.
    @MainActor
    func testExportEmbedsRelativeAndAbsoluteLocalImagesAsRenderedPixels() throws {
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-image-test-\(UUID().uuidString)", isDirectory: true)
        let assetsDir = workDir.appendingPathComponent("Doc.assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let magenta = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let magentaPNG = Self.solidColorPNG(color: magenta, width: 200, height: 120)
        let relativeImageURL = assetsDir.appendingPathComponent("mag.png")
        try magentaPNG.write(to: relativeImageURL)

        let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let greenPNG = Self.solidColorPNG(color: green, width: 200, height: 120)
        let absoluteImageURL = workDir.appendingPathComponent("abs-green.png")
        try greenPNG.write(to: absoluteImageURL)

        let markdown = """
        # Image export test

        ![relative magenta](Doc.assets/mag.png)

        ![absolute green](\(absoluteImageURL.path))
        """

        let docURL = workDir.appendingPathComponent("Doc.md")
        try markdown.write(to: docURL, atomically: true, encoding: .utf8)

        let pdfURL = workDir.appendingPathComponent("Doc.pdf")
        let done = expectation(description: "export completes")
        PDFExporter.shared.export(markdown: markdown, title: "Image export test", baseURL: workDir, to: pdfURL) { error in
            XCTAssertNil(error, "Export reported an error: \(String(describing: error))")
            done.fulfill()
        }
        wait(for: [done], timeout: 30)

        guard let document = PDFDocument(url: pdfURL), let page = document.page(at: 0) else {
            return XCTFail("No readable PDF was written at \(pdfURL.path)")
        }
        let pageBounds = page.bounds(for: .mediaBox)
        let thumb = page.thumbnail(of: NSSize(width: pageBounds.width * 2, height: pageBounds.height * 2), for: .mediaBox)
        let tiff = try XCTUnwrap(thumb.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        // Thresholds are loose enough to tolerate the color-management shift NSBitmapImageRep's
        // colorAt(x:y:) applies (pixels come back in "Generic RGB", not raw sRGB, so a pure
        // sRGB green (0,1,0) reads back around (0.47, 0.98, 0.24) rather than (0,1,0)) while still
        // clearly distinguishing "an image rendered" from "blank white page" (1,1,1).
        XCTAssertTrue(Self.bitmapContainsPixel(rep, matching: { r, g, b in r > 0.6 && g < 0.3 && b > 0.6 }),
                      "Expected magenta pixels from the relatively-linked image to be rendered in the PDF")
        XCTAssertTrue(Self.bitmapContainsPixel(rep, matching: { r, g, b in r < 0.6 && g > 0.9 && b < 0.4 }),
                      "Expected green pixels from the absolutely-linked image to be rendered in the PDF")
    }

    private static func solidColorPNG(color: NSColor, width: Int, height: Int) -> Data {
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    private static func bitmapContainsPixel(_ rep: NSBitmapImageRep, matching: (CGFloat, CGFloat, CGFloat) -> Bool) -> Bool {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let strideX = max(1, width / 200)
        let strideY = max(1, height / 200)
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                if let color = rep.colorAt(x: x, y: y) {
                    if matching(color.redComponent, color.greenComponent, color.blueComponent) {
                        return true
                    }
                }
                x += strideX
            }
            y += strideY
        }
        return false
    }
}
