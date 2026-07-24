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
