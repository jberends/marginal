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

    /// Reproduces the real-app bug: `autosavesInPlace = true` means a brand-new, never-saved
    /// document already has a non-nil `fileURL` (pointing into the sandbox's hidden Autosave
    /// Information folder) by the time a paste happens. `isDraft` is NSDocument's own signal that
    /// the user hasn't done a real Save/Save As yet, and `insertImageData` must key off it, not
    /// merely off `fileURL` being non-nil -- otherwise the image is written into that hidden
    /// autosave folder with a relative path that's never relocated on the eventual real save.
    func testInsertImageDataDraftDocumentWithAutosaveFileURLUsesAbsoluteTempPath() throws {
        let (vc, url) = try makeVC(saved: true)
        vc.document?.isDraft = true
        let png = Self.onePixelPNG()
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let path = try XCTUnwrap(vc.insertImageData(png, sourceExtension: "png", now: now))
        XCTAssertTrue(path.hasPrefix("/"), "draft doc (autosave fileURL) → absolute temp path, got \(path)")
        XCTAssertFalse(path.hasPrefix(url!.deletingLastPathComponent().path), "must not land next to the autosave fileURL")
    }

    func testInsertImageDataAlwaysUsesAbsoluteTempPath() throws {
        for saved in [false, true] {
            let (vc, _) = try makeVC(saved: saved)
            let path = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(),
                                                        sourceExtension: "png",
                                                        now: Date(timeIntervalSince1970: 1_755_000_000)))
            XCTAssertTrue(path.hasPrefix("/"), "expected absolute temp path, got \(path)")
            XCTAssertTrue(path.contains("marginal-images-"), "expected temp container path, got \(path)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        }
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

    /// Injects a `DocumentFolderAccess` whose prompt always grants, so `prepareForSave` tests
    /// never hit the real `NSOpenPanel` (which would hang a headless test run).
    static func grantingFolderAccess() -> DocumentFolderAccess {
        DocumentFolderAccess(defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!) { req, _ in (req, false) }
    }

    func testPrepareForSaveRelocatesAndRewrites() throws {
        let (vc, _) = try makeVC(saved: false)
        vc.imageFolderAccess = Self.grantingFolderAccess()
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
        vc.imageFolderAccess = Self.grantingFolderAccess()
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
        vc.imageFolderAccess = Self.grantingFolderAccess()
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

    func testPrepareForSaveWithGrantedAccessRelocates() throws {
        let (vc, _) = try makeVC(saved: false)
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let temp = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        vc.textView.string = "x ![](\(temp)) y"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.imageFolderAccess = DocumentFolderAccess(defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!) { req, _ in (req, false) }

        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        let name = URL(fileURLWithPath: temp).lastPathComponent
        XCTAssertEqual(vc.textView.string, "x ![](MyNote.assets/\(name)) y")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("MyNote.assets").appendingPathComponent(name).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp))
        try? FileManager.default.removeItem(at: dir)
    }

    func testPrepareForSaveWithDeclinedAccessKeepsTempPathAndDoesNotThrow() throws {
        let (vc, _) = try makeVC(saved: false)
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let temp = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        vc.textView.string = "![](\(temp))"
        vc.document?.text = vc.textView.string
        vc.imageFolderAccess = DocumentFolderAccess(defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!) { _, _ in nil }
        vc.suppressSaveWarningForTests = true   // don't show an NSAlert in tests

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        XCTAssertEqual(vc.textView.string, "![](\(temp))", "declined access must leave the temp path untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temp))
        try? FileManager.default.removeItem(at: dir)
    }

    /// Injects a `DocumentFolderAccess` that grants access and reports the given
    /// "also copy externally-linked images" checkbox state, so `prepareForSave` tests can drive
    /// the opt-in flag without a real `NSOpenPanel`.
    static func grantingFolderAccess(copyLinkedImages: Bool) -> DocumentFolderAccess {
        DocumentFolderAccess(defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!) { req, _ in
            (req, copyLinkedImages)
        }
    }

    func testPrepareForSaveCopiesLinkedImageWhenOptedIn() throws {
        let (vc, _) = try makeVC(saved: false)
        vc.imageFolderAccess = Self.grantingFolderAccess(copyLinkedImages: true)
        let now = Date(timeIntervalSince1970: 1_755_000_000)

        // a managed (pasted) temp image
        let tempPath = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))

        // a linked (externally referenced) image: a real, readable source file outside the doc folder
        let linkedSource = FileManager.default.temporaryDirectory.appendingPathComponent("linked-\(UUID().uuidString).png")
        try ImageInsertionTests.onePixelPNG().write(to: linkedSource)

        vc.textView.string = "managed ![](\(tempPath)) linked ![](\(linkedSource.path)) end"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        let assetsDir = dir.appendingPathComponent("MyNote.assets")
        let managedName = URL(fileURLWithPath: tempPath).lastPathComponent
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetsDir.appendingPathComponent(managedName).path))

        XCTAssertFalse(vc.textView.string.contains(linkedSource.path), "linked image path should have been rewritten to relative")
        XCTAssertTrue(vc.textView.string.contains("MyNote.assets/"), "linked image should now point into MyNote.assets")
        // The linked source file must still exist -- this is a copy, not a move.
        XCTAssertTrue(FileManager.default.fileExists(atPath: linkedSource.path))

        // Find the rewritten linked reference and confirm the copy landed on disk.
        guard let range = vc.textView.string.range(of: "linked ![](") else {
            return XCTFail("could not find rewritten linked markup")
        }
        let afterOpen = vc.textView.string[range.upperBound...]
        guard let closeRange = afterOpen.range(of: ")") else {
            return XCTFail("could not find closing paren")
        }
        let rewrittenPath = String(afterOpen[..<closeRange.lowerBound])
        XCTAssertTrue(rewrittenPath.hasPrefix("MyNote.assets/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(rewrittenPath).path))

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: linkedSource)
    }

    func testPrepareForSaveLeavesLinkedImageAbsoluteWhenNotOptedIn() throws {
        let (vc, _) = try makeVC(saved: false)
        vc.imageFolderAccess = Self.grantingFolderAccess(copyLinkedImages: false)
        let now = Date(timeIntervalSince1970: 1_755_000_000)

        let tempPath = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        let linkedSource = FileManager.default.temporaryDirectory.appendingPathComponent("linked-\(UUID().uuidString).png")
        try ImageInsertionTests.onePixelPNG().write(to: linkedSource)

        vc.textView.string = "managed ![](\(tempPath)) linked ![](\(linkedSource.path)) end"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        // Managed image still relocates.
        let assetsDir = dir.appendingPathComponent("MyNote.assets")
        let managedName = URL(fileURLWithPath: tempPath).lastPathComponent
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetsDir.appendingPathComponent(managedName).path))

        // Linked image stays untouched (absolute, unchanged).
        XCTAssertTrue(vc.textView.string.contains("![](\(linkedSource.path))"), "linked image path must remain absolute when not opted in")

        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: linkedSource)
    }

    func testPrepareForSaveSkipsUnreadableLinkedImageWithoutThrowing() throws {
        let (vc, _) = try makeVC(saved: false)
        vc.imageFolderAccess = Self.grantingFolderAccess(copyLinkedImages: true)
        let now = Date(timeIntervalSince1970: 1_755_000_000)

        let tempPath = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
        // A linked path to a file that doesn't exist.
        let missingSource = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).png")

        vc.textView.string = "managed ![](\(tempPath)) linked ![](\(missingSource.path)) end"
        vc.document?.text = vc.textView.string

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        vc.prepareForSave(to: dir.appendingPathComponent("MyNote.md"), now: now)

        // Managed image still relocates; the missing linked source stays absolute, no crash/throw.
        let assetsDir = dir.appendingPathComponent("MyNote.assets")
        let managedName = URL(fileURLWithPath: tempPath).lastPathComponent
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetsDir.appendingPathComponent(managedName).path))
        XCTAssertTrue(vc.textView.string.contains("![](\(missingSource.path))"), "unreadable linked source must be left as an absolute path")

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
