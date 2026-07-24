# Marginal Phase 2: Formatting Engine Completion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the markdown formatting Phase 1 left undone (inline code, fenced code blocks with basic heuristic highlighting, single-level blockquotes, horizontal rules) and fix four real gaps found through direct use of the running app (links never hid their `[]()` syntax, list markers never became visual bullets, ⌘+ didn't alias to font-increase, and cursor-reveal let adjacent spans both reveal at a shared boundary).

**Architecture:** Extends Phase 1's exact pattern — pure `MarkdownParser` functions (`string -> spans`), `MarkdownStyler` (spans + cursor -> `NSAttributedString` attributes), `CursorRevealController` (which spans does the cursor reveal). Two genuinely new techniques, both de-risked with a compiled spike before this plan was written: (1) `NSGlyphInfo` substitutes the rendered glyph for a character without changing the underlying string (used for list bullets); (2) a custom `NSLayoutManager` subclass overriding `drawBackground(forGlyphRange:at:)` draws paragraph-level decorations (blockquote left bar, horizontal rule line) keyed off custom attribute keys — proven to correctly span multi-line wrapped paragraphs. `NSTextAttachment` was rejected for the horizontal rule because it inserts a literal U+FFFC character, violating the "never mutate the string" invariant.

**Tech Stack:** Swift 6, AppKit (`NSTextView`, `NSLayoutManager`, `NSGlyphInfo`), XCTest. Same XcodeGen-generated project as Phase 1 (`project.yml`, regenerate with `xcodegen generate`).

## Global Constraints

- macOS 14.0 (Sonoma) minimum deployment target (unchanged from Phase 1).
- Native Swift + AppKit only — no web view.
- The file on disk is always plain UTF-8 markdown; WYSIWYG rendering is a display-time transformation only and must never alter the underlying characters. This is the load-bearing invariant behind every technique in this plan (glyph substitution and layout-manager drawing were chosen specifically because they satisfy it; `NSTextAttachment` was rejected because it doesn't).
- Single-level blockquotes only (no nested `>>` support) — matches Phase 1's own precedent of single-level lists.
- Fenced code block highlighting is basic and language-agnostic (generic regex heuristics for strings/comments/numbers) — not a per-language tokenizer.
- GUI-visual verification (glyph rendering, layout-manager drawing) must be done against the real running app via Accessibility scripting + a screenshot read back with the Read tool — NOT a "code reasoning walkthrough." This project has working Accessibility/System Events access confirmed in this environment; use it. Always quit the launched app cleanly (`osascript -e 'tell application "Marginal" to quit'`) when verification is done — do not leave stray windows open, since a real person may be using this Mac concurrently.
- Known historical bug (fixed, stays fixed): XcodeGen's `info:`/`entitlements:` project.yml keys used to silently corrupt `Info.plist`/`Marginal.entitlements` on `xcodegen generate`. Current `project.yml` uses plain `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS` settings instead — if either file ever shows as modified in `git status` after `xcodegen generate`, STOP and report BLOCKED with the diff; do not investigate further, just don't commit it.

---

## File Structure

```
Sources/Marginal/Editor/
  MarkdownDocumentModel.swift    # MODIFY: add .code case, BlockquoteSpan, HorizontalRuleSpan,
                                 #   CodeBlockSpan, CodeTokenKind, CodeHighlightToken, model fields
  MarkdownParser.swift           # MODIFY: inline code pattern, parseBlockquotes, parseHorizontalRules,
                                 #   parseFencedCodeBlocks, parseCodeHighlightTokens
  MarkdownStyler.swift           # MODIFY: inline code styling, list bullet glyph substitution,
                                 #   link delimiter hiding, blockquote/HR/code-block attributes
  CursorRevealController.swift   # MODIFY: fix boundary overlap, add revealedLinkSpans,
                                 #   revealedBlockquoteSpans, revealedCodeBlockSpans
  MarkdownLayoutManager.swift    # CREATE: custom NSLayoutManager, draws blockquote bar + HR line
  MarkdownTextView.swift         # MODIFY: Cmd+Plus alias
Sources/Marginal/Document/
  DocumentViewController.swift   # MODIFY: attach MarkdownLayoutManager, wire new model fields into restyle()
Tests/MarginalTests/
  MarkdownParserTests.swift          # MODIFY: inline code, blockquote, HR, fenced-code-block, highlight-token tests
  MarkdownStylerTests.swift          # MODIFY: inline code, bullet glyph, link-hiding, blockquote/HR/code-block attribute tests
  CursorRevealControllerTests.swift  # MODIFY: boundary-overlap fix tests, link/blockquote/code-block reveal tests
  MarkdownTextViewTests.swift        # CREATE: Cmd+Plus keyDown test (new file — Phase 1 never had direct MarkdownTextView tests)
```

---

## Task 1: Fix — ⌘+ aliases to font-increase alongside ⌘=

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownTextView.swift`
- Test: `Tests/MarginalTests/MarkdownTextViewTests.swift` (new file)

**Interfaces:**
- No new public interface — `keyDown(with:)` already exists; this task adds one more matched character.

**Why this needs no reveal/model changes:** `charactersIgnoringModifiers` strips Option/Command/Control but honors Shift, so ⌘+ (⌘⇧=) produces the character `"+"`, which today matches no `case` in `MarkdownTextView.keyDown`'s switch and silently falls through to `super.keyDown`. Fixing this is a one-line addition.

- [ ] **Step 1: Write the failing test**

This is the first test file for `MarkdownTextView` directly — construct a fake shortcut delegate and a real `NSEvent` for ⌘+ and ⌘= to confirm both call the same delegate method.

```swift
import XCTest
import AppKit
@testable import Marginal

final class MarkdownTextViewTests: XCTestCase {

    private final class RecordingShortcutDelegate: MarkdownTextViewShortcutDelegate {
        var increaseCallCount = 0
        var decreaseCallCount = 0
        func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView) { increaseCallCount += 1 }
        func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView) { decreaseCallCount += 1 }
        func markdownTextViewCopyAsMarkdown(_ textView: MarkdownTextView) {}
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownTextViewTests`
Expected: FAIL — second assertion fails, `increaseCallCount` is still `1` (⌘+ falls through to `super.keyDown` today).

- [ ] **Step 3: Add the `"+"` case in `MarkdownTextView.swift`**

In `keyDown(with:)`'s switch statement, change the `case "="` line to also match `"+"`:

```swift
            case "=", "+":
                shortcutDelegate?.markdownTextViewIncreaseFontSize(self)
                return
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownTextViewTests`
Expected: PASS (1/1).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownTextView.swift Tests/MarginalTests/MarkdownTextViewTests.swift
git commit -m "Fix Cmd+Plus not aliasing to font-increase alongside Cmd+="
```

---

## Task 2: Fix — cursor-reveal boundary overlap on adjacent spans

**Files:**
- Modify: `Sources/Marginal/Editor/CursorRevealController.swift`
- Test: `Tests/MarginalTests/CursorRevealControllerTests.swift`

**Interfaces:**
- `CursorRevealController.revealedInlineStyleSpans(in:cursorLocation:)` signature unchanged — only its internal tie-breaking logic changes.

**The bug:** the reveal check uses `cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound` — inclusive on both ends. When two spans touch exactly (e.g. `**a****b**`, where the first span's closing `**` ends exactly where the second span's opening `**` begins), a cursor sitting at that shared index matches BOTH spans' inclusive ranges, so both reveal at once.

**The fix:** when more than one span matches, drop any span whose right edge (`fullRange.upperBound`) sits exactly at the cursor AND another matched span's left edge (`openingDelimiterRange.lowerBound`) also sits exactly at the cursor — i.e. prefer the span that *starts* at the shared boundary over the one that *ends* there. A single matching span is always returned unchanged (this is what every existing Phase 1 test exercises, since none of them have two spans in play at once — this fix is purely additive tie-breaking, existing tests keep passing unmodified).

- [ ] **Step 1: Write the failing test**

Add to `CursorRevealControllerTests.swift`:

```swift
    func testCursorAtSharedBoundaryOfAdjacentSpansRevealsOnlyOne() {
        let text = "**a****b**"
        // "**a**" spans indices 0..<5, "**b**" spans indices 5..<10 — index 5 is the exact
        // shared boundary between the first span's closing "**" and the second span's opening "**".
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 5)
        let revealed = CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor)
        XCTAssertEqual(revealed.count, 1, "Only one of the two touching spans should reveal at the shared boundary")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: FAIL — `revealed.count` is `2`.

- [ ] **Step 3: Fix `revealedInlineStyleSpans` in `CursorRevealController.swift`**

Replace the whole function:

```swift
    static func revealedInlineStyleSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [InlineStyleSpan] {
        let candidates = model.inlineStyles.filter { span in
            let fullRange = span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound
            return cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound
        }
        guard candidates.count > 1 else { return candidates }
        // When the cursor sits exactly on a shared boundary between two adjacent spans (one's
        // closing edge equals another's opening edge), prefer the span that STARTS there over
        // the one that ENDS there, so touching spans don't both reveal at once.
        return candidates.filter { span in
            let fullRange = span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound
            let endsExactlyAtCursor = fullRange.upperBound == cursorLocation
            let anotherStartsAtCursor = candidates.contains { other in
                other != span && other.openingDelimiterRange.lowerBound == cursorLocation
            }
            return !(endsExactlyAtCursor && anotherStartsAtCursor)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes, and existing tests still pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: PASS (all tests, including the 5 from Phase 1 plus this new one).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/CursorRevealController.swift Tests/MarginalTests/CursorRevealControllerTests.swift
git commit -m "Fix cursor-reveal boundary overlap letting adjacent spans both reveal"
```

---

## Task 3: Fix — list markers render as real bullets, not literal `-`/`*`/`+`

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`

**Interfaces:**
- No new public interface — `MarkdownStyler.attributedString` already handles `model.listItems`; this task changes what attributes get applied to `.unordered` markers.

**Design decision (verified by spike before this plan was written):** `NSGlyphInfo(glyphName: "bullet", for: font, baseString: "-")` set as the `.glyphInfo` attribute on an unordered marker's single-character range makes the *rendered glyph* a bullet while the *string* stays literally `"-"`/`"*"`/`"+"` — satisfying the never-mutate-the-string invariant. Ordered list numbers (`1.`, `2.`, ...) are left as literal text, unchanged — renumbering/list-style concerns are out of scope for this fix.

- [ ] **Step 1: Write the failing test**

Add to `MarkdownStylerTests.swift`:

```swift
    func testUnorderedListMarkerGetsGlyphSubstitutionAttribute() {
        let text = "- one\n- two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
        XCTAssertNotNil(glyphInfo, "Unordered marker should carry a glyph-substitution attribute")
        // The underlying string must stay the literal marker character -- this is the whole point.
        XCTAssertEqual(attributed.string.first, "-")
    }

    func testOrderedListMarkerGetsNoGlyphSubstitution() {
        let text = "1. one\n2. two"
        let model = MarkdownDocumentModel(listItems: MarkdownParser.parseListItems(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let glyphInfo = attributed.attribute(.glyphInfo, at: 0, effectiveRange: nil) as? NSGlyphInfo
        XCTAssertNil(glyphInfo, "Ordered markers keep their literal digits/period, no glyph substitution")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — `testUnorderedListMarkerGetsGlyphSubstitutionAttribute` fails, `glyphInfo` is nil.

- [ ] **Step 3: Update the list-item loop in `MarkdownStyler.attributedString`**

Replace the existing `for item in model.listItems { ... }` loop with:

```swift
        for item in model.listItems {
            let markerRange = NSRange(item.markerRange, in: text)
            result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: markerRange)

            if case .unordered = item.kind, markerRange.length > 0 {
                let markerCharacterRange = NSRange(location: markerRange.location, length: 1)
                let markerCharacter = String((text as NSString).substring(with: markerCharacterRange))
                if let glyphInfo = NSGlyphInfo(glyphName: "bullet", for: baseFont, baseString: markerCharacter) {
                    result.addAttribute(.glyphInfo, value: glyphInfo, range: markerCharacterRange)
                }
            }
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (both new tests, plus all existing `MarkdownStylerTests`).

- [ ] **Step 5: Manual GUI verification**

Build and launch the app, load `test/markdown-editor-feature-test.md`'s "Unordered Lists" section content (or type `- one\n- two\n- three`). Take a screenshot (`screencapture -l$(osascript -e 'tell application "System Events" to id of window 1 of process "Marginal"') /tmp/bullet-check.png` or capture the whole screen if window-id capture is awkward) and Read it back to visually confirm the markers render as bullet points, not literal hyphens. Quit the app cleanly afterward.

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownStyler.swift Tests/MarginalTests/MarkdownStylerTests.swift
git commit -m "Render unordered list markers as bullet glyphs via NSGlyphInfo, without changing the source character"
```

---

## Task 4: Fix — links never hide their `[]()` syntax

**Files:**
- Modify: `Sources/Marginal/Editor/CursorRevealController.swift`
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Test: `Tests/MarginalTests/CursorRevealControllerTests.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`

**Interfaces:**
- Produces: `CursorRevealController.revealedLinkSpans(in:cursorLocation:) -> [LinkSpan]`.
- Consumes: `LinkSpan.fullRange`/`textRange` (from Phase 1 Task 6).

**The bug:** Phase 1's `MarkdownStyler` only ever colors/underlines `link.textRange` — the surrounding `[`, `]`, `(`, url, `)` were never hidden, so links always show their full raw markdown syntax regardless of cursor position, unlike headers and inline styles which do hide/reveal.

**The fix:** apply the same hidden-font-size technique already used for headers/inline styles to the two "delimiter" pieces around a link's text — the range before `textRange` (covering `[`) and the range after `textRange` (covering `](url)`) — using `LinkSpan.fullRange` and `textRange` to compute them.

- [ ] **Step 1: Write the failing `CursorRevealController` test**

Add to `CursorRevealControllerTests.swift`:

```swift
    func testCursorOutsideLinkDoesNotRevealIt() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let cursor = text.startIndex
        XCTAssertTrue(CursorRevealController.revealedLinkSpans(in: model, cursorLocation: cursor).isEmpty)
    }

    func testCursorInsideLinkRevealsIt() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 10) // inside "this"
        XCTAssertEqual(CursorRevealController.revealedLinkSpans(in: model, cursorLocation: cursor).count, 1)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: FAIL — `revealedLinkSpans` not found.

- [ ] **Step 3: Add `revealedLinkSpans` to `CursorRevealController.swift`**

```swift
    static func revealedLinkSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [LinkSpan] {
        model.links.filter { link in
            cursorLocation >= link.fullRange.lowerBound && cursorLocation <= link.fullRange.upperBound
        }
    }
```

- [ ] **Step 4: Run to verify `CursorRevealControllerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: PASS (all tests).

- [ ] **Step 5: Write the failing `MarkdownStyler` test**

Add to `MarkdownStylerTests.swift`:

```swift
    func testLinkDelimitersAreHiddenWhenCursorIsElsewhere() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let openBracketLocation = text.distance(from: text.startIndex, to: text.range(of: "[")!.lowerBound)
        let font = attributed.attribute(.font, at: openBracketLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    func testLinkDelimitersAreRevealedWhenCursorIsInside() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 10) // inside "this"
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let openBracketLocation = text.distance(from: text.startIndex, to: text.range(of: "[")!.lowerBound)
        let font = attributed.attribute(.font, at: openBracketLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }
```

- [ ] **Step 6: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — delimiters currently render at the base font size regardless of cursor.

- [ ] **Step 7: Update the link loop in `MarkdownStyler.attributedString`**

Replace the existing `for link in model.links { ... }` loop with:

```swift
        let revealedLinks = cursorLocation.map {
            CursorRevealController.revealedLinkSpans(in: model, cursorLocation: $0)
        } ?? []

        for link in model.links {
            let textRange = NSRange(link.textRange, in: text)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            result.addAttribute(.link, value: link.url, range: textRange)

            let delimiterFont = revealedLinks.contains(link) ? baseFont : hiddenFont
            let fullNSRange = NSRange(link.fullRange, in: text)
            let prefixRange = NSRange(location: fullNSRange.location, length: textRange.location - fullNSRange.location)
            let suffixRange = NSRange(location: textRange.location + textRange.length, length: fullNSRange.location + fullNSRange.length - (textRange.location + textRange.length))
            if prefixRange.length > 0 {
                result.addAttribute(.font, value: delimiterFont, range: prefixRange)
            }
            if suffixRange.length > 0 {
                result.addAttribute(.font, value: delimiterFont, range: suffixRange)
            }
        }
```

Note: this declares `revealedLinks` right before the loop that uses it — place it directly above the `for link in model.links` line (after the existing `revealedStyles`/`revealedHeaders`/`hiddenFont` declarations near the top of the function, or immediately before this loop — either works, just don't declare it twice).

- [ ] **Step 8: Run to verify `MarkdownStylerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (both new tests, plus all existing).

- [ ] **Step 9: Commit**

```bash
git add Sources/Marginal/Editor/CursorRevealController.swift Sources/Marginal/Editor/MarkdownStyler.swift Tests/MarginalTests/CursorRevealControllerTests.swift Tests/MarginalTests/MarkdownStylerTests.swift
git commit -m "Fix links never hiding their [text](url) syntax -- hide/reveal like headers and inline styles"
```

---

## Task 5: Feature — inline code (`` `code` ``)

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Modify: `Sources/Marginal/Editor/MarkdownParser.swift`
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`

**Interfaces:**
- Produces: `InlineStyleKind.code` case (new).
- Reuses `InlineStyleSpan`/`CursorRevealController.revealedInlineStyleSpans` unchanged — inline code hides/reveals its backticks exactly like bold/italic already do, no new reveal function needed.

**Design decision:** inline code renders monospace with a subtle background tint, matching common convention (GitHub, Bear, iA Writer). Its backtick delimiters hide/reveal via the cursor exactly like `**`/`*`/`~~`/`<u>` already do (Task 4 of Phase 1's plan) — this feature is almost entirely reuse of existing infrastructure, not new mechanism.

- [ ] **Step 1: Add `.code` to `InlineStyleKind` in `MarkdownDocumentModel.swift`**

```swift
enum InlineStyleKind: Equatable {
    case bold
    case italic
    case strikethrough
    case underline
    case code
}
```

- [ ] **Step 2: Write the failing parser tests**

Add to `MarkdownParserTests.swift`:

```swift
final class MarkdownParserInlineCodeTests: XCTestCase {

    func testParsesInlineCode() {
        let text = "Use `npm install` to install"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .code)
        XCTAssertEqual(String(text[spans[0].contentRange]), "npm install")
    }

    func testMarkdownInsideInlineCodeDoesNotAlsoMatchAsOtherStyles() {
        let text = "`**not bold** and *not italic*`"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1, "The whole backtick span should win; asterisks inside must not also parse as bold/italic")
        XCTAssertEqual(spans[0].kind, .code)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserInlineCodeTests`
Expected: FAIL — no spans matched (`.code` doesn't exist as a produced kind yet).

- [ ] **Step 4: Add the code pattern to `MarkdownParser.parseInlineStyles`, FIRST in the priority order**

In `MarkdownParser.swift`, add this as the very first `findMatches` call (before the existing bold pattern), so backtick spans claim their range before anything inside them can be mistaken for bold/italic:

```swift
        // Inline code claims first: its content must never be reinterpreted as bold/italic/etc.
        findMatches(pattern: "`([^`\\n]+?)`", kind: .code, openLength: 1, closeLength: 1)
        findMatches(pattern: "\\*\\*(.+?)\\*\\*", kind: .bold, openLength: 2, closeLength: 2)
```

(leave the rest of the existing `findMatches` calls unchanged, just below this new line)

- [ ] **Step 5: Run to verify parser tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserInlineCodeTests`
Expected: PASS (both tests).

- [ ] **Step 6: Write the failing styler test**

Add to `MarkdownStylerTests.swift`:

```swift
    func testInlineCodeGetsMonospaceFontAndBackground() {
        let text = "Use `npm install` now"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "npm")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
        let background = attributed.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(background)
    }
```

- [ ] **Step 7: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — the `switch span.kind` in `attributedString` isn't exhaustive yet (compile error) or `.code` produces no styling.

- [ ] **Step 8: Add the `.code` case to the inline-style switch in `MarkdownStyler.attributedString`**

```swift
            case .code:
                result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular), range: contentRange)
                result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentRange)
```

Add this case inside the existing `switch span.kind { case .bold: ... case .italic: ... case .strikethrough: ... case .underline: ... }` block, alongside the others.

- [ ] **Step 9: Run to verify styler tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (all tests).

- [ ] **Step 10: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Sources/Marginal/Editor/MarkdownStyler.swift Tests/MarginalTests/MarkdownParserTests.swift Tests/MarginalTests/MarkdownStylerTests.swift
git commit -m "Add inline code support, reusing the existing inline-style hide/reveal pattern"
```

---

## Task 6: Feature — blockquotes + `MarkdownLayoutManager` infrastructure

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Modify: `Sources/Marginal/Editor/MarkdownParser.swift`
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Modify: `Sources/Marginal/Editor/CursorRevealController.swift`
- Create: `Sources/Marginal/Editor/MarkdownLayoutManager.swift`
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`
- Test: `Tests/MarginalTests/CursorRevealControllerTests.swift`

**Interfaces:**
- Produces: `BlockquoteSpan { markerRange, contentRange, lineRange }`, `MarkdownParser.parseBlockquotes(in:) -> [BlockquoteSpan]`, `CursorRevealController.revealedBlockquoteSpans(in:cursorLocation:) -> [BlockquoteSpan]`, `NSAttributedString.Key.marginalBlockquoteMarker`, `MarkdownLayoutManager` (Task 7 reuses this class and its `.marginalHorizontalRuleMarker` key).
- Consumes: nothing new from other tasks.

**Design decision:** single-level only (matches Phase 1's list-nesting precedent) — a line's `>` prefix marks it as a blockquote line; consecutive `>`-prefixed lines are NOT required to merge into one span, each qualifying line gets its own `BlockquoteSpan` (simpler, and the drawn bar naturally looks continuous across adjacent lines since each line gets its own bar rect at the same x-position). The `>` marker hides/reveals like a header's `#` marker; the left bar itself is always visible regardless of cursor (it's the reader's "you're in a blockquote" cue, not raw markdown syntax).

**Known v1 limitation (document this in the code):** nested blockquotes (`>>`) are not detected as nested — only a line's leading `>` (with or without a following space) is recognized; any additional `>` characters are treated as literal content, not further nesting.

- [ ] **Step 1: Add `BlockquoteSpan` to `MarkdownDocumentModel.swift`**

```swift
struct BlockquoteSpan: Equatable {
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
}
```

Add `var blockquotes: [BlockquoteSpan] = []` to `MarkdownDocumentModel`.

- [ ] **Step 2: Write the failing parser tests**

Add to `MarkdownParserTests.swift`:

```swift
final class MarkdownParserBlockquoteTests: XCTestCase {

    func testParsesSingleLineBlockquote() {
        let text = "> This is a quote"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 1)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "This is a quote")
    }

    func testParsesMultiLineBlockquoteAsOneSpanPerLine() {
        let text = "> Line one\n> Line two"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 2)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "Line one")
        XCTAssertEqual(String(text[blockquotes[1].contentRange]), "Line two")
    }

    func testPlainLineIsNotABlockquote() {
        XCTAssertTrue(MarkdownParser.parseBlockquotes(in: "Just a normal sentence.").isEmpty)
    }

    func testNestedMarkerIsNotSpeciallyDetected() {
        // Known v1 limitation: ">> nested" is parsed as ONE blockquote level whose content
        // literally starts with the second ">" -- not detected as a nested level.
        let text = ">> nested"
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        XCTAssertEqual(blockquotes.count, 1)
        XCTAssertEqual(String(text[blockquotes[0].contentRange]), "> nested")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserBlockquoteTests`
Expected: FAIL — `parseBlockquotes` not found.

- [ ] **Step 4: Add `parseBlockquotes` to `MarkdownParser.swift`**

```swift
    /// Single-level only: a line's leading ">" marks it as a blockquote line. Any additional
    /// ">" characters are treated as literal content, not further nesting -- known v1 limitation,
    /// matching Phase 1's single-level-lists precedent.
    static func parseBlockquotes(in text: String) -> [BlockquoteSpan] {
        var blockquotes: [BlockquoteSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = line.range(of: "^> ?", options: .regularExpression) {
                blockquotes.append(BlockquoteSpan(
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return blockquotes
    }
```

- [ ] **Step 5: Run to verify parser tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserBlockquoteTests`
Expected: PASS (all 4 tests).

- [ ] **Step 6: Write the failing `CursorRevealController` tests**

Add to `CursorRevealControllerTests.swift`:

```swift
    func testCursorInBlockquoteLineRevealsItsMarker() {
        let text = "> Quoted\nNot quoted"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 3) // inside "Quoted"
        XCTAssertEqual(CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOnOtherLineDoesNotRevealBlockquoteMarker() {
        let text = "> Quoted\nNot quoted"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 12) // inside "Not quoted"
        XCTAssertTrue(CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: cursor).isEmpty)
    }
```

- [ ] **Step 7: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: FAIL — `revealedBlockquoteSpans` not found.

- [ ] **Step 8: Add `revealedBlockquoteSpans` to `CursorRevealController.swift`**

```swift
    static func revealedBlockquoteSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [BlockquoteSpan] {
        model.blockquotes.filter { blockquote in
            cursorLocation >= blockquote.lineRange.lowerBound && cursorLocation <= blockquote.lineRange.upperBound
        }
    }
```

- [ ] **Step 9: Run to verify `CursorRevealControllerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: PASS (all tests).

- [ ] **Step 10: Write the failing `MarkdownStyler` test for the marker-hiding attribute**

Add to `MarkdownStylerTests.swift`:

```swift
    func testBlockquoteMarkerIsHiddenWhenCursorIsElsewhereAndMarkedForLayoutManager() {
        let text = "> Quoted text"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
        let contentLocation = text.distance(from: text.startIndex, to: text.range(of: "Quoted")!.lowerBound)
        let marker = attributed.attribute(.marginalBlockquoteMarker, at: contentLocation, effectiveRange: nil)
        XCTAssertNotNil(marker, "Content range must carry the layout-manager key so MarkdownLayoutManager can draw the bar")
    }

    func testBlockquoteMarkerIsRevealedWhenCursorIsInside() {
        let text = "> Quoted text"
        let model = MarkdownDocumentModel(blockquotes: MarkdownParser.parseBlockquotes(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 5)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }
```

- [ ] **Step 11: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — `.marginalBlockquoteMarker` doesn't exist yet, and blockquotes aren't styled at all.

- [ ] **Step 12: Create `Sources/Marginal/Editor/MarkdownLayoutManager.swift`**

```swift
import AppKit

extension NSAttributedString.Key {
    static let marginalBlockquoteMarker = NSAttributedString.Key("marginalBlockquoteMarker")
    static let marginalHorizontalRuleMarker = NSAttributedString.Key("marginalHorizontalRuleMarker")
}

/// Draws paragraph-level decorations that can't be expressed as ordinary run attributes: the
/// blockquote left bar and the horizontal rule line. Verified by a compiled spike (see Phase 2
/// design spec) to correctly span multi-line wrapped paragraphs, unlike a single-character
/// attachment would. Keyed off custom attributes MarkdownStyler applies to the relevant ranges.
final class MarkdownLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage, let textContainer = textContainers.first else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        textStorage.enumerateAttribute(.marginalBlockquoteMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let barRect = NSRect(x: origin.x + rect.minX - 10, y: origin.y + rect.minY, width: 3, height: rect.height)
            NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
            barRect.fill()
        }

        textStorage.enumerateAttribute(.marginalHorizontalRuleMarker, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let lineRect = NSRect(
                x: origin.x + textContainer.lineFragmentPadding,
                y: origin.y + rect.midY,
                width: max(0, textContainer.size.width - textContainer.lineFragmentPadding * 2),
                height: 1
            )
            NSColor.separatorColor.setFill()
            lineRect.fill()
        }
    }
}
```

- [ ] **Step 13: Update the blockquote handling in `MarkdownStyler.attributedString`**

Add this loop (near the header loop, since it follows the same hide/reveal pattern):

```swift
        let revealedBlockquotes = cursorLocation.map {
            CursorRevealController.revealedBlockquoteSpans(in: model, cursorLocation: $0)
        } ?? []

        for blockquote in model.blockquotes {
            let markerRange = NSRange(blockquote.markerRange, in: text)
            let contentRange = NSRange(blockquote.contentRange, in: text)
            result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask), range: contentRange)
            result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: contentRange)
            result.addAttribute(.marginalBlockquoteMarker, value: true, range: NSRange(blockquote.lineRange, in: text))

            let markerFont = revealedBlockquotes.contains(blockquote) ? baseFont : hiddenFont
            if markerRange.length > 0 {
                result.addAttribute(.font, value: markerFont, range: markerRange)
            }
        }
```

- [ ] **Step 14: Run to verify `MarkdownStylerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (both new tests, plus all existing).

- [ ] **Step 15: Wire `parseBlockquotes` into `DocumentViewController.restyle()`**

In `Sources/Marginal/Document/DocumentViewController.swift`, `restyle(cursorLocation:)`, add `blockquotes:` to the `MarkdownDocumentModel(...)` construction:

```swift
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text)
        )
```

- [ ] **Step 16: Attach `MarkdownLayoutManager` to the text view in `DocumentViewController.loadView()`**

Immediately after the `let textView = MarkdownTextView()` line (and before any other `textView.` configuration), swap in the custom layout manager using `NSTextContainer.replaceLayoutManager(_:)` — the documented API for exactly this, which handles detaching/reattaching the container and text storage internally (simpler and more reliable than manually juggling `removeTextContainer`/`addTextContainer`/`removeLayoutManager`/`addLayoutManager`):

```swift
        let textView = MarkdownTextView()
        textView.textContainer?.replaceLayoutManager(MarkdownLayoutManager())
```

- [ ] **Step 17: Regenerate, build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 18: Manual GUI verification (real, not code-reasoning)**

Launch the built app via `open`. Use Accessibility scripting to click into the text view and type a multi-line blockquote (e.g. `> This is a long quoted passage that should wrap across more than one visual line to confirm the bar spans the wrap`). Take a screenshot (`screencapture` targeting the app window, or the full screen) and Read it back to visually confirm: (a) the `>` marker is not visible as literal text when the cursor is elsewhere, (b) a left-edge bar is drawn next to the quoted paragraph, (c) the bar continues across wrapped lines of the same paragraph. Quit the app cleanly afterward (`osascript -e 'tell application "Marginal" to quit'`). If the bar doesn't render correctly (e.g. wrong position, doesn't span wrapped lines), fix `MarkdownLayoutManager`'s rect math and re-verify — this exact rect math was not compiled in the de-risking spike inside this specific app's real text-container geometry (only a standalone spike), so iteration here is expected.

- [ ] **Step 19: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Sources/Marginal/Editor/MarkdownStyler.swift Sources/Marginal/Editor/CursorRevealController.swift Sources/Marginal/Editor/MarkdownLayoutManager.swift Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/MarkdownParserTests.swift Tests/MarginalTests/MarkdownStylerTests.swift Tests/MarginalTests/CursorRevealControllerTests.swift
git commit -m "Add single-level blockquotes with a drawn left bar via a custom NSLayoutManager"
```

---

## Task 7: Feature — horizontal rules

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Modify: `Sources/Marginal/Editor/MarkdownParser.swift`
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Modify: `Sources/Marginal/Editor/CursorRevealController.swift`
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`
- Test: `Tests/MarginalTests/CursorRevealControllerTests.swift`

**Interfaces:**
- Produces: `HorizontalRuleSpan { lineRange }`, `MarkdownParser.parseHorizontalRules(in:) -> [HorizontalRuleSpan]`, `CursorRevealController.revealedHorizontalRuleSpans(in:cursorLocation:) -> [HorizontalRuleSpan]`.
- Consumes: `MarkdownLayoutManager` and `.marginalHorizontalRuleMarker` (both from Task 6 — already exist, this task only applies the attribute).

**Design decision:** recognizes exactly `---`, `***`, or `___` on their own line (a pragmatic subset of CommonMark's thematic-break rule, matching this codebase's established "pragmatic single-pass parser, not full CommonMark" style) — not the more permissive CommonMark rule that also allows spaces between the repeated characters or more than three repetitions. Like blockquotes and headers, the raw `---`/`***`/`___` text hides when the cursor is elsewhere and reveals when the cursor is on that line; the drawn line itself (via `MarkdownLayoutManager`, already built in Task 6) is always visible.

- [ ] **Step 1: Add `HorizontalRuleSpan` to `MarkdownDocumentModel.swift`**

```swift
struct HorizontalRuleSpan: Equatable {
    let lineRange: Range<String.Index>
}
```

Add `var horizontalRules: [HorizontalRuleSpan] = []` to `MarkdownDocumentModel`.

- [ ] **Step 2: Write the failing parser tests**

Add to `MarkdownParserTests.swift`:

```swift
final class MarkdownParserHorizontalRuleTests: XCTestCase {

    func testParsesThreeHyphens() {
        XCTAssertEqual(MarkdownParser.parseHorizontalRules(in: "---").count, 1)
    }

    func testParsesThreeAsterisks() {
        XCTAssertEqual(MarkdownParser.parseHorizontalRules(in: "***").count, 1)
    }

    func testParsesThreeUnderscores() {
        XCTAssertEqual(MarkdownParser.parseHorizontalRules(in: "___").count, 1)
    }

    func testPlainLineIsNotAHorizontalRule() {
        XCTAssertTrue(MarkdownParser.parseHorizontalRules(in: "Just a normal sentence.").isEmpty)
    }

    func testTwoHyphensIsNotAHorizontalRule() {
        XCTAssertTrue(MarkdownParser.parseHorizontalRules(in: "--").isEmpty)
    }

    func testHorizontalRuleAmongOtherLines() {
        let text = "Above\n---\nBelow"
        let rules = MarkdownParser.parseHorizontalRules(in: text)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(String(text[rules[0].lineRange]), "---")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserHorizontalRuleTests`
Expected: FAIL — `parseHorizontalRules` not found.

- [ ] **Step 4: Add `parseHorizontalRules` to `MarkdownParser.swift`**

```swift
    /// Pragmatic subset of CommonMark's thematic-break rule: exactly "---", "***", or "___" on
    /// their own line (no interior spaces, no other repetition counts) -- matches this parser's
    /// established single-pass, not-full-CommonMark style.
    static func parseHorizontalRules(in text: String) -> [HorizontalRuleSpan] {
        var rules: [HorizontalRuleSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if line == "---" || line == "***" || line == "___" {
                rules.append(HorizontalRuleSpan(lineRange: lineStart..<lineEnd))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return rules
    }
```

- [ ] **Step 5: Run to verify parser tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserHorizontalRuleTests`
Expected: PASS (all 6 tests).

- [ ] **Step 6: Write the failing `CursorRevealController` tests**

Add to `CursorRevealControllerTests.swift`:

```swift
    func testCursorOnHorizontalRuleLineRevealsIt() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 7) // on the "---" line
        XCTAssertEqual(CursorRevealController.revealedHorizontalRuleSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOnOtherLineDoesNotRevealHorizontalRule() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 1) // on "Above"
        XCTAssertTrue(CursorRevealController.revealedHorizontalRuleSpans(in: model, cursorLocation: cursor).isEmpty)
    }
```

- [ ] **Step 7: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: FAIL — `revealedHorizontalRuleSpans` not found.

- [ ] **Step 8: Add `revealedHorizontalRuleSpans` to `CursorRevealController.swift`**

```swift
    static func revealedHorizontalRuleSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [HorizontalRuleSpan] {
        model.horizontalRules.filter { rule in
            cursorLocation >= rule.lineRange.lowerBound && cursorLocation <= rule.lineRange.upperBound
        }
    }
```

- [ ] **Step 9: Run to verify `CursorRevealControllerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: PASS (all tests).

- [ ] **Step 10: Write the failing `MarkdownStyler` test**

Add to `MarkdownStylerTests.swift`:

```swift
    func testHorizontalRuleLineIsHiddenWhenCursorIsElsewhereAndMarkedForLayoutManager() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let ruleLocation = text.distance(from: text.startIndex, to: text.range(of: "---")!.lowerBound)
        let font = attributed.attribute(.font, at: ruleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
        let marker = attributed.attribute(.marginalHorizontalRuleMarker, at: ruleLocation, effectiveRange: nil)
        XCTAssertNotNil(marker, "Rule line must carry the layout-manager key so MarkdownLayoutManager draws the line")
    }

    func testHorizontalRuleLineIsRevealedWhenCursorIsOnIt() {
        let text = "Above\n---\nBelow"
        let model = MarkdownDocumentModel(horizontalRules: MarkdownParser.parseHorizontalRules(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 7)
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let ruleLocation = text.distance(from: text.startIndex, to: text.range(of: "---")!.lowerBound)
        let font = attributed.attribute(.font, at: ruleLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }
```

- [ ] **Step 11: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — horizontal rules aren't styled at all yet.

- [ ] **Step 12: Add the horizontal-rule loop to `MarkdownStyler.attributedString`**

```swift
        let revealedHorizontalRules = cursorLocation.map {
            CursorRevealController.revealedHorizontalRuleSpans(in: model, cursorLocation: $0)
        } ?? []

        for rule in model.horizontalRules {
            let lineNSRange = NSRange(rule.lineRange, in: text)
            result.addAttribute(.marginalHorizontalRuleMarker, value: true, range: lineNSRange)
            let ruleFont = revealedHorizontalRules.contains(rule) ? baseFont : hiddenFont
            result.addAttribute(.font, value: ruleFont, range: lineNSRange)
        }
```

- [ ] **Step 13: Run to verify `MarkdownStylerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (both new tests, plus all existing).

- [ ] **Step 14: Wire `parseHorizontalRules` into `DocumentViewController.restyle()`**

Add `horizontalRules:` to the same `MarkdownDocumentModel(...)` construction from Task 6 Step 15:

```swift
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text)
        )
```

- [ ] **Step 15: Regenerate, build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 16: Manual GUI verification**

Launch the app, type `Some text\n---\nMore text`, move the cursor off the `---` line. Screenshot and Read back to confirm a real horizontal divider line is drawn (not literal `---` text) and that clicking back onto that line reveals the literal `---`. Quit cleanly afterward.

- [ ] **Step 17: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Sources/Marginal/Editor/MarkdownStyler.swift Sources/Marginal/Editor/CursorRevealController.swift Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/MarkdownParserTests.swift Tests/MarginalTests/MarkdownStylerTests.swift Tests/MarginalTests/CursorRevealControllerTests.swift
git commit -m "Add horizontal rules with a real drawn divider line, reusing MarkdownLayoutManager"
```

---

## Task 8: Feature — fenced code blocks with basic heuristic syntax highlighting

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Modify: `Sources/Marginal/Editor/MarkdownParser.swift`
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Modify: `Sources/Marginal/Editor/CursorRevealController.swift`
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`
- Test: `Tests/MarginalTests/CursorRevealControllerTests.swift`

**Interfaces:**
- Produces: `CodeBlockSpan { openingFenceRange, contentRange, closingFenceRange, language }`, `MarkdownParser.parseFencedCodeBlocks(in:) -> [CodeBlockSpan]`, `CodeTokenKind` (`.string`, `.comment`, `.number`), `CodeHighlightToken { kind, range }`, `MarkdownParser.parseCodeHighlightTokens(in:) -> [CodeHighlightToken]`, `CursorRevealController.revealedCodeBlockSpans(in:cursorLocation:) -> [CodeBlockSpan]`.

**Design decision:** only ` ``` ` fences are recognized (not `~~~`) — a pragmatic subset matching this parser's established style. Highlighting is generic/language-agnostic regex heuristics (string literals in single or double quotes, `//`/`#` line comments, bare numbers) applied to a code block's content regardless of its language tag — not a per-language tokenizer. An unclosed fence (no matching closing ` ``` ` before end of document) produces no code block span at all — the rest of the document after an unclosed fence is treated as plain text; this is a known v1 limitation.

**Known v1 limitation (document this in the code):** a string literal's contents might contain a `#`/`//`-like substring that gets skipped correctly (because strings are matched before comments), but the reverse isn't fully robust for all pathological inputs — acceptable for a basic heuristic highlighter, not a real tokenizer.

- [ ] **Step 1: Add types to `MarkdownDocumentModel.swift`**

```swift
struct CodeBlockSpan: Equatable {
    let openingFenceRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let closingFenceRange: Range<String.Index>
    let language: String?
}

enum CodeTokenKind: Equatable {
    case string
    case comment
    case number
}

struct CodeHighlightToken: Equatable {
    let kind: CodeTokenKind
    let range: Range<String.Index>
}
```

Add `var codeBlocks: [CodeBlockSpan] = []` to `MarkdownDocumentModel`.

- [ ] **Step 2: Write the failing parser tests for `parseFencedCodeBlocks`**

Add to `MarkdownParserTests.swift`:

```swift
final class MarkdownParserFencedCodeBlockTests: XCTestCase {

    func testParsesPlainFencedCodeBlock() {
        let text = "```\nplain content\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(String(text[blocks[0].contentRange]), "plain content\n")
        XCTAssertNil(blocks[0].language)
    }

    func testParsesFencedCodeBlockWithLanguageTag() {
        let text = "```swift\nlet x = 1\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "swift")
        XCTAssertEqual(String(text[blocks[0].contentRange]), "let x = 1\n")
    }

    func testMarkdownInsideFencedCodeBlockIsNotParsedAsOtherSpans() {
        // This test only proves parseFencedCodeBlocks correctly identifies the block's
        // content range -- MarkdownStyler (a later step) is responsible for not re-parsing
        // that content range as headers/lists/etc.
        let text = "```markdown\n# Not a real heading\n- Not a real list\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertTrue(String(text[blocks[0].contentRange]).contains("# Not a real heading"))
    }

    func testUnclosedFenceProducesNoSpan() {
        let text = "```swift\nlet x = 1"
        XCTAssertTrue(MarkdownParser.parseFencedCodeBlocks(in: text).isEmpty)
    }

    func testTextWithoutFencesReturnsEmpty() {
        XCTAssertTrue(MarkdownParser.parseFencedCodeBlocks(in: "Just a normal paragraph.").isEmpty)
    }

    func testMultipleFencedCodeBlocks() {
        let text = "```\nfirst\n```\n\nSome text\n\n```\nsecond\n```"
        let blocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        XCTAssertEqual(blocks.count, 2)
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserFencedCodeBlockTests`
Expected: FAIL — `parseFencedCodeBlocks` not found.

- [ ] **Step 4: Add `parseFencedCodeBlocks` to `MarkdownParser.swift`**

```swift
    /// Only recognizes ``` fences (not ~~~) -- a pragmatic subset matching this parser's
    /// established style. An unclosed fence (no matching closing ``` before end of document)
    /// produces no span at all; the rest of the document is treated as plain text.
    static func parseFencedCodeBlocks(in text: String) -> [CodeBlockSpan] {
        var blocks: [CodeBlockSpan] = []
        var lineStart = text.startIndex
        var openingFenceRange: Range<String.Index>?
        var contentStart: String.Index?
        var language: String?

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if openingFenceRange == nil, trimmed.hasPrefix("```") {
                openingFenceRange = lineStart..<lineEnd
                let tag = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                language = tag.isEmpty ? nil : tag
                contentStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            } else if let openRange = openingFenceRange, trimmed == "```" {
                blocks.append(CodeBlockSpan(
                    openingFenceRange: openRange,
                    contentRange: contentStart!..<lineStart,
                    closingFenceRange: lineStart..<lineEnd,
                    language: language
                ))
                openingFenceRange = nil
                contentStart = nil
                language = nil
            }

            if lineEnd >= text.endIndex { break }
            lineStart = text.index(after: lineEnd)
        }
        return blocks
    }
```

- [ ] **Step 5: Run to verify parser tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserFencedCodeBlockTests`
Expected: PASS (all 6 tests).

- [ ] **Step 6: Write the failing tests for `parseCodeHighlightTokens`**

Add to `MarkdownParserTests.swift`:

```swift
final class MarkdownParserCodeHighlightTests: XCTestCase {

    func testParsesStringLiteral() {
        let code = "let greeting = \"hello\""
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .string })
        let stringToken = tokens.first { $0.kind == .string }!
        XCTAssertEqual(String(code[stringToken.range]), "\"hello\"")
    }

    func testParsesLineCommentWithDoubleSlash() {
        let code = "let x = 1 // a comment"
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
    }

    func testParsesLineCommentWithHash() {
        let code = "x = 1  # a comment"
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
    }

    func testParsesNumber() {
        let code = "let x = 42"
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertTrue(tokens.contains { $0.kind == .number })
    }

    func testHashInsideStringIsNotMistakenForAComment() {
        let code = "let s = \"contains # not a comment\""
        let tokens = MarkdownParser.parseCodeHighlightTokens(in: code)
        XCTAssertEqual(tokens.filter { $0.kind == .string }.count, 1)
        XCTAssertTrue(tokens.filter { $0.kind == .comment }.isEmpty, "The # is inside the string, already claimed -- must not also match as a comment")
    }

    func testPlainCodeWithNoTokensReturnsEmpty() {
        XCTAssertTrue(MarkdownParser.parseCodeHighlightTokens(in: "print(x)").isEmpty)
    }
}
```

- [ ] **Step 7: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserCodeHighlightTests`
Expected: FAIL — `parseCodeHighlightTokens` not found.

- [ ] **Step 8: Add `parseCodeHighlightTokens` to `MarkdownParser.swift`**

```swift
    /// Basic, language-agnostic heuristic highlighting -- not a real tokenizer. Order matters:
    /// strings claim first so a "#"/"//" INSIDE a string literal isn't later mistaken for a
    /// comment marker (the comment regex's match would overlap the already-claimed string
    /// range and get skipped by the isClaimed check).
    static func parseCodeHighlightTokens(in codeText: String) -> [CodeHighlightToken] {
        var tokens: [CodeHighlightToken] = []
        var claimed = Set<Int>()

        func offset(_ index: String.Index) -> Int {
            codeText.distance(from: codeText.startIndex, to: index)
        }
        func claim(_ range: Range<String.Index>) {
            for i in offset(range.lowerBound)..<offset(range.upperBound) { claimed.insert(i) }
        }
        func isClaimed(_ range: Range<String.Index>) -> Bool {
            for i in offset(range.lowerBound)..<offset(range.upperBound) where claimed.contains(i) { return true }
            return false
        }

        func findMatches(pattern: String, kind: CodeTokenKind) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsrange = NSRange(codeText.startIndex..<codeText.endIndex, in: codeText)
            regex.enumerateMatches(in: codeText, range: nsrange) { match, _, _ in
                guard let match, let fullRange = Range(match.range, in: codeText) else { return }
                if isClaimed(fullRange) { return }
                tokens.append(CodeHighlightToken(kind: kind, range: fullRange))
                claim(fullRange)
            }
        }

        findMatches(pattern: "\"[^\"\\n]*\"", kind: .string)
        findMatches(pattern: "'[^'\\n]*'", kind: .string)
        findMatches(pattern: "//[^\\n]*", kind: .comment)
        findMatches(pattern: "#[^\\n]*", kind: .comment)
        findMatches(pattern: "\\b\\d+(\\.\\d+)?\\b", kind: .number)

        return tokens
    }
```

- [ ] **Step 9: Run to verify tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserCodeHighlightTests`
Expected: PASS (all 6 tests).

- [ ] **Step 10: Write the failing `CursorRevealController` tests**

Add to `CursorRevealControllerTests.swift`:

```swift
    func testCursorInCodeBlockRevealsItsFences() {
        let text = "```\ncode here\n```"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 6) // inside "code here"
        XCTAssertEqual(CursorRevealController.revealedCodeBlockSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOutsideCodeBlockDoesNotRevealFences() {
        let text = "```\ncode here\n```\nafter"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let cursor = text.index(text.startIndex, offsetBy: text.count - 2) // inside "after"
        XCTAssertTrue(CursorRevealController.revealedCodeBlockSpans(in: model, cursorLocation: cursor).isEmpty)
    }
```

- [ ] **Step 11: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: FAIL — `revealedCodeBlockSpans` not found.

- [ ] **Step 12: Add `revealedCodeBlockSpans` to `CursorRevealController.swift`**

```swift
    static func revealedCodeBlockSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [CodeBlockSpan] {
        model.codeBlocks.filter { block in
            let fullRange = block.openingFenceRange.lowerBound..<block.closingFenceRange.upperBound
            return cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound
        }
    }
```

- [ ] **Step 13: Run to verify `CursorRevealControllerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: PASS (all tests).

- [ ] **Step 14: Write the failing `MarkdownStyler` tests**

Add to `MarkdownStylerTests.swift`:

```swift
    func testCodeBlockContentGetsMonospaceFontAndBackground() {
        let text = "```\nplain content\n```"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let contentLocation = text.distance(from: text.startIndex, to: text.range(of: "plain")!.lowerBound)
        let font = attributed.attribute(.font, at: contentLocation, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
        let background = attributed.attribute(.backgroundColor, at: contentLocation, effectiveRange: nil) as? NSColor
        XCTAssertNotNil(background)
    }

    func testCodeBlockFencesAreHiddenWhenCursorIsElsewhere() {
        let text = "```\nplain content\n```\nafter"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    func testCodeBlockHighlightTokensGetColored() {
        let text = "```\nlet s = \"hi\"\n```"
        let model = MarkdownDocumentModel(codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let stringLocation = text.distance(from: text.startIndex, to: text.range(of: "\"hi\"")!.lowerBound)
        let color = attributed.attribute(.foregroundColor, at: stringLocation, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(color, NSColor.labelColor, "The string literal should get a distinct highlight color, not the default text color")
    }
```

- [ ] **Step 15: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — code blocks aren't styled at all yet.

- [ ] **Step 16: Add the code-block loop to `MarkdownStyler.attributedString`**

```swift
        let revealedCodeBlocks = cursorLocation.map {
            CursorRevealController.revealedCodeBlockSpans(in: model, cursorLocation: $0)
        } ?? []

        for codeBlock in model.codeBlocks {
            let contentNSRange = NSRange(codeBlock.contentRange, in: text)
            let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            result.addAttribute(.font, value: codeFont, range: contentNSRange)
            result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentNSRange)

            let codeText = String(text[codeBlock.contentRange])
            for token in MarkdownParser.parseCodeHighlightTokens(in: codeText) {
                let startOffset = codeText.distance(from: codeText.startIndex, to: token.range.lowerBound)
                let endOffset = codeText.distance(from: codeText.startIndex, to: token.range.upperBound)
                guard let tokenStart = text.index(codeBlock.contentRange.lowerBound, offsetBy: startOffset, limitedBy: text.endIndex),
                      let tokenEnd = text.index(codeBlock.contentRange.lowerBound, offsetBy: endOffset, limitedBy: text.endIndex) else { continue }
                let tokenColor: NSColor
                switch token.kind {
                case .string: tokenColor = NSColor.systemGreen
                case .comment: tokenColor = NSColor.secondaryLabelColor
                case .number: tokenColor = NSColor.systemPurple
                }
                result.addAttribute(.foregroundColor, value: tokenColor, range: NSRange(tokenStart..<tokenEnd, in: text))
            }

            let fenceFont = revealedCodeBlocks.contains(codeBlock) ? baseFont : hiddenFont
            result.addAttribute(.font, value: fenceFont, range: NSRange(codeBlock.openingFenceRange, in: text))
            result.addAttribute(.font, value: fenceFont, range: NSRange(codeBlock.closingFenceRange, in: text))
        }
```

- [ ] **Step 17: Run to verify `MarkdownStylerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (all 3 new tests, plus all existing).

- [ ] **Step 18: Wire `parseFencedCodeBlocks` into `DocumentViewController.restyle()`**

Add `codeBlocks:` to the `MarkdownDocumentModel(...)` construction (same one from Tasks 6 and 7):

```swift
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text)
        )
```

- [ ] **Step 19: Regenerate, build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 20: Manual GUI verification**

Launch the app, type:
```
```swift
let greeting = "hello" // a comment
```
```
Screenshot and Read back to confirm: monospace font, a background tint distinguishing the code block from surrounding text, the string literal and comment visibly colored differently from plain code, and the fence lines hidden when the cursor is elsewhere / revealed when the cursor is inside the block. Quit cleanly afterward.

- [ ] **Step 21: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Sources/Marginal/Editor/MarkdownStyler.swift Sources/Marginal/Editor/CursorRevealController.swift Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/MarkdownParserTests.swift Tests/MarginalTests/MarkdownStylerTests.swift Tests/MarginalTests/CursorRevealControllerTests.swift
git commit -m "Add fenced code blocks with basic language-agnostic heuristic syntax highlighting"
```

---

## Task 9: Final Phase 2 verification pass and status update

**Files:**
- Modify: `README.md`

**Interfaces:** none — this task only verifies and documents, no new production code.

- [ ] **Step 1: Run the full test suite**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal`
Expected: all tests across every test file PASS (Phase 1's 42 plus every test added in Tasks 1–8 of this plan).

- [ ] **Step 2: Full manual regression pass against the feature test file**

Launch the app, open `test/markdown-editor-feature-test.md` (via File > Open, exercising the Phase 1.5 hotfix), and visually confirm via screenshots read back with the Read tool:
1. Every Phase 1 formatting type still renders correctly (bold/italic/strikethrough/underline/headers/lists/links) — this file's "Text Formatting", "Unordered Lists", "Ordered Lists", and "Links" sections exercise these.
2. Inline code (this file's "Inline Code" section) renders monospace with a background tint.
3. Fenced code blocks (this file's "Code Blocks" section, e.g. the JavaScript/Python/JSON examples) render monospace with a background and basic string/comment/number highlighting.
4. Blockquotes (this file's "Blockquotes" section) show a left bar and muted italic text, with the `>` marker hidden/revealed correctly.
5. Horizontal rules (this file's "Horizontal Rules" section) render as a real drawn line.
6. Unordered list markers (this file's "Unordered Lists" section) render as bullet glyphs, not literal hyphens/asterisks/plus signs.
7. Links (this file's "Links" section) hide their `[]()` syntax when the cursor is elsewhere and reveal it when the cursor is inside.
8. ⌘+ and ⌘= both increase font size; ⌘- decreases it.
9. Copy/paste/undo/redo/select-all all still work (Phase 1.5 hotfix regression check).

Note: this file also contains many features explicitly out of Marginal's scope per the spec (tables, images, footnotes, math, Mermaid, etc.) — confirm those render as inert plain text (their raw markdown/HTML shown as-is) rather than causing a crash or corrupting nearby content, but do not expect them to be styled.

- [ ] **Step 3: Update `README.md` status line**

Change:
```markdown
> **Status: 🚧 Phase 1 complete (foundation + core WYSIWYG engine).** Tables, images, code highlighting, AI, visual polish, and export are not yet implemented — see [`specs`](specs) and [`plans`](plans).
```
to:
```markdown
> **Status: 🚧 Phase 2 complete (formatting engine: inline code, fenced code blocks with basic highlighting, blockquotes, horizontal rules).** Tables, images, AI, visual polish, and export are not yet implemented — see [`specs`](specs) and [`plans`](plans).
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Complete Phase 2: formatting engine completion + quality fixes"
```

---

## Self-Review Notes

- **Spec coverage:** inline code ✅ (Task 5), fenced code blocks + basic highlighting ✅ (Task 8), blockquotes ✅ (Task 6), horizontal rules ✅ (Task 7); link-hiding fix ✅ (Task 4), list-bullet fix ✅ (Task 3), ⌘+ alias fix ✅ (Task 1), reveal-boundary fix ✅ (Task 2). Tables, images, AI, visual polish, export, packaging remain explicitly out of scope per Global Constraints, for future phases.
- **Placeholder scan:** no TBD/TODO markers; the "Known v1 limitation" notes (Tasks 6, 7, 8) are concrete, bounded scope decisions, matching Phase 1's own established style, not unresolved gaps.
- **Type consistency:** `BlockquoteSpan`, `HorizontalRuleSpan`, `CodeBlockSpan`, `CodeTokenKind`, `CodeHighlightToken`, `MarkdownParser.parseBlockquotes/parseHorizontalRules/parseFencedCodeBlocks/parseCodeHighlightTokens`, `CursorRevealController.revealedLinkSpans/revealedBlockquoteSpans/revealedHorizontalRuleSpans/revealedCodeBlockSpans`, `MarkdownLayoutManager`, `.marginalBlockquoteMarker`/`.marginalHorizontalRuleMarker` are used with identical names and signatures everywhere they're referenced across tasks. The shared `MarkdownDocumentModel(...)` construction in `DocumentViewController.restyle()` is extended incrementally by Tasks 6, 7, and 8 (each adding one more named parameter) rather than each task rewriting the whole call — later tasks' steps show the cumulative signature at that point.
