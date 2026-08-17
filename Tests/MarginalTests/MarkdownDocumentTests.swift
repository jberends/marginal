import XCTest
@testable import Marginal

// @MainActor because NSDocument's initializer (and, on older SDKs, data(ofType:)/read)
// are main-actor-isolated -- older CI toolchains reject nonisolated calls that the
// newest SDK happens to allow.
@MainActor
final class MarkdownDocumentTests: XCTestCase {

    func testWriteThenReadRoundTrip() throws {
        let document = MarkdownDocument()
        document.text = "# Hello\n\nSome **bold** text."

        let data = try document.data(ofType: "net.daringfireball.markdown")

        let readBack = MarkdownDocument()
        try readBack.read(from: data, ofType: "net.daringfireball.markdown")

        XCTAssertEqual(readBack.text, document.text)
    }

    func testReadInvalidUTF8Throws() {
        let document = MarkdownDocument()
        let invalidData = Data([0xFF, 0xFE, 0xFD])
        XCTAssertThrowsError(try document.read(from: invalidData, ofType: "net.daringfireball.markdown"))
    }

    // Multiple open documents group into one window with the native macOS tab bar (iTerm2-style)
    // instead of scattering separate windows; the shared identifier is what lets AppKit join them.
    @MainActor
    func testDocumentWindowsPreferNativeTabbing() {
        let document = MarkdownDocument()
        document.makeWindowControllers()
        let window = document.windowControllers.first?.window
        XCTAssertEqual(window?.tabbingMode, .preferred)
        XCTAssertEqual(window?.tabbingIdentifier, "MarginalDocumentWindow")
        window?.close()
    }

    // Relocating managed temp images must happen only on a genuine user save. Autosave-in-place
    // fires on a draft document before the user ever picks a real location; if prepareForSave ran
    // there too, it would move temp images into the hidden Autosave Information folder and rewrite
    // their paths to something no longer relocatable on the eventual real save.
    func testShouldRelocateImagesOnlyForUserInitiatedSaves() {
        XCTAssertTrue(MarkdownDocument.shouldRelocateImages(for: .saveOperation))
        XCTAssertTrue(MarkdownDocument.shouldRelocateImages(for: .saveAsOperation))
        XCTAssertTrue(MarkdownDocument.shouldRelocateImages(for: .saveToOperation))

        XCTAssertFalse(MarkdownDocument.shouldRelocateImages(for: .autosaveInPlaceOperation))
        XCTAssertFalse(MarkdownDocument.shouldRelocateImages(for: .autosaveElsewhereOperation))
        XCTAssertFalse(MarkdownDocument.shouldRelocateImages(for: .autosaveAsOperation))
    }

    // New documents should propose "Untitled.md", not "Untitled.markdown" -- .md is the
    // extension users expect and the one every other markdown tool defaults to.
    func testDefaultSaveExtensionIsMd() {
        let doc = MarkdownDocument()
        let ext = doc.fileNameExtension(forType: doc.fileType ?? "net.daringfireball.markdown",
                                        saveOperation: .saveOperation)
        XCTAssertEqual(ext, "md")
    }

    // The visible Save-As proposal is governed by prepareSavePanel -> proposedMarkdownFileName,
    // not fileNameExtension(forType:) (the system markdown UTI seeds ".markdown" otherwise).
    func testProposedMarkdownFileNameForcesMdExtension() {
        XCTAssertEqual(MarkdownDocument.proposedMarkdownFileName(from: "Untitled.markdown"), "Untitled.md")
        XCTAssertEqual(MarkdownDocument.proposedMarkdownFileName(from: "Untitled.md"), "Untitled.md")
        XCTAssertEqual(MarkdownDocument.proposedMarkdownFileName(from: "Untitled"), "Untitled.md")
        XCTAssertEqual(MarkdownDocument.proposedMarkdownFileName(from: ""), "Untitled.md")
        XCTAssertEqual(MarkdownDocument.proposedMarkdownFileName(from: "My Notes.MARKDOWN"), "My Notes.md")
        // A dotted base without a markdown extension keeps its base intact.
        XCTAssertEqual(MarkdownDocument.proposedMarkdownFileName(from: "v1.2 draft.markdown"), "v1.2 draft.md")
    }

    // Proves the override is wired: prepareSavePanel rewrites the panel's name field to .md,
    // which is what the user actually sees (the system markdown UTI seeds ".markdown" otherwise).
    @MainActor
    func testPrepareSavePanelRewritesNameFieldToMd() {
        let doc = MarkdownDocument()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled.markdown"
        _ = doc.prepareSavePanel(panel)
        XCTAssertEqual(panel.nameFieldStringValue, "Untitled.md")
    }
}
