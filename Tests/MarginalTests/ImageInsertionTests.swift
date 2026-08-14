import XCTest
@testable import Marginal

@MainActor
final class ImageInsertionTests: XCTestCase {
    /// Builds a real controller + document. `saved` decides untitled vs file-backed.
    func makeVC(saved: Bool) throws -> (DocumentViewController, URL?) {
        let vc = DocumentViewController()
        let doc = MarkdownDocument()
        var url: URL?
        if saved {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("doc-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("MyNote.md")
            try Data("hi".utf8).write(to: url!)
            doc.fileURL = url
        }
        vc.document = doc
        vc.loadView()
        vc.loadInitialText(saved ? "hi" : "")
        return (vc, url)
    }

    func testInsertImageDataUntitledUsesAbsoluteTempPath() throws {
        let (vc, _) = try makeVC(saved: false)
        let png = Self.onePixelPNG()
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let path = try XCTUnwrap(vc.insertImageData(png, sourceExtension: "png", now: now))
        XCTAssertTrue(path.hasPrefix("/"), "untitled → absolute temp path, got \(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testInsertImageDataSavedUsesRelativeAssetsPath() throws {
        let (vc, url) = try makeVC(saved: true)
        let png = Self.onePixelPNG()
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let path = try XCTUnwrap(vc.insertImageData(png, sourceExtension: "png", now: now))
        XCTAssertTrue(path.hasPrefix("MyNote.assets/"), "saved → relative assets path, got \(path)")
        let onDisk = url!.deletingLastPathComponent().appendingPathComponent(path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: onDisk.path))
    }

    static func onePixelPNG() -> Data {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        let tiff = img.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }
}
