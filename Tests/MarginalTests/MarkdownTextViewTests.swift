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
        func markdownTextViewInsertPastedImage(_ textView: MarkdownTextView) -> Bool { false }
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
}
