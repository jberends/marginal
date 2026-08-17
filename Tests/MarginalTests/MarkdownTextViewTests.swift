import XCTest
import AppKit
@testable import Marginal

final class MarkdownTextViewTests: XCTestCase {

    private final class RecordingShortcutDelegate: MarkdownTextViewShortcutDelegate {
        var increaseCallCount = 0
        var decreaseCallCount = 0
        func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView) { increaseCallCount += 1 }
        func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView) { decreaseCallCount += 1 }
        func markdownTextViewToggleShowSource(_ textView: MarkdownTextView) {}
        func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedMarkdownFileAt url: URL) {}
        func markdownTextView(_ textView: MarkdownTextView, didReceiveDroppedImageFileAt url: URL, atCharacterIndex characterIndex: Int) {}
        func markdownTextViewInsertPastedImage(_ textView: MarkdownTextView) -> Bool { false }
        func markdownTextViewRequestImageAccess(_ textView: MarkdownTextView, resolvedURL: URL) {}
    }

    private func makeKeyEvent(charactersIgnoringModifiers: String, modifierFlags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: charactersIgnoringModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: 0
        )!
    }

    @MainActor
    private func makeStyledTaskTextView(_ text: String) -> MarkdownTextView {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 16), cursorLocation: nil)
        textView.textStorage?.setAttributedString(attributed)
        return textView
    }

    @MainActor
    func testToggleTaskCheckboxChecksAnIncompleteTask() {
        let text = "- [ ] Unsupported extensions fail gracefully"
        let textView = makeStyledTaskTextView(text)
        let checkboxIndex = (text as NSString).range(of: "[ ]").location

        XCTAssertTrue(textView.toggleTaskCheckbox(atCharacterIndex: checkboxIndex))
        XCTAssertEqual(textView.string, "- [x] Unsupported extensions fail gracefully")
    }

    @MainActor
    func testToggleTaskCheckboxUnchecksACompletedTask() {
        let text = "- [x] Ship it"
        let textView = makeStyledTaskTextView(text)
        let checkboxIndex = (text as NSString).range(of: "[x]").location

        XCTAssertTrue(textView.toggleTaskCheckbox(atCharacterIndex: checkboxIndex))
        XCTAssertEqual(textView.string, "- [ ] Ship it")
    }

    @MainActor
    func testToggleTaskCheckboxIgnoresPlainText() {
        let textView = makeStyledTaskTextView("- [ ] A task")
        let taskTextIndex = ("- [ ] A task" as NSString).range(of: "task").location
        XCTAssertFalse(textView.toggleTaskCheckbox(atCharacterIndex: taskTextIndex), "Only the checkbox marker itself toggles")
        XCTAssertEqual(textView.string, "- [ ] A task")
    }

    @MainActor
    func testCommandPlusIncreasesFontSizeSameAsCommandEquals() {
        let textView = MarkdownTextView()
        let delegate = RecordingShortcutDelegate()
        textView.shortcutDelegate = delegate

        textView.keyDown(with: makeKeyEvent(charactersIgnoringModifiers: "=", modifierFlags: .command))
        XCTAssertEqual(delegate.increaseCallCount, 1)

        textView.keyDown(with: makeKeyEvent(charactersIgnoringModifiers: "+", modifierFlags: [.command, .shift]))
        XCTAssertEqual(delegate.increaseCallCount, 2, "Cmd+Plus (Cmd+Shift+=) should also increase font size")
    }

    @MainActor
    func testPasteboardContainsImageDetectsImagesAndRejectsText() {
        let pngPb = ImageInsertionTests.makePrivatePasteboard()
        pngPb.setData(ImageInsertionTests.onePixelPNG(), forType: .png)
        XCTAssertTrue(MarkdownTextView.pasteboardContainsImage(pngPb), "PNG bytes should be detected as an image")

        let tiffPb = ImageInsertionTests.makePrivatePasteboard()
        let tiffImg = NSImage(size: NSSize(width: 1, height: 1))
        tiffImg.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        tiffImg.unlockFocus()
        tiffPb.setData(tiffImg.tiffRepresentation!, forType: .tiff)
        XCTAssertTrue(MarkdownTextView.pasteboardContainsImage(tiffPb), "TIFF bytes should be detected as an image")

        let urlPb = ImageInsertionTests.makePrivatePasteboard()
        let fileURL = URL(fileURLWithPath: "/tmp/some-photo.png")
        urlPb.writeObjects([fileURL as NSURL])
        XCTAssertTrue(MarkdownTextView.pasteboardContainsImage(urlPb), "An image file URL should be detected as an image")

        let stringPb = ImageInsertionTests.makePrivatePasteboard()
        stringPb.setString("just some text", forType: .string)
        XCTAssertFalse(MarkdownTextView.pasteboardContainsImage(stringPb), "Plain text should not be detected as an image")

        let emptyPb = ImageInsertionTests.makePrivatePasteboard()
        XCTAssertFalse(MarkdownTextView.pasteboardContainsImage(emptyPb), "An empty pasteboard should not be detected as an image")
    }

    @MainActor
    func testPasteboardContainsImageAgreesWithHandlerOnFileURLExtensions() {
        // Validation must accept exactly the same file-URL extensions the paste
        // handler (DocumentViewController.imageDataFromPasteboard) accepts, or a
        // paste can validate as enabled and then silently no-op.
        let pngPb = ImageInsertionTests.makePrivatePasteboard()
        pngPb.writeObjects([URL(fileURLWithPath: "/tmp/some-photo.png") as NSURL])
        XCTAssertTrue(MarkdownTextView.pasteboardContainsImage(pngPb), "A .png file URL is handled, so validation should accept it")

        let tiffPb = ImageInsertionTests.makePrivatePasteboard()
        tiffPb.writeObjects([URL(fileURLWithPath: "/tmp/some-photo.tiff") as NSURL])
        XCTAssertFalse(MarkdownTextView.pasteboardContainsImage(tiffPb), "A .tiff file URL is NOT handled by imageDataFromPasteboard, so validation must not enable paste for it")
    }

    @MainActor
    func testPasteCommandIsEnabledWhenClipboardHasImage() {
        let savedItems = NSPasteboard.general.pasteboardItems?.map { item -> [NSPasteboard.PasteboardType: Data] in
            var dict = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
        defer {
            NSPasteboard.general.clearContents()
            if let savedItems {
                let restoredItems = savedItems.map { dict -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in dict { item.setData(data, forType: type) }
                    return item
                }
                NSPasteboard.general.writeObjects(restoredItems)
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(ImageInsertionTests.onePixelPNG(), forType: .png)

        let textView = MarkdownTextView()
        let menuItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        XCTAssertTrue(textView.validateUserInterfaceItem(menuItem), "Paste should be enabled when the clipboard holds an image")
    }
}
