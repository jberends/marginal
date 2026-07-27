import XCTest
@testable import Marginal

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
}
