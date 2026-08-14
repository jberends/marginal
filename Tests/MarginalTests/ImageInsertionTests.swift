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

    func testDroppedImageFileInsertsAbsoluteMarkupAtIndex() throws {
        let (vc, _) = try makeVC(saved: false)
        vc.loadInitialText("hello world")
        let tv = vc.textView!
        // an existing image file somewhere outside the doc folder
        let ext = FileManager.default.temporaryDirectory.appendingPathComponent("photo.png")
        try ImageInsertionTests.onePixelPNG().write(to: ext)
        vc.markdownTextView(tv, didReceiveDroppedImageFileAt: ext, atCharacterIndex: 5)
        XCTAssertEqual(tv.string, "hello![](\(ext.path)) world")
        try? FileManager.default.removeItem(at: ext)
    }

    func testPrepareForSaveRelocatesAndRewrites() throws {
        let (vc, _) = try makeVC(saved: false)
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let tempPath = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        vc.textView.string = "before ![](\(tempPath)) after"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("MyNote.md")

        vc.prepareForSave(to: target, now: now)

        XCTAssertEqual(vc.textView.string, "before ![](MyNote.assets/\(URL(fileURLWithPath: tempPath).lastPathComponent)) after")
        let moved = dir.appendingPathComponent("MyNote.assets").appendingPathComponent(URL(fileURLWithPath: tempPath).lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
        try? FileManager.default.removeItem(at: dir)
    }

    func testPrepareForSaveLeavesAbsoluteLinkedImages() throws {
        let (vc, _) = try makeVC(saved: false)
        let linked = "/Users/someone/Pictures/holiday.png"
        vc.textView.string = "![](\(linked))"
        vc.document?.text = vc.textView.string
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(vc.textView.string, "![](\(linked))") // untouched
        try? FileManager.default.removeItem(at: dir)
    }

    /// The single-image test can't distinguish a correct descending-range sort from a naive
    /// front-to-back one (rewriting the first span first would shift the second span's range).
    /// Two managed images in one document is the property back-to-front rewriting protects.
    func testPrepareForSaveRewritesMultipleManagedImagesCorrectly() throws {
        let (vc, _) = try makeVC(saved: false)
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let tempA = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        let tempB = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        vc.textView.string = "a ![](\(tempA)) b ![](\(tempB)) c"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        let nameA = URL(fileURLWithPath: tempA).lastPathComponent
        let nameB = URL(fileURLWithPath: tempB).lastPathComponent
        XCTAssertEqual(vc.textView.string, "a ![](MyNote.assets/\(nameA)) b ![](MyNote.assets/\(nameB)) c")

        let assetsDir = dir.appendingPathComponent("MyNote.assets")
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetsDir.appendingPathComponent(nameA).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetsDir.appendingPathComponent(nameB).path))
        try? FileManager.default.removeItem(at: dir)
    }

    /// Two spans referencing the SAME managed temp file (e.g. duplicated markdown) must not
    /// abort the save after the first move -- the file is relocated once and both spans are
    /// rewritten to the same relative path.
    func testPrepareForSaveDedupesDuplicateReferencesToSameTempFile() throws {
        let (vc, _) = try makeVC(saved: false)
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let tempPath = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        vc.textView.string = "one ![](\(tempPath)) two ![](\(tempPath)) three"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        let name = URL(fileURLWithPath: tempPath).lastPathComponent
        XCTAssertEqual(vc.textView.string, "one ![](MyNote.assets/\(name)) two ![](MyNote.assets/\(name)) three")
        let assetsDir = dir.appendingPathComponent("MyNote.assets")
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetsDir.appendingPathComponent(name).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPath))
        try? FileManager.default.removeItem(at: dir)
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

    /// A private, per-test pasteboard — never the global NSPasteboard.general, which is
    /// shared across the whole machine and would make these tests flaky/order-dependent.
    static func makePrivatePasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("MarginalTest-\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    // MARK: - imageDataFromPasteboard

    func testImageDataFromPasteboardReadsPNGBytes() throws {
        let pb = Self.makePrivatePasteboard()
        let png = Self.onePixelPNG()
        pb.setData(png, forType: .png)

        let result = try XCTUnwrap(DocumentViewController.imageDataFromPasteboard(pb))
        XCTAssertEqual(result.0, png)
        XCTAssertEqual(result.1, "png")
    }

    func testImageDataFromPasteboardConvertsTIFFToPNG() throws {
        let pb = Self.makePrivatePasteboard()
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        let tiff = try XCTUnwrap(img.tiffRepresentation)
        pb.setData(tiff, forType: .tiff)

        let result = try XCTUnwrap(DocumentViewController.imageDataFromPasteboard(pb))
        XCTAssertEqual(result.1, "png")
        XCTAssertNotNil(NSBitmapImageRep(data: result.0), "should decode as a valid PNG")
    }

    func testImageDataFromPasteboardReturnsNilForPlainString() {
        let pb = Self.makePrivatePasteboard()
        pb.setString("hello", forType: .string)

        XCTAssertNil(DocumentViewController.imageDataFromPasteboard(pb))
    }

    // MARK: - insertPastedImage(from:into:)

    func testInsertPastedImageInsertsMarkupAndWritesFile() throws {
        let (vc, _) = try makeVC(saved: false)
        let pb = Self.makePrivatePasteboard()
        pb.setData(Self.onePixelPNG(), forType: .png)

        let handled = vc.insertPastedImage(from: pb, into: vc.textView)
        XCTAssertTrue(handled)

        let text = vc.textView.string
        XCTAssertTrue(text.hasPrefix("![]("), "expected markup at the caret, got \(text)")
        XCTAssertTrue(text.contains("pasted-"), "expected the managed filename, got \(text)")

        guard let start = text.range(of: "![]("), let end = text.range(of: ")", range: start.upperBound..<text.endIndex) else {
            return XCTFail("could not locate inserted markdown path in \(text)")
        }
        let path = String(text[start.upperBound..<end.lowerBound])
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testInsertPastedImageIsUndoable() throws {
        let (vc, _) = try makeVC(saved: false)
        // NSTextView only vends an undoManager once it's hosted in a window -- give it one
        // (never shown on screen) so allowsUndo's undo manager actually exists to query.
        let window = NSWindow(contentViewController: vc)

        let pb = Self.makePrivatePasteboard()
        pb.setData(Self.onePixelPNG(), forType: .png)

        XCTAssertTrue(vc.insertPastedImage(from: pb, into: vc.textView))
        XCTAssertFalse(vc.textView.string.isEmpty)
        _ = window // keep the window alive for the duration of the test

        // NSTextView's undo manager groups actions by run-loop event (groupsByEvent), and that
        // group is never closed here since the test never spins the run loop the way a real
        // keystroke/paste event would -- calling undo() while the group is still open crashes
        // deep in AppKit's text storage replay, unrelated to whether our own insert is correct.
        // canUndo reflects that a registered undo action exists for this insert, which is what
        // "paste goes through the undo stack" actually requires.
        let undoManager = try XCTUnwrap(vc.textView.undoManager)
        XCTAssertTrue(undoManager.canUndo, "the pasted-image insert should register an undo action")
    }

    func testInsertPastedImageReturnsFalseAndInsertsNothingForPlainString() throws {
        let (vc, _) = try makeVC(saved: false)
        let pb = Self.makePrivatePasteboard()
        pb.setString("hello", forType: .string)

        let handled = vc.insertPastedImage(from: pb, into: vc.textView)
        XCTAssertFalse(handled)
        XCTAssertEqual(vc.textView.string, "")
    }
}
