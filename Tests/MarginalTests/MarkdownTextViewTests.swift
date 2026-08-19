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
    func testTabIndentsCurrentLineByTwoSpaces() {
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = "- item"
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        tv.insertTab(nil)
        XCTAssertEqual(tv.string, "  - item")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 8, length: 0), "caret follows its text right by two")
    }

    @MainActor
    func testShiftTabOutdentsUpToTwoLeadingSpaces() {
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = "    - nested"   // four leading spaces
        tv.setSelectedRange(NSRange(location: 6, length: 0))   // caret on the 'n'
        tv.insertBacktab(nil)
        XCTAssertEqual(tv.string, "  - nested", "removes exactly one level (two spaces)")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 4, length: 0))
    }

    @MainActor
    func testShiftTabWithNoLeadingSpacesIsANoOp() {
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = "- item"
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.insertBacktab(nil)
        XCTAssertEqual(tv.string, "- item")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 3, length: 0))
    }

    @MainActor
    func testTabIndentsEveryLineInAMultiLineSelection() {
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.string = "- a\n- b"
        tv.setSelectedRange(NSRange(location: 0, length: 7))
        tv.insertTab(nil)
        XCTAssertEqual(tv.string, "  - a\n  - b", "both selected lines indent")
    }

    @MainActor
    private func makeTextViewWithSpy() -> (MarkdownTextView, RecordingShortcutDelegate) {
        let textView = MarkdownTextView()
        let spy = RecordingShortcutDelegate()
        textView.shortcutDelegate = spy
        return (textView, spy)
    }

    @MainActor
    func testCommandPlusIncreasesFontSizeSameAsCommandEquals() {
        let (textView, spy) = makeTextViewWithSpy()

        textView.keyDown(with: makeKeyEvent(charactersIgnoringModifiers: "=", modifierFlags: .command))
        XCTAssertEqual(spy.increaseCallCount, 1)

        textView.keyDown(with: makeKeyEvent(charactersIgnoringModifiers: "+", modifierFlags: [.command, .shift]))
        XCTAssertEqual(spy.increaseCallCount, 2, "Cmd+Plus (Cmd+Shift+=) should also increase font size")
    }

    /// Calls keyDown directly, pinning the fallback path in isolation. In the running app the
    /// menu claims this gesture: AppKit masks out .numericPad before comparing modifier flags
    /// against keyEquivalentModifierMask, so the plain [.command] Zoom In item matches numpad
    /// ⌘+ just like main-row ⌘+ (measured -- see "Spike findings" in the View menu design spec).
    /// What this guards is what keyDown would do if that menu item were ever removed.
    @MainActor
    func testCommandNumpadPlusIncreasesFontSize() {
        let (textView, spy) = makeTextViewWithSpy()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command, .numericPad], timestamp: 0, windowNumber: 0,
            context: nil, characters: "+", charactersIgnoringModifiers: "+",
            isARepeat: false, keyCode: 69   // kVK_ANSI_KeypadPlus
        )!
        textView.keyDown(with: event)
        XCTAssertEqual(spy.increaseCallCount, 1)
    }

    /// U+002D hyphen-minus, the character the key actually produces -- not U+2212.
    @MainActor
    func testCommandHyphenDecreasesFontSize() {
        let (textView, spy) = makeTextViewWithSpy()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: 0,
            context: nil, characters: "\u{002D}", charactersIgnoringModifiers: "\u{002D}",
            isARepeat: false, keyCode: 27
        )!
        textView.keyDown(with: event)
        XCTAssertEqual(spy.decreaseCallCount, 1)
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
