# Marginal Editor Modes: Code · Live · Preview — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hidden `⌘⇧P` "Show Source" toggle with three explicit editor modes — **Code** (tinted monospace source, nothing hides, nothing reflows), **Live** (today's reveal-at-cursor WYSIWYG, unchanged), and **Preview** (read-only `WKWebView` render where a paragraph's soft newlines collapse) — exposed through a status-bar segmented control, a new View menu, and `⌘⌥1/2/3`.

**Architecture:** Two new types carry the feature. `EditorMode` is the enum plus its `UserDefaults` persistence and display metadata. `EditorModeController` owns the active mode and collapses the render dispatch to one call site — today the branch `isShowingSource ? applyPlainSourceRendering() : restyle(…)` is duplicated in four places in `DocumentViewController`, and a three-way version of that duplication is how this feature would rot. Preview reuses the existing `MarkdownHTMLRenderer` (which already collapses a paragraph's lines with a space before emitting `<p>`) plus a stylesheet extracted out of `PDFExporter`, so screen preview, PDF export and Copy as HTML stay one artifact. Position is preserved across mode switches via `data-line` attributes emitted on every block element.

**Tech Stack:** Swift 6, AppKit (`NSTextView`, `NSSegmentedControl`, `NSLayoutManager`), WebKit (`WKWebView`, Preview only), XCTest. Same XcodeGen-generated project (`project.yml`, regenerate with `xcodegen generate`).

## Global Constraints

- macOS 14.0 (Sonoma) minimum deployment target.
- Swift 6 + AppKit. **WebKit is permitted for Preview mode and PDF export only** — this consciously supersedes Phase 2's "native AppKit only, no web view" constraint, which `PDFExporter` already broke. Code and Live modes remain pure AppKit text rendering.
- **The file on disk is always plain UTF-8 markdown.** The text storage in Code and Live modes is the literal source and is never mutated for display — only attributes change. Preview renders from a copy and has no write path. This is the load-bearing invariant behind the whole app; every technique in this plan was chosen to satisfy it.
- Mode is per-window; the last-chosen mode persists globally in `UserDefaults` under the key `editorMode`, mirroring the existing `editorFontPointSize` precedent.
- `⌘1`–`⌘9` stay bound to "Select Tab N" (`AppDelegate.buildMainMenu`). Mode switching uses `⌘⌥1/2/3` and is registered **only** as View-menu key equivalents — never in `MarkdownTextView.keyDown`, so plain `⌘1` can never be intercepted from tab switching.
- Colors come from `DesignPalette` (AppKit) and `MarkdownStylesheet` (CSS). Never hardcode a hex value at a call site.
- Test command: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`. A single test: append `-only-testing:MarginalTests/<Suite>/<testName>`.
- GUI-visual verification must be done against the real running app via Accessibility scripting plus a screenshot read back with the Read tool — NOT a code-reasoning walkthrough. Always quit the launched app cleanly (`osascript -e 'tell application "Marginal" to quit'`) when done; a real person may be using this Mac concurrently.
- Known historical bug (fixed, stays fixed): XcodeGen's `info:`/`entitlements:` keys used to corrupt `Info.plist`/`Marginal.entitlements` on `xcodegen generate`. If either file shows as modified in `git status` after `xcodegen generate`, STOP and report BLOCKED with the diff — do not investigate, do not commit it.
- New source files must be added to the target. This project uses XcodeGen with directory-based sources, so `xcodegen generate` picks them up automatically — run it after creating a file, then confirm `Info.plist`/`entitlements` are unmodified per the constraint above.
- **`Marginal.xcodeproj/` is generated and git-ignored (`.gitignore:8`) — never commit it, and never `git add -f` it.** It carries per-user Xcode state (`UserInterfaceState.xcuserstate`) that must not enter the history. Commit only the `Sources/` and `Tests/` files a task creates or edits. Never `git add -A`: the working tree has unrelated pre-existing modifications in `marketing/` and `test/`.

---

## File Structure

```
Sources/Marginal/Editor/
  EditorMode.swift               # CREATE: enum, UserDefaults persistence, display metadata
  EditorModeController.swift     # CREATE: owns active mode, single render() dispatch, host protocol
  DocumentStatistics.swift       # CREATE: word count + reading time for Preview's status bar
  MarkdownStylesheet.swift       # CREATE: CSS for screen (light/dark) and print, extracted from PDFExporter
  PreviewWebView.swift           # CREATE: WKWebView host, loads rendered HTML, scroll anchor queries
  MarkdownStyler.swift           # MODIFY: add codeSourceAttributedString (Task 5), delete
                                 #   plainSourceAttributedString (Task 8)
  MarkdownHTMLRenderer.swift     # MODIFY: data-line anchors, blockSourceLines, blockLine mapping
  EditorChromeViews.swift        # MODIFY: StatusBarView gains the segmented control + preview
                                 #   variant; LineNumberGutterView gains all-lines mode
  MarkdownTextView.swift         # MODIFY: remove the ⌘⇧P case and the toggleShowSource protocol method
Sources/Marginal/Document/
  DocumentViewController.swift   # MODIFY: delegate mode handling to EditorModeController, host the
                                 #   preview view, preserve position across switches
Sources/Marginal/App/
  AppDelegate.swift              # MODIFY: View menu (modes + zoom), checkmark validation
Sources/Marginal/Export/
  PDFExporter.swift              # MODIFY: use MarkdownStylesheet.printCSS instead of inline CSS
Tests/MarginalTests/
  EditorModeTests.swift              # CREATE
  EditorModeControllerTests.swift    # CREATE
  DocumentStatisticsTests.swift      # CREATE
  MarkdownStylesheetTests.swift      # CREATE
  PreviewWebViewTests.swift          # CREATE
  MarkdownHTMLRendererTests.swift    # MODIFY: data-line anchors, blockSourceLines, mapping
  MarkdownStylerTests.swift          # MODIFY: code-mode marker tinting, uniform-font-size guarantee
  EditorChromeViewsTests.swift       # CREATE: status bar + gutter configuration
```

---

## Task 1: `EditorMode` — the enum, its persistence, its display metadata

**Files:**
- Create: `Sources/Marginal/Editor/EditorMode.swift`
- Test: `Tests/MarginalTests/EditorModeTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum EditorMode: String, CaseIterable { case code, live, preview }`, with instance properties `title: String`, `symbolName: String`, `menuKeyEquivalent: String`, and statics `EditorMode.persisted(in: UserDefaults) -> EditorMode` / `func persist(in: UserDefaults)`. Every later task uses these names.

- [ ] **Step 1: Write the failing test**

Create `Tests/MarginalTests/EditorModeTests.swift`:

```swift
import XCTest
@testable import Marginal

final class EditorModeTests: XCTestCase {

    private func emptyDefaults() -> UserDefaults {
        let suite = "EditorModeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToLiveWhenNothingPersisted() {
        XCTAssertEqual(EditorMode.persisted(in: emptyDefaults()), .live)
    }

    func testPersistRoundTripsEveryMode() {
        for mode in EditorMode.allCases {
            let defaults = emptyDefaults()
            mode.persist(in: defaults)
            XCTAssertEqual(EditorMode.persisted(in: defaults), mode, "\(mode) did not round-trip")
        }
    }

    func testUnknownPersistedValueFallsBackToLive() {
        let defaults = emptyDefaults()
        defaults.set("split", forKey: "editorMode")
        XCTAssertEqual(EditorMode.persisted(in: defaults), .live)
    }

    func testDisplayMetadata() {
        XCTAssertEqual(EditorMode.code.title, "Code")
        XCTAssertEqual(EditorMode.live.title, "Live")
        XCTAssertEqual(EditorMode.preview.title, "Preview")
        XCTAssertEqual(EditorMode.code.symbolName, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(EditorMode.live.symbolName, "text.cursor")
        XCTAssertEqual(EditorMode.preview.symbolName, "eye")
        XCTAssertEqual(EditorMode.allCases.map(\.menuKeyEquivalent), ["1", "2", "3"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/EditorModeTests`
Expected: FAIL — compile error, `cannot find 'EditorMode' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Marginal/Editor/EditorMode.swift`:

```swift
import Foundation

/// The editor's three rendering surfaces. `allCases` order is the order they appear in the
/// status-bar control and the View menu, and it defines the ⌘⌥1/2/3 key equivalents.
enum EditorMode: String, CaseIterable {
    /// Monospace source: every marker visible and tinted, uniform font size, nothing reflows.
    case code
    /// WYSIWYG with markdown syntax revealing itself at the cursor. The default.
    case live
    /// Read-only rendered HTML, where a paragraph's soft newlines collapse into flowing text.
    case preview

    /// The key `EditorMode` persists under. Mirrors the existing "editorFontPointSize" key.
    static let defaultsKey = "editorMode"

    var title: String {
        switch self {
        case .code: return "Code"
        case .live: return "Live"
        case .preview: return "Preview"
        }
    }

    /// SF Symbol shown in the status-bar segmented control.
    var symbolName: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .live: return "text.cursor"
        case .preview: return "eye"
        }
    }

    /// The digit in this mode's ⌘⌥-modified View menu shortcut.
    var menuKeyEquivalent: String {
        switch self {
        case .code: return "1"
        case .live: return "2"
        case .preview: return "3"
        }
    }

    /// The last mode the user chose, or `.live` on first launch and for any unrecognized
    /// stored value (e.g. a mode written by a newer version of the app).
    static func persisted(in defaults: UserDefaults) -> EditorMode {
        guard let raw = defaults.string(forKey: defaultsKey), let mode = EditorMode(rawValue: raw) else {
            return .live
        }
        return mode
    }

    func persist(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Regenerate the project and run the test**

Run: `xcodegen generate && git status --short`
Expected: `Info.plist` and `Marginal.entitlements` are NOT listed as modified. If either is, STOP and report BLOCKED with the diff.

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/EditorModeTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/EditorMode.swift Tests/MarginalTests/EditorModeTests.swift
git commit -m "feat: EditorMode enum with UserDefaults persistence"
```

---

## Task 2: `DocumentStatistics` — word count and reading time

**Files:**
- Create: `Sources/Marginal/Editor/DocumentStatistics.swift`
- Test: `Tests/MarginalTests/DocumentStatisticsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct DocumentStatistics: Equatable { let wordCount: Int; let readingMinutes: Int; var statusText: String }` and `static func statistics(for markdown: String) -> DocumentStatistics`. Task 10 renders `statusText` in Preview's status bar.

- [ ] **Step 1: Write the failing test**

Create `Tests/MarginalTests/DocumentStatisticsTests.swift`:

```swift
import XCTest
@testable import Marginal

final class DocumentStatisticsTests: XCTestCase {

    func testEmptyDocument() {
        let stats = DocumentStatistics.statistics(for: "")
        XCTAssertEqual(stats.wordCount, 0)
        XCTAssertEqual(stats.readingMinutes, 0)
        XCTAssertEqual(stats.statusText, "No words")
    }

    func testCountsWhitespaceSeparatedWords() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one two three").wordCount, 3)
    }

    func testCollapsesRunsOfWhitespaceAndNewlines() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one   two\n\nthree\tfour\n").wordCount, 4)
    }

    // Markdown markers are punctuation, not words: a "---" rule or a bare "#" adds nothing.
    func testPurePunctuationRunsAreNotWords() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "# Title\n\n---\n\n**bold**").wordCount, 2)
    }

    func testReadingTimeRoundsUpAndIsAtLeastOneMinuteForAnyWords() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one").readingMinutes, 1)
        let twoHundredTwenty = Array(repeating: "word", count: 220).joined(separator: " ")
        XCTAssertEqual(DocumentStatistics.statistics(for: twoHundredTwenty).readingMinutes, 1)
        let twoHundredTwentyOne = Array(repeating: "word", count: 221).joined(separator: " ")
        XCTAssertEqual(DocumentStatistics.statistics(for: twoHundredTwentyOne).readingMinutes, 2)
    }

    func testStatusTextSingularAndPlural() {
        XCTAssertEqual(DocumentStatistics.statistics(for: "one").statusText, "1 word · 1 min read")
        XCTAssertEqual(DocumentStatistics.statistics(for: "one two").statusText, "2 words · 1 min read")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/DocumentStatisticsTests`
Expected: FAIL — `cannot find 'DocumentStatistics' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Marginal/Editor/DocumentStatistics.swift`:

```swift
import Foundation

/// Word count and reading time for the status bar in Preview mode, where the caret-based
/// breadcrumb and "L · C" readout have nothing to report.
struct DocumentStatistics: Equatable {

    /// Average adult silent-reading speed for prose, in words per minute. 220 is the midpoint
    /// of the commonly cited 200–250 range.
    static let wordsPerMinute = 220

    let wordCount: Int
    let readingMinutes: Int

    /// Counts whitespace-separated runs that contain at least one letter or digit, so markdown
    /// punctuation ("---", "#", "**") never inflates the count.
    static func statistics(for markdown: String) -> DocumentStatistics {
        let words = markdown
            .split(whereSeparator: { $0.isWhitespace })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }
            .count
        let minutes = words == 0 ? 0 : Int(ceil(Double(words) / Double(wordsPerMinute)))
        return DocumentStatistics(wordCount: words, readingMinutes: minutes)
    }

    var statusText: String {
        guard wordCount > 0 else { return "No words" }
        let wordLabel = wordCount == 1 ? "1 word" : "\(wordCount) words"
        return "\(wordLabel) · \(readingMinutes) min read"
    }
}
```

- [ ] **Step 4: Regenerate and run the test**

Run: `xcodegen generate && git status --short`
Expected: `Info.plist`/`Marginal.entitlements` NOT modified.

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/DocumentStatisticsTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/DocumentStatistics.swift Tests/MarginalTests/DocumentStatisticsTests.swift
git commit -m "feat: DocumentStatistics word count and reading time"
```

---

## Task 3: `MarkdownStylesheet` — extract the CSS out of `PDFExporter`, add a dark variant

**Files:**
- Create: `Sources/Marginal/Editor/MarkdownStylesheet.swift`
- Modify: `Sources/Marginal/Export/PDFExporter.swift:49-89` (replace the inline `<style>` block and page wrapper)
- Test: `Tests/MarginalTests/MarkdownStylesheetTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum MarkdownStylesheet` with `enum Appearance { case light, dark }`
  - `static func screenCSS(appearance: Appearance, bodyPointSize: CGFloat) -> String`
  - `static var printCSS: String`
  - `static func document(body: String, title: String, css: String) -> String`

  Task 6 calls `screenCSS` + `document`. `PDFExporter` calls `printCSS` + `document`.

- [ ] **Step 1: Write the failing test**

Create `Tests/MarginalTests/MarkdownStylesheetTests.swift`:

```swift
import XCTest
@testable import Marginal

final class MarkdownStylesheetTests: XCTestCase {

    func testScreenCSSUsesTheGivenBodySize() {
        let css = MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 18)
        XCTAssertTrue(css.contains("font-size: 18px"), css)
    }

    func testLightAndDarkDifferAndEachCarriesItsOwnPaperColour() {
        let light = MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 16)
        let dark = MarkdownStylesheet.screenCSS(appearance: .dark, bodyPointSize: 16)
        XCTAssertNotEqual(light, dark)
        // Paper, not white / ink, not black — the design system's surfaces.
        XCTAssertTrue(light.contains("#FFFEFC"), light)
        XCTAssertTrue(dark.contains("#1E1E1D"), dark)
        XCTAssertFalse(light.contains("#1E1E1D"), "light variant must not carry dark surfaces")
    }

    // Every token is re-typed as a hex literal here rather than derived from the canonical
    // token sheet, so each one needs pinning or a one-digit drift goes unnoticed. These are
    // marketing/Marginal Design System/tokens/colors.css --ink-header for each appearance.
    func testHeadingTokenMatchesTheDesignSystemInBothAppearances() {
        XCTAssertTrue(MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 16).contains("#232323"))
        XCTAssertTrue(MarkdownStylesheet.screenCSS(appearance: .dark, bodyPointSize: 16).contains("#F2F1EE"))
    }

    // Print is always on white paper, so it never follows the window's appearance.
    func testPrintCSSIsLightAndCarriesPageBreakRules() {
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("#2C2C2B"))
        XCTAssertFalse(MarkdownStylesheet.printCSS.contains("#1E1E1D"))
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("page-break-after: avoid"))
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("12pt"))
    }

    func testDocumentWrapsBodyAndEscapesTitle() {
        let html = MarkdownStylesheet.document(body: "<p>hi</p>", title: "A & B <c>", css: "body{}")
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<title>A &amp; B &lt;c&gt;</title>"), html)
        XCTAssertTrue(html.contains("<body><p>hi</p></body>"), html)
        XCTAssertTrue(html.contains("body{}"))
    }

    // The accent, inline-code and rule colours must come from one place, not be retyped
    // per call site — assert the shared token appears in both stylesheets.
    func testBothStylesheetsUseTheAccentToken() {
        XCTAssertTrue(MarkdownStylesheet.screenCSS(appearance: .light, bodyPointSize: 16).contains("#8E1FCB"))
        XCTAssertTrue(MarkdownStylesheet.printCSS.contains("#8E1FCB"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/MarkdownStylesheetTests`
Expected: FAIL — `cannot find 'MarkdownStylesheet' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Marginal/Editor/MarkdownStylesheet.swift`:

```swift
import Foundation

/// The CSS behind every HTML rendering of a document — Preview mode on screen and PDF export.
/// One stylesheet, so the three renderings of a document (screen, PDF, Copy as HTML) can never
/// drift apart. Colour values mirror DesignPalette / the design system's token sheet.
enum MarkdownStylesheet {

    enum Appearance {
        case light
        case dark
    }

    private struct Tokens {
        let paper: String
        let ink: String
        let heading: String
        let panel: String
        let hairline: String
        let accent: String
        let muted: String

        static let light = Tokens(
            paper: "#FFFEFC", ink: "#2C2C2B", heading: "#232323", panel: "#F7F6F3",
            hairline: "#E6E5E3", accent: "#8E1FCB", muted: "#6B6A67"
        )

        static let dark = Tokens(
            paper: "#1E1E1D", ink: "#E8E7E3", heading: "#F2F1EE", panel: "#252524",
            hairline: "#33332F", accent: "#CB7DF7", muted: "#A6A49F"
        )
    }

    /// Preview mode. Follows the window's appearance and the editor's own font size, so ⌘+/⌘−
    /// keep working in Preview.
    static func screenCSS(appearance: Appearance, bodyPointSize: CGFloat) -> String {
        let tokens = appearance == .light ? Tokens.light : Tokens.dark
        return rules(
            tokens: tokens,
            bodySize: "\(Int(bodyPointSize.rounded()))px",
            extra: """
              body { background: \(tokens.paper); padding: 24px 40px 64px; }
              ::selection { background: \(appearance == .light ? "#EDD5F9" : "#472C63"); }
            """
        )
    }

    /// PDF export. Always the light tokens at 12pt — print goes on white paper regardless of
    /// the window's appearance — plus pagination rules the screen doesn't need.
    static var printCSS: String {
        rules(
            tokens: .light,
            bodySize: "12pt",
            extra: """
              body { margin: 0; }
              pre { page-break-inside: avoid; }
              h1, h2, h3 { page-break-after: avoid; }
            """
        )
    }

    private static func rules(tokens: Tokens, bodySize: String, extra: String) -> String {
        """
          body {
            font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
            font-size: \(bodySize); line-height: 1.5; color: \(tokens.ink);
          }
          h1, h2, h3, h4, h5, h6 { color: \(tokens.heading); font-weight: 600; line-height: 1.25; }
          h1 { font-size: 1.875em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
          h4 { font-size: 1.125em; } h5 { font-size: 1em; } h6 { font-size: 0.875em; }
          blockquote {
            margin: 0; padding-left: 14px; border-left: 3px solid \(tokens.ink);
            color: \(tokens.muted);
          }
          code {
            font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 0.85em;
            color: \(tokens.accent); background: \(tokens.panel); border-radius: 4px; padding: 1px 4px;
          }
          pre {
            background: \(tokens.panel); border-radius: 10px; padding: 16px 22px; overflow-x: auto;
          }
          pre code { color: \(tokens.ink); background: none; padding: 0; }
          a { color: \(tokens.accent); }
          hr { border: 0; border-top: 1px solid \(tokens.hairline); }
          li { margin-bottom: 6px; }
        \(extra)
        """
    }

    /// Wraps rendered block HTML in a complete document.
    static func document(body: String, title: String, css: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escapedTitle)</title>
        <style>
        \(css)
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}
```

- [ ] **Step 4: Point `PDFExporter` at the shared stylesheet**

In `Sources/Marginal/Export/PDFExporter.swift`, replace the whole `static func pageHTML(markdown:title:)` (currently lines 49–89, the inline `<style>` block and hand-built document) with:

```swift
    /// Wraps the rendered markdown body in a printable page styled on the design tokens.
    static func pageHTML(markdown: String, title: String) -> String {
        MarkdownStylesheet.document(
            body: MarkdownHTMLRenderer.html(fromMarkdown: markdown),
            title: title,
            css: MarkdownStylesheet.printCSS
        )
    }
```

- [ ] **Step 5: Run the new tests plus the existing PDF tests**

Run: `xcodegen generate && git status --short`
Expected: `Info.plist`/`Marginal.entitlements` NOT modified.

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/MarkdownStylesheetTests -only-testing:MarginalTests/PDFExporterIntegrationTests`
Expected: PASS. `PDFExporterIntegrationTests` must still pass unchanged.

Note that the extraction is **not** byte-identical for print: the shared `rules()` gives print two
things the old inline CSS lacked — explicit `h4`/`h5`/`h6` sizes (previously left at the WebKit
default) and a muted blockquote colour (`#6B6A67`, previously inheriting body ink). Both are
design-token values and both are intentional: print inheriting the screen's refinements is the
point of having one stylesheet. Exported PDFs containing `####`-or-deeper headings, or
blockquotes, will look slightly different from before. Task 11's CHANGELOG entry records this.

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownStylesheet.swift Sources/Marginal/Export/PDFExporter.swift Tests/MarginalTests/MarkdownStylesheetTests.swift
git commit -m "refactor: extract MarkdownStylesheet from PDFExporter, add dark variant"
```

---

## Task 4: `data-line` anchors and caret↔block mapping in `MarkdownHTMLRenderer`

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownHTMLRenderer.swift`
- Test: `Tests/MarginalTests/MarkdownHTMLRendererTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces, on `MarkdownHTMLRenderer`:
  - `static func html(fromMarkdown: String) -> String` — unchanged signature, now emits `data-line="N"` on every block element.
  - `static func blockSourceLines(fromMarkdown: String) -> [Int]` — the 1-based source line of every emitted block, in document order.
  - `static func blockLine(nearestAtOrBefore caretLine: Int, in blockLines: [Int]) -> Int?` — the greatest element of `blockLines` not exceeding `caretLine`, or the first block when the caret precedes all blocks, or nil when there are no blocks.

  Task 6 uses all three; Task 8 uses the mapping.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MarginalTests/MarkdownHTMLRendererTests.swift`:

```swift
    // MARK: - data-line anchors

    func testEveryBlockKindCarriesItsSourceLine() {
        let markdown = """
        # Title

        A paragraph.

        - one
        - two

        > quoted

        ---

        ```swift
        let x = 1
        ```
        """
        let html = MarkdownHTMLRenderer.html(fromMarkdown: markdown)
        XCTAssertTrue(html.contains("<h1 data-line=\"1\">"), html)
        XCTAssertTrue(html.contains("<p data-line=\"3\">"), html)
        XCTAssertTrue(html.contains("<ul data-line=\"5\">"), html)
        XCTAssertTrue(html.contains("<blockquote data-line=\"8\">"), html)
        XCTAssertTrue(html.contains("<hr data-line=\"10\">"), html)
        XCTAssertTrue(html.contains("<pre data-line=\"12\">"), html)
    }

    // A paragraph's soft newlines collapse into one <p>, so the anchor is the FIRST line.
    func testMultiLineParagraphAnchorsToItsFirstLine() {
        let markdown = "# T\n\nline one\nline two\nline three\n\n## Next"
        let html = MarkdownHTMLRenderer.html(fromMarkdown: markdown)
        XCTAssertTrue(html.contains("<p data-line=\"3\">line one line two line three</p>"), html)
        XCTAssertTrue(html.contains("<h2 data-line=\"7\">"), html)
    }

    func testBlockSourceLinesInDocumentOrder() {
        let markdown = "# T\n\npara\n\n- item\n"
        XCTAssertEqual(MarkdownHTMLRenderer.blockSourceLines(fromMarkdown: markdown), [1, 3, 5])
    }

    func testBlockSourceLinesIsEmptyForEmptyDocument() {
        XCTAssertEqual(MarkdownHTMLRenderer.blockSourceLines(fromMarkdown: ""), [])
    }

    // MARK: - caret line -> block mapping

    func testBlockLineMapsToTheBlockContainingTheCaret() {
        let blocks = [1, 3, 7]
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 1, in: blocks), 1)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 2, in: blocks), 1)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 5, in: blocks), 3)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 7, in: blocks), 7)
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 99, in: blocks), 7)
    }

    // A caret above the first block (e.g. leading blank lines) still lands somewhere sensible.
    func testCaretBeforeFirstBlockMapsToFirstBlock() {
        XCTAssertEqual(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 1, in: [4, 9]), 4)
    }

    func testNoBlocksMapsToNil() {
        XCTAssertNil(MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: 3, in: []))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/MarkdownHTMLRendererTests`
Expected: FAIL — `blockSourceLines`/`blockLine` don't exist, and the anchor assertions fail because tags carry no attributes.

- [ ] **Step 3: Refactor `html(fromMarkdown:)` to produce line-tagged blocks**

In `Sources/Marginal/Editor/MarkdownHTMLRenderer.swift`:

First add the line-number helpers below the existing `advance(past:in:)`:

```swift
    /// Every line's start index, so a block's start index can be turned into a 1-based line
    /// number with a binary search rather than a rescan per block.
    private static func lineStarts(in text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\n" {
                starts.append(text.index(after: index))
            }
            index = text.index(after: index)
        }
        return starts
    }

    /// The 1-based line number containing `index`.
    private static func lineNumber(at index: String.Index, lineStarts: [String.Index]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= index {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }
```

Then change the entry points. Replace the existing `static func html(fromMarkdown:)` signature line and its `guard`/`return` with a private block-producing core plus two thin public entry points. Concretely: rename the existing function body into `private static func blocks(fromMarkdown text: String) -> [(line: Int, html: String)]`, and add:

```swift
    static func html(fromMarkdown text: String) -> String {
        blocks(fromMarkdown: text).map(\.html).joined(separator: "\n")
    }

    /// The 1-based source line each emitted block starts at, in document order. Paired with the
    /// `data-line` attributes in the HTML, this lets the editor map a caret line to a rendered
    /// block and back.
    static func blockSourceLines(fromMarkdown text: String) -> [Int] {
        blocks(fromMarkdown: text).map(\.line)
    }

    /// The greatest block line not exceeding `caretLine` — i.e. the block the caret sits in.
    /// Falls back to the first block when the caret precedes all of them, and to nil when the
    /// document renders no blocks at all.
    static func blockLine(nearestAtOrBefore caretLine: Int, in blockLines: [Int]) -> Int? {
        guard let first = blockLines.first else { return nil }
        return blockLines.last { $0 <= caretLine } ?? first
    }
```

- [ ] **Step 4: Emit the anchors inside `blocks(fromMarkdown:)`**

Inside the renamed `blocks(fromMarkdown:)`, change the `guard`, add a line table, change `blocks` to hold pairs, and add `data-line` to each emitted tag:

```swift
    private static func blocks(fromMarkdown text: String) -> [(line: Int, html: String)] {
        guard !text.isEmpty else { return [] }

        let headers = MarkdownParser.parseHeaders(in: text)
        let listItems = MarkdownParser.parseListItems(in: text)
        let blockquotes = MarkdownParser.parseBlockquotes(in: text)
        let horizontalRules = MarkdownParser.parseHorizontalRules(in: text)
        let codeBlocks = MarkdownParser.parseFencedCodeBlocks(in: text)
        let starts = lineStarts(in: text)

        var blocks: [(line: Int, html: String)] = []
        var index = text.startIndex

        while index < text.endIndex {
            let line = lineNumber(at: index, lineStarts: starts)

            if let codeBlock = codeBlocks.first(where: { $0.openingFenceRange.lowerBound == index }) {
                let languageAttribute = codeBlock.language.map { " class=\"language-\(htmlEscape($0))\"" } ?? ""
                blocks.append((line, "<pre data-line=\"\(line)\"><code\(languageAttribute)>\(htmlEscape(String(text[codeBlock.contentRange])))</code></pre>"))
                index = advance(past: codeBlock.openingFenceRange.lowerBound..<codeBlock.closingFenceRange.upperBound, in: text)
                continue
            }
            if let header = headers.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append((line, "<h\(header.level) data-line=\"\(line)\">\(inlineHTML(for: String(text[header.contentRange])))</h\(header.level)>"))
                index = advance(past: header.lineRange, in: text)
                continue
            }
            if let rule = horizontalRules.first(where: { $0.lineRange.lowerBound == index }) {
                blocks.append((line, "<hr data-line=\"\(line)\">"))
                index = advance(past: rule.lineRange, in: text)
                continue
            }
            if let item = listItems.first(where: { $0.lineRange.lowerBound == index }) {
                var groupItems = [item]
                var cursor = advance(past: item.lineRange, in: text)
                while let next = listItems.first(where: { $0.lineRange.lowerBound == cursor }), sameListKind(next.kind, item.kind) {
                    groupItems.append(next)
                    cursor = advance(past: next.lineRange, in: text)
                }
                let tag = isOrdered(item.kind) ? "ol" : "ul"
                let items = groupItems.map { "<li>\(inlineHTML(for: listItemText($0, in: text)))</li>" }.joined()
                blocks.append((line, "<\(tag) data-line=\"\(line)\">\(items)</\(tag)>"))
                index = cursor
                continue
            }
            if let quote = blockquotes.first(where: { $0.lineRange.lowerBound == index }) {
                var groupLines = [String(text[quote.contentRange])]
                var cursor = advance(past: quote.lineRange, in: text)
                while let next = blockquotes.first(where: { $0.lineRange.lowerBound == cursor }) {
                    groupLines.append(String(text[next.contentRange]))
                    cursor = advance(past: next.lineRange, in: text)
                }
                blocks.append((line, "<blockquote data-line=\"\(line)\"><p>\(inlineHTML(for: groupLines.joined(separator: " ")))</p></blockquote>"))
                index = cursor
                continue
            }

            let firstLineRange = lineRange(at: index, in: text)
            let firstLine = String(text[firstLineRange])
            if firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
                index = advance(past: firstLineRange, in: text)
                continue
            }

            var paragraphLines = [firstLine]
            var cursor = advance(past: firstLineRange, in: text)
            while cursor < text.endIndex, !isBlockStart(at: cursor, headers: headers, listItems: listItems, blockquotes: blockquotes, horizontalRules: horizontalRules, codeBlocks: codeBlocks) {
                let range = lineRange(at: cursor, in: text)
                let lineText = String(text[range])
                if lineText.trimmingCharacters(in: .whitespaces).isEmpty { break }
                paragraphLines.append(lineText)
                cursor = advance(past: range, in: text)
            }
            blocks.append((line, "<p data-line=\"\(line)\">\(inlineHTML(for: paragraphLines.joined(separator: " ")))</p>"))
            index = cursor
        }

        return blocks
    }
```

- [ ] **Step 5: Run the full renderer suite**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/MarkdownHTMLRendererTests`
Expected: PASS, including every pre-existing test in the file. Pre-existing tests that assert on exact tag strings like `"<p>"` will now fail — update those assertions to include the `data-line` attribute; do NOT weaken them to `contains("<p")`.

- [ ] **Step 6: Run the PDF suite too — the exported HTML changed shape**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/PDFExporterIntegrationTests`
Expected: PASS. `data-line` attributes are inert in print.

- [ ] **Step 7: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownHTMLRenderer.swift Tests/MarginalTests/MarkdownHTMLRendererTests.swift
git commit -m "feat: data-line source anchors and caret-to-block mapping in the HTML renderer"
```

---

## Task 5: Code-mode styling — `codeSourceAttributedString`

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift` (add a function; `plainSourceAttributedString` stays for now and is deleted in Task 8)
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`

**Interfaces:**
- Consumes: `MarkdownDocumentModel` (existing).
- Produces: `static func codeSourceAttributedString(for text: String, model: MarkdownDocumentModel, font: NSFont) -> NSAttributedString`. Task 8 calls it.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MarginalTests/MarkdownStylerTests.swift`:

```swift
    // MARK: - Code mode

    private func codeModeString(_ markdown: String, size: CGFloat = 16) -> NSAttributedString {
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: markdown),
            headers: MarkdownParser.parseHeaders(in: markdown),
            listItems: MarkdownParser.parseListItems(in: markdown),
            links: MarkdownParser.parseLinks(in: markdown),
            blockquotes: MarkdownParser.parseBlockquotes(in: markdown),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: markdown),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: markdown),
            tables: MarkdownParser.parseTables(in: markdown),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: markdown)
        )
        return MarkdownStyler.codeSourceAttributedString(
            for: markdown,
            model: model,
            font: NSFont.systemFont(ofSize: size)
        )
    }

    private func colour(_ attributed: NSAttributedString, at location: Int) -> NSColor? {
        attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    // The whole point of Code mode: no size variation anywhere, so nothing ever reflows while
    // the caret moves or text is typed.
    func testCodeModeUsesOneFixedPitchSizeForEveryCharacter() {
        let markdown = "# Big heading\n\nbody **bold** text\n\n> quote\n\n---\n\n- [x] task\n"
        let attributed = codeModeString(markdown, size: 15)
        var sizesSeen: Set<CGFloat> = []
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let font = value as? NSFont else {
                return XCTFail("every character must carry a font; range \(range) had none")
            }
            XCTAssertTrue(font.isFixedPitch, "Code mode must be monospace throughout")
            sizesSeen.insert(font.pointSize)
        }
        XCTAssertEqual(sizesSeen, [15])
    }

    // Nothing is hidden in Code mode — the hidden-delimiter trick must not appear.
    func testCodeModeNeverHidesAnything() {
        let attributed = codeModeString("**bold** and [link](https://example.com)")
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            XCTAssertNotEqual((value as? NSFont)?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
        }
        attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            XCTAssertNotEqual(value as? NSColor, NSColor.clear)
        }
    }

    func testHeaderMarkerIsTintedAccentAndContentIsNot() {
        let attributed = codeModeString("## Heading")
        XCTAssertEqual(colour(attributed, at: 0), DesignPalette.accent)   // "#"
        XCTAssertEqual(colour(attributed, at: 1), DesignPalette.accent)   // "#"
        XCTAssertEqual(colour(attributed, at: 3), NSColor.labelColor)     // "H"
    }

    func testInlineStyleDelimitersAreTintedAccent() {
        let attributed = codeModeString("a **b** c")
        // "a **b** c" -- offsets: 0'a' 1' ' 2'*' 3'*' 4'b' 5'*' 6'*' 7' ' 8'c'
        XCTAssertEqual(colour(attributed, at: 2), DesignPalette.accent)   // first "*"
        XCTAssertEqual(colour(attributed, at: 4), NSColor.labelColor)     // "b"
        XCTAssertEqual(colour(attributed, at: 6), DesignPalette.accent)   // closing "*"
    }

    func testListBulletIsFaintAndTaskMarkerIsAccent() {
        let attributed = codeModeString("- [x] done")
        XCTAssertEqual(colour(attributed, at: 0), DesignPalette.textFaint) // "-"
        XCTAssertEqual(colour(attributed, at: 2), DesignPalette.accent)    // "["
        XCTAssertEqual(colour(attributed, at: 6), NSColor.labelColor)      // "d" of "done"
    }

    func testLinkSyntaxIsTintedButLinkTextIsNot() {
        let attributed = codeModeString("[text](https://example.com)")
        XCTAssertEqual(colour(attributed, at: 0), DesignPalette.accent)   // "["
        XCTAssertEqual(colour(attributed, at: 1), NSColor.labelColor)     // "t"
        XCTAssertEqual(colour(attributed, at: 5), DesignPalette.accent)   // "]"
        XCTAssertEqual(colour(attributed, at: 7), DesignPalette.accent)   // inside the URL
    }

    func testBlockquoteMarkerAndHorizontalRuleAreTinted() {
        XCTAssertEqual(colour(codeModeString("> quoted"), at: 0), DesignPalette.accent)
        XCTAssertEqual(colour(codeModeString("---"), at: 1), DesignPalette.accent)
    }

    func testCodeFencesAreTintedAndFenceContentIsNot() {
        let attributed = codeModeString("```swift\nlet x = 1\n```\n")
        XCTAssertEqual(colour(attributed, at: 0), DesignPalette.accent)   // opening backtick
        XCTAssertEqual(colour(attributed, at: 9), NSColor.labelColor)     // "l" of "let"
    }

    func testTablePipesAreFaint() {
        let attributed = codeModeString("| a | b |\n| --- | --- |\n| 1 | 2 |\n")
        XCTAssertEqual(colour(attributed, at: 0), DesignPalette.textFaint) // leading "|"
        XCTAssertEqual(colour(attributed, at: 2), NSColor.labelColor)      // "a"
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — `codeSourceAttributedString` doesn't exist.

- [ ] **Step 3: Write the implementation**

In `Sources/Marginal/Editor/MarkdownStyler.swift`, add directly above the existing `plainSourceAttributedString`:

```swift
    /// Code mode: the literal source in one fixed-pitch size, with markdown's own markers
    /// tinted so structure is legible without anything hiding, moving, or changing size.
    ///
    /// Deliberately unlike `attributedString(for:model:baseFont:cursorLocation:)`: there is no
    /// cursor reveal, no hidden-delimiter font, no per-heading point size, and no paragraph
    /// indentation. A uniform size is the whole feature — it is what stops lines reflowing
    /// under the caret while editing.
    static func codeSourceAttributedString(
        for text: String,
        model: MarkdownDocumentModel,
        font: NSFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])

        func tint(_ range: Range<String.Index>, _ color: NSColor) {
            guard !range.isEmpty else { return }
            result.addAttribute(.foregroundColor, value: color, range: NSRange(range, in: text))
        }

        // Structural markers: violet, the app's single accent.
        for header in model.headers {
            tint(header.markerRange, DesignPalette.accent)
        }
        for style in model.inlineStyles {
            tint(style.openingDelimiterRange, DesignPalette.accent)
            tint(style.closingDelimiterRange, DesignPalette.accent)
        }
        for quote in model.blockquotes {
            tint(quote.markerRange, DesignPalette.accent)
        }
        for rule in model.horizontalRules {
            tint(rule.lineRange, DesignPalette.accent)
        }
        for codeBlock in model.codeBlocks {
            tint(codeBlock.openingFenceRange, DesignPalette.accent)
            tint(codeBlock.closingFenceRange, DesignPalette.accent)
        }
        for link in model.links {
            // Everything outside the link's own text: "[", "](url)".
            tint(link.fullRange.lowerBound..<link.textRange.lowerBound, DesignPalette.accent)
            tint(link.textRange.upperBound..<link.fullRange.upperBound, DesignPalette.accent)
        }

        // List scaffolding: faint, so bullets recede while their task checkboxes stay legible.
        for item in model.listItems {
            tint(item.markerRange, DesignPalette.textFaint)
            if let taskMarkerRange = item.taskMarkerRange {
                tint(taskMarkerRange, DesignPalette.accent)
            }
        }
        for table in model.tables {
            for pipe in table.headerRow.pipeRanges { tint(pipe, DesignPalette.textFaint) }
            tint(table.separatorRowRange, DesignPalette.textFaint)
            for row in table.bodyRows {
                for pipe in row.pipeRanges { tint(pipe, DesignPalette.textFaint) }
            }
        }

        return result
    }
```

- [ ] **Step 4: Run the styler suite**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS, including every pre-existing test in the file (Live-mode styling is untouched).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownStyler.swift Tests/MarginalTests/MarkdownStylerTests.swift
git commit -m "feat: Code-mode source styling with tinted markers at a uniform size"
```

---

## Task 6: `PreviewWebView` — the read-only rendered surface

**Files:**
- Create: `Sources/Marginal/Editor/PreviewWebView.swift`
- Test: `Tests/MarginalTests/PreviewWebViewTests.swift`

**Interfaces:**
- Consumes: `MarkdownHTMLRenderer.html(fromMarkdown:)`, `MarkdownHTMLRenderer.blockSourceLines(fromMarkdown:)`, `MarkdownHTMLRenderer.blockLine(nearestAtOrBefore:in:)`, `MarkdownStylesheet.screenCSS(appearance:bodyPointSize:)`, `MarkdownStylesheet.document(body:title:css:)`.
- Produces: `@MainActor final class PreviewWebView: NSView` with
  - `func load(markdown: String, title: String, fontSize: CGFloat, appearance: MarkdownStylesheet.Appearance)`
  - `func scrollToSourceLine(_ line: Int)`
  - `func topmostVisibleSourceLine(completion: @escaping (Int?) -> Void)`
  - `static func documentHTML(markdown: String, title: String, fontSize: CGFloat, appearance: MarkdownStylesheet.Appearance) -> String`
  - `static func scrollScript(forSourceLine line: Int) -> String`
  - `static let topmostVisibleLineScript: String`

  Task 8 uses the instance methods.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MarginalTests/PreviewWebViewTests.swift`:

```swift
import XCTest
@testable import Marginal

@MainActor
final class PreviewWebViewTests: XCTestCase {

    func testDocumentHTMLCombinesRendererAndStylesheet() {
        let html = PreviewWebView.documentHTML(
            markdown: "# Title\n\nbody",
            title: "notes.md",
            fontSize: 17,
            appearance: .light
        )
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<title>notes.md</title>"), html)
        XCTAssertTrue(html.contains("<h1 data-line=\"1\">Title</h1>"), html)
        XCTAssertTrue(html.contains("font-size: 17px"), html)
        XCTAssertTrue(html.contains("#FFFEFC"), html)
    }

    func testDocumentHTMLFollowsAppearance() {
        let dark = PreviewWebView.documentHTML(markdown: "x", title: "t", fontSize: 16, appearance: .dark)
        XCTAssertTrue(dark.contains("#1E1E1D"), dark)
    }

    // The soft-newline collapse is the whole reason Preview exists — assert it end to end.
    func testHardWrappedParagraphRendersAsOneFlowingParagraph() {
        let html = PreviewWebView.documentHTML(
            markdown: "one\ntwo\nthree",
            title: "t",
            fontSize: 16,
            appearance: .light
        )
        XCTAssertTrue(html.contains("<p data-line=\"1\">one two three</p>"), html)
    }

    func testScrollScriptTargetsTheAnchorForThatLine() {
        let script = PreviewWebView.scrollScript(forSourceLine: 12)
        XCTAssertTrue(script.contains("[data-line=\"12\"]"), script)
        XCTAssertTrue(script.contains("scrollIntoView"), script)
    }

    func testTopmostVisibleLineScriptReadsADataLineAttribute() {
        XCTAssertTrue(PreviewWebView.topmostVisibleLineScript.contains("data-line"))
    }

    // A freshly built view must be usable before any load: no crash, no anchors.
    func testNewViewHasNoAnchorsYet() {
        let view = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(view.blockSourceLines, [])
    }

    func testLoadRecordsTheDocumentsBlockAnchors() {
        let view = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.load(markdown: "# T\n\npara\n\n- item\n", title: "t", fontSize: 16, appearance: .light)
        XCTAssertEqual(view.blockSourceLines, [1, 3, 5])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/PreviewWebViewTests`
Expected: FAIL — `cannot find 'PreviewWebView' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Marginal/Editor/PreviewWebView.swift`:

```swift
import AppKit
import WebKit

/// Preview mode's surface: a read-only WKWebView showing the document rendered through the same
/// MarkdownHTMLRenderer that drives PDF export and Copy as HTML. Because it renders real HTML, a
/// paragraph's soft newlines collapse into flowing text — which the AppKit text view can never do,
/// since its storage is the literal file.
///
/// Every emitted block carries a `data-line` attribute, so scroll position can be handed back and
/// forth with the editing surfaces.
@MainActor
final class PreviewWebView: NSView {

    private let webView: WKWebView

    /// The 1-based source line of each rendered block, in document order. Empty until `load`.
    private(set) var blockSourceLines: [Int] = []

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        // The rendered HTML comes from a user's own document, so page content must not be able
        // to run script. This flag governs *page* content only -- evaluateJavaScript, which this
        // class uses for scroll positioning, is host-driven and keeps working with it off.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: frameRect, configuration: configuration)
        super.init(frame: frameRect)

        webView.translatesAutoresizingMaskIntoConstraints = false
        // The document's own paper colour comes from the stylesheet; keep the web view itself
        // from flashing white behind it on load. underPageBackgroundColor is the public API for
        // this (macOS 12+) -- do not reach for the private `setValue(false, forKey:
        // "drawsBackground")` KVC hack.
        webView.underPageBackgroundColor = .clear
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(markdown: String, title: String, fontSize: CGFloat, appearance: MarkdownStylesheet.Appearance) {
        blockSourceLines = MarkdownHTMLRenderer.blockSourceLines(fromMarkdown: markdown)
        webView.loadHTMLString(
            Self.documentHTML(markdown: markdown, title: title, fontSize: fontSize, appearance: appearance),
            baseURL: nil
        )
    }

    /// Scrolls the block containing `line` to the top of the view.
    func scrollToSourceLine(_ line: Int) {
        guard let anchor = MarkdownHTMLRenderer.blockLine(nearestAtOrBefore: line, in: blockSourceLines) else { return }
        webView.evaluateJavaScript(Self.scrollScript(forSourceLine: anchor))
    }

    /// The source line of the topmost block currently visible, for handing position back to the
    /// editing surfaces. Completes with nil when nothing is rendered yet.
    func topmostVisibleSourceLine(completion: @escaping (Int?) -> Void) {
        webView.evaluateJavaScript(Self.topmostVisibleLineScript) { value, _ in
            completion((value as? NSNumber)?.intValue)
        }
    }

    static func documentHTML(
        markdown: String,
        title: String,
        fontSize: CGFloat,
        appearance: MarkdownStylesheet.Appearance
    ) -> String {
        MarkdownStylesheet.document(
            body: MarkdownHTMLRenderer.html(fromMarkdown: markdown),
            title: title,
            css: MarkdownStylesheet.screenCSS(appearance: appearance, bodyPointSize: fontSize)
        )
    }

    static func scrollScript(forSourceLine line: Int) -> String {
        """
        (function () {
          var el = document.querySelector('[data-line="\(line)"]');
          if (el) { el.scrollIntoView({ block: 'start' }); }
        })();
        """
    }

    /// Returns the `data-line` of the first block whose bottom edge is still below the top of the
    /// viewport — i.e. the block the reader is looking at.
    static let topmostVisibleLineScript = """
    (function () {
      var blocks = document.querySelectorAll('[data-line]');
      for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].getBoundingClientRect().bottom > 0) {
          return parseInt(blocks[i].getAttribute('data-line'), 10);
        }
      }
      return null;
    })();
    """
}
```

- [ ] **Step 4: Regenerate and run the tests**

Run: `xcodegen generate && git status --short`
Expected: `Info.plist`/`Marginal.entitlements` NOT modified.

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/PreviewWebViewTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/PreviewWebView.swift Tests/MarginalTests/PreviewWebViewTests.swift
git commit -m "feat: PreviewWebView renders the document as HTML with source-line anchors"
```

---

## Task 7: `EditorModeController` — one mode, one render dispatch

**Files:**
- Create: `Sources/Marginal/Editor/EditorModeController.swift`
- Test: `Tests/MarginalTests/EditorModeControllerTests.swift`

**Interfaces:**
- Consumes: `EditorMode` (Task 1).
- Produces:
  - `@MainActor protocol EditorModeHost: AnyObject { func renderCode(); func renderLive(); func renderPreview(); func applyChrome(for mode: EditorMode) }`
  - `@MainActor final class EditorModeController` with `init(host: EditorModeHost, defaults: UserDefaults = .standard)`, `var mode: EditorMode { get }`, `func setMode(_ mode: EditorMode)`, `func render()`, `func activate()`.

  Task 8 conforms `DocumentViewController` to `EditorModeHost` and owns one controller.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MarginalTests/EditorModeControllerTests.swift`:

```swift
import XCTest
@testable import Marginal

@MainActor
final class EditorModeControllerTests: XCTestCase {

    private final class HostSpy: EditorModeHost {
        var calls: [String] = []
        var chromeModes: [EditorMode] = []
        func renderCode() { calls.append("code") }
        func renderLive() { calls.append("live") }
        func renderPreview() { calls.append("preview") }
        func applyChrome(for mode: EditorMode) { chromeModes.append(mode) }
    }

    private func emptyDefaults() -> UserDefaults {
        let suite = "EditorModeControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testStartsInThePersistedMode() {
        let defaults = emptyDefaults()
        EditorMode.code.persist(in: defaults)
        let controller = EditorModeController(host: HostSpy(), defaults: defaults)
        XCTAssertEqual(controller.mode, .code)
    }

    func testInitDoesNotRenderUntilActivated() {
        let host = HostSpy()
        _ = EditorModeController(host: host, defaults: emptyDefaults())
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertTrue(host.chromeModes.isEmpty)
    }

    func testActivateAppliesChromeThenRendersOnce() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.activate()
        XCTAssertEqual(host.chromeModes, [.live])
        XCTAssertEqual(host.calls, ["live"])
    }

    // The reason this class exists: exactly one render path runs per event, from one call site.
    func testRenderDispatchesToExactlyOneSurface() {
        for (mode, expected) in [(EditorMode.code, "code"), (.live, "live"), (.preview, "preview")] {
            let host = HostSpy()
            let controller = EditorModeController(host: host, defaults: emptyDefaults())
            controller.setMode(mode)
            host.calls.removeAll()
            controller.render()
            XCTAssertEqual(host.calls, [expected], "\(mode) rendered \(host.calls)")
        }
    }

    func testSetModeAppliesChromeAndRendersTheNewMode() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.setMode(.preview)
        XCTAssertEqual(controller.mode, .preview)
        XCTAssertEqual(host.chromeModes, [.preview])
        XCTAssertEqual(host.calls, ["preview"])
    }

    func testSetModePersistsTheChoice() {
        let defaults = emptyDefaults()
        let controller = EditorModeController(host: HostSpy(), defaults: defaults)
        controller.setMode(.code)
        XCTAssertEqual(EditorMode.persisted(in: defaults), .code)
    }

    // Re-selecting the active mode must not reload Preview or restyle the whole document.
    func testSetModeToTheCurrentModeIsANoOp() {
        let host = HostSpy()
        let controller = EditorModeController(host: host, defaults: emptyDefaults())
        controller.setMode(.live)
        XCTAssertTrue(host.calls.isEmpty)
        XCTAssertTrue(host.chromeModes.isEmpty)
    }

    func testEveryOrderedPairOfModesTransitionsCleanly() {
        for from in EditorMode.allCases {
            for to in EditorMode.allCases where to != from {
                let host = HostSpy()
                let controller = EditorModeController(host: host, defaults: emptyDefaults())
                controller.setMode(from)
                host.calls.removeAll()
                host.chromeModes.removeAll()
                controller.setMode(to)
                XCTAssertEqual(controller.mode, to)
                XCTAssertEqual(host.chromeModes, [to], "\(from) -> \(to)")
                XCTAssertEqual(host.calls.count, 1, "\(from) -> \(to) rendered \(host.calls)")
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/EditorModeControllerTests`
Expected: FAIL — `cannot find 'EditorModeController' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Marginal/Editor/EditorModeController.swift`:

```swift
import Foundation

/// The surfaces `EditorModeController` drives. `DocumentViewController` is the only real
/// conformer; the protocol exists so mode dispatch can be tested without a window.
@MainActor
protocol EditorModeHost: AnyObject {
    /// Render the document as tinted monospace source.
    func renderCode()
    /// Render the document as WYSIWYG with reveal-at-cursor.
    func renderLive()
    /// Render the document as read-only HTML.
    func renderPreview()
    /// Show/hide the surfaces and chrome (gutter, status bar contents) this mode needs.
    /// Always called before the matching render.
    func applyChrome(for mode: EditorMode)
}

/// Owns which of the three editor modes is active, and is the single place that decides which
/// render path runs.
///
/// Before this existed, `DocumentViewController` repeated the branch
/// `isShowingSource ? applyPlainSourceRendering() : restyle(…)` at four separate call sites —
/// the mode toggle, text changes, selection changes and font-size changes. A three-way version
/// of that, duplicated four times, is how a feature like this rots. Callers now say `render()`
/// and this class decides what that means.
@MainActor
final class EditorModeController {

    private(set) var mode: EditorMode
    private weak var host: EditorModeHost?
    private let defaults: UserDefaults

    init(host: EditorModeHost, defaults: UserDefaults = .standard) {
        self.host = host
        self.defaults = defaults
        self.mode = EditorMode.persisted(in: defaults)
    }

    /// Applies the starting mode's chrome and renders it. Separate from `init` so a host can
    /// finish building its views before anything draws.
    func activate() {
        applyAndRender()
    }

    /// Switches mode: persists the choice, swaps the chrome, renders the new surface.
    /// Selecting the mode that's already active does nothing — re-rendering Preview or
    /// restyling the whole document for a no-op change would be visible work for no reason.
    func setMode(_ newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        newMode.persist(in: defaults)
        applyAndRender()
    }

    /// Re-renders the active surface. The one call site for text changes, selection changes and
    /// font-size changes.
    func render() {
        guard let host else { return }
        switch mode {
        case .code: host.renderCode()
        case .live: host.renderLive()
        case .preview: host.renderPreview()
        }
    }

    private func applyAndRender() {
        host?.applyChrome(for: mode)
        render()
    }
}
```

- [ ] **Step 4: Regenerate and run the tests**

Run: `xcodegen generate && git status --short`
Expected: `Info.plist`/`Marginal.entitlements` NOT modified.

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/EditorModeControllerTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Marginal/Editor/EditorModeController.swift Tests/MarginalTests/EditorModeControllerTests.swift
git commit -m "feat: EditorModeController collapses render dispatch to one call site"
```

---

## Task 8: Wire the three modes into `DocumentViewController`

**Files:**
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Modify: `Sources/Marginal/Editor/MarkdownTextView.swift:88-108` (remove the `"P"` case) and `:4-9` (remove the protocol method)
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift` (delete `plainSourceAttributedString`)
- Test: `Tests/MarginalTests/DocumentViewControllerTests.swift`

**Interfaces:**
- Consumes: `EditorMode`, `EditorModeController`, `EditorModeHost`, `PreviewWebView`, `MarkdownStyler.codeSourceAttributedString`, `MarkdownHTMLRenderer.blockLine(nearestAtOrBefore:in:)`, `DocumentStatistics`.
- Produces on `DocumentViewController`: `var editorMode: EditorMode { get }`, `func setEditorMode(_ mode: EditorMode)`, `@objc func selectEditorMode(_ sender: NSMenuItem)` (reads `sender.tag` as the `EditorMode.allCases` index). Task 9 targets `selectEditorMode(_:)` from the View menu; Task 10 targets `setEditorMode(_:)` from the status bar.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/MarginalTests/DocumentViewControllerTests.swift`:

```swift
    // MARK: - Editor modes

    /// A controller whose starting mode is always `.live`, whatever mode this Mac's real
    /// UserDefaults happens to hold — otherwise every assertion below depends on what the
    /// developer last clicked.
    private func loadedController(_ markdown: String = "# Title\n\nbody text\n") -> DocumentViewController {
        let controller = DocumentViewController()
        _ = controller.view          // force loadView()
        let suite = "DocumentViewControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        controller.editorModeDefaults = defaults
        controller.loadInitialText(markdown)
        return controller
    }

    func testSettingCodeModeRendersMonospaceSourceAtOneSize() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        XCTAssertEqual(controller.editorMode, .code)

        let storage = controller.textView.textStorage!
        var sizes: Set<CGFloat> = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let font = value as? NSFont else { return XCTFail("missing font") }
            XCTAssertTrue(font.isFixedPitch)
            sizes.insert(font.pointSize)
        }
        XCTAssertEqual(sizes.count, 1, "Code mode must not vary font size: \(sizes)")
    }

    func testSettingLiveModeRestoresWysiwygHeadingSize() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        controller.setEditorMode(.live)
        XCTAssertEqual(controller.editorMode, .live)

        let storage = controller.textView.textStorage!
        let headingFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let bodyFont = storage.attribute(.font, at: storage.length - 2, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        XCTAssertGreaterThan(headingFont!.pointSize, bodyFont!.pointSize)
    }

    // The source of truth never changes shape, whatever the mode.
    func testTextStorageStaysTheLiteralSourceInEveryMode() {
        let markdown = "# Title\n\none\ntwo\n"
        let controller = loadedController(markdown)
        for mode in EditorMode.allCases {
            controller.setEditorMode(mode)
            XCTAssertEqual(controller.textView.string, markdown, "\(mode) mutated the storage")
        }
    }

    func testPreviewModeShowsTheWebViewAndHidesTheGutter() {
        let controller = loadedController()
        controller.setEditorMode(.preview)
        XCTAssertEqual(controller.editorMode, .preview)
        XCTAssertFalse(controller.previewWebViewForTesting!.isHidden)
        XCTAssertTrue(controller.gutterViewForTesting.isHidden)
    }

    func testLeavingPreviewRestoresTheEditingSurface() {
        let controller = loadedController()
        controller.setEditorMode(.preview)
        controller.setEditorMode(.live)
        XCTAssertTrue(controller.previewWebViewForTesting!.isHidden)
        XCTAssertFalse(controller.gutterViewForTesting.isHidden)
    }

    // Preview is lazy: a document never previewed pays no web-process cost.
    func testWebViewIsNotCreatedUntilPreviewIsEntered() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        XCTAssertNil(controller.previewWebViewForTesting)
        controller.setEditorMode(.preview)
        XCTAssertNotNil(controller.previewWebViewForTesting)
    }

    func testSelectEditorModeMenuActionUsesTheSendersTag() {
        let controller = loadedController()
        let item = NSMenuItem(title: "Code", action: nil, keyEquivalent: "")
        item.tag = 0
        controller.selectEditorMode(item)
        XCTAssertEqual(controller.editorMode, .code)

        item.tag = 2
        controller.selectEditorMode(item)
        XCTAssertEqual(controller.editorMode, .preview)
    }

    func testEditingInCodeModeKeepsCodeRendering() {
        let controller = loadedController()
        controller.setEditorMode(.code)
        controller.textView.setSelectedRange(NSRange(location: controller.textView.string.count, length: 0))
        controller.textView.insertText("more", replacementRange: controller.textView.selectedRange())

        let storage = controller.textView.textStorage!
        let font = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.isFixedPitch, true, "typing must not knock Code mode back to Live")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/DocumentViewControllerTests`
Expected: FAIL — `setEditorMode`, `editorMode`, `previewWebViewForTesting`, `gutterViewForTesting`, `selectEditorMode` don't exist.

- [ ] **Step 3: Replace the source-toggle state with the mode controller**

In `Sources/Marginal/Document/DocumentViewController.swift`:

Replace the stored property `private var isShowingSource = false` (line 11) with:

```swift
    private var previewWebView: PreviewWebView?
    private var scrollView: NSScrollView!

    /// Where the mode controller reads and persists the mode. Tests point this at a throwaway
    /// suite so a developer's own last-used mode can never change what a test observes; it must
    /// be set before `loadInitialText`, which is what first touches `modeController`.
    var editorModeDefaults: UserDefaults = .standard
    private lazy var modeController = EditorModeController(host: self, defaults: editorModeDefaults)

    /// The active rendering mode.
    var editorMode: EditorMode { modeController.mode }
```

Add these test hooks immediately after (they exist so tests can assert on view state without
reaching into private storage):

```swift
    var previewWebViewForTesting: PreviewWebView? { previewWebView }
    var gutterViewForTesting: NSView { gutterView }
```

In `loadView()`, assign the scroll view to the new stored property — change
`let scrollView = NSScrollView()` to `let scrollView = NSScrollView()` followed by
`self.scrollView = scrollView` just before `self.textView = textView` at the end of the method.

- [ ] **Step 4: Replace `toggleShowSource` with the mode API and the host conformance**

Delete `toggleShowSource()` (lines 225–232) and `applyPlainSourceRendering()` (lines 238–248). In their place add:

```swift
    /// Switches rendering mode. Preserves reading position across the switch: leaving an editing
    /// surface scrolls Preview to the caret's block, and leaving Preview puts the caret on the
    /// topmost visible block's first line.
    func setEditorMode(_ mode: EditorMode) {
        guard mode != editorMode else { return }

        if editorMode == .preview, let previewWebView {
            // Capture the reading position before the web view goes away. The JS round-trip is
            // asynchronous, so the caret move lands just after the switch — which is fine, the
            // text view is already showing by then.
            previewWebView.topmostVisibleSourceLine { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self, let line else { return }
                    self.moveCaretToLine(line)
                }
            }
        }

        let caretLineBeforeSwitch = mode == .preview ? currentCaretLine() : nil
        modeController.setMode(mode)
        if let caretLineBeforeSwitch {
            previewWebView?.scrollToSourceLine(caretLineBeforeSwitch)
        }
    }

    /// View-menu action. `sender.tag` is the mode's index in `EditorMode.allCases`.
    @objc func selectEditorMode(_ sender: NSMenuItem) {
        guard EditorMode.allCases.indices.contains(sender.tag) else { return }
        setEditorMode(EditorMode.allCases[sender.tag])
    }

    /// The 1-based line the caret sits on, via the same status computation the status bar uses.
    private func currentCaretLine() -> Int {
        guard let cursor = currentCursorIndex() else { return 1 }
        let model = latestModel ?? MarkdownDocumentModel()
        return CursorStatus.status(for: textView.string, model: model, cursor: cursor).line
    }

    /// Puts the caret at the start of 1-based `line` and scrolls it into view.
    private func moveCaretToLine(_ line: Int) {
        let nsText = textView.string as NSString
        var location = 0
        var currentLine = 1
        while currentLine < line, location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(lineRange)
            currentLine += 1
        }
        let clamped = min(location, nsText.length)
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
        textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }
```

- [ ] **Step 5: Conform to `EditorModeHost`**

Add at the end of the file:

```swift
extension DocumentViewController: EditorModeHost {

    func renderCode() {
        let text = textView.string
        let model = parsedModel(for: text)
        applyRendering(
            MarkdownStyler.codeSourceAttributedString(
                for: text,
                model: model,
                font: NSFont.systemFont(ofSize: editorFontSize)
            )
        )
    }

    func renderLive() {
        restyle(cursorLocation: currentCursorIndex())
    }

    func renderPreview() {
        let webView = previewWebView ?? makePreviewWebView()
        webView.load(
            markdown: textView.string,
            title: document?.displayName ?? "Document",
            fontSize: editorFontSize,
            appearance: view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        )
    }

    func applyChrome(for mode: EditorMode) {
        let isPreview = mode == .preview
        if isPreview, previewWebView == nil {
            _ = makePreviewWebView()
        }
        previewWebView?.isHidden = !isPreview
        scrollView.isHidden = isPreview
        gutterView.isHidden = isPreview
        // NOTE: the status bar's Preview readout (word count / reading time) and its segmented
        // control are wired in Task 10, which is where those StatusBarView members are added.
        // Do not reference them here — they do not exist yet and this task must compile.
        if !isPreview {
            // Editing surfaces take focus back when Preview yields it.
            view.window?.makeFirstResponder(textView)
        }
        updateCursorChrome()
    }

    private func makePreviewWebView() -> PreviewWebView {
        let webView = PreviewWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor)
        ])
        previewWebView = webView
        return webView
    }
}
```

- [ ] **Step 6: Extract the shared parse and route every event through `render()`**

Still in `DocumentViewController.swift`, factor the model build out of `restyle` so `renderCode`
can share it. Replace the first eleven lines of `restyle(cursorLocation:)` (the `let text` line
through `latestModel = model`) with:

```swift
    private func parsedModel(for text: String) -> MarkdownDocumentModel {
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text),
            blockquotes: MarkdownParser.parseBlockquotes(in: text),
            horizontalRules: MarkdownParser.parseHorizontalRules(in: text),
            codeBlocks: MarkdownParser.parseFencedCodeBlocks(in: text),
            tables: MarkdownParser.parseTables(in: text),
            emojiShortcodes: MarkdownParser.parseEmojiShortcodes(in: text)
        )
        latestModel = model
        return model
    }

    /// Applies a fully-styled attributed string to the text storage in place, preserving the
    /// selection. Shared by Live and Code rendering — only the string differs.
    private func applyRendering(_ attributed: NSAttributedString) {
        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticEdit = true
        textView.textStorage?.beginEditing()
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            textView.textStorage?.setAttributes(attrs, range: range)
        }
        textView.textStorage?.endEditing()
        textView.setSelectedRange(selectedRange)
        isApplyingProgrammaticEdit = false
        // Horizontal rules are the first feature where revealing/hiding a marker changes an
        // entire line's font size (0.1pt <-> baseFont), which changes that line's height and
        // therefore shifts every line below it. NSTextView's automatic display invalidation
        // after the in-place setAttributes calls above redraws only the stale (pre-shift)
        // region, leaving lines below a revealed/hidden rule visually blank until some other
        // event forces a full redraw. The layout itself is always correct; only the drawn
        // pixels go stale. Forcing a full-view redraw after every render fixes it.
        textView.needsDisplay = true
    }

    private func restyle(cursorLocation: String.Index?) {
        let text = textView.string
        let model = parsedModel(for: text)
        applyRendering(
            MarkdownStyler.attributedString(
                for: text,
                model: model,
                baseFont: NSFont.systemFont(ofSize: editorFontSize),
                cursorLocation: cursorLocation
            )
        )
    }
```

Then replace all four duplicated `isShowingSource ? … : restyle(…)` branches with a single
`modeController.render()`:

- In `loadInitialText(_:)`: replace `restyle(cursorLocation: nil)` with `modeController.activate()`.
- In `textDidChange(_:)`: replace the `if isShowingSource { … } else { … }` block with `modeController.render()` — the body becomes:

```swift
    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        document?.text = textView.string
        document?.updateChangeCount(.changeDone)
        modeController.render()
        updateCursorChrome()
    }
```

- In `textViewDidChangeSelection(_:)`: replace the branch with `modeController.render()`. Guard against Preview, which has no selection to follow:

```swift
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit, editorMode != .preview else { return }
        modeController.render()
        updateCursorChrome()
    }
```

- In `setFontSize(_:)`: replace the branch with `modeController.render()`.

In `updateCursorChrome()`, return early when Preview owns the window — add after the `guard let gutterView, let statusBar else { return }` line:

```swift
        guard editorMode != .preview else { return }
```

- [ ] **Step 7: Retire the `⌘⇧P` toggle**

In `Sources/Marginal/Editor/MarkdownTextView.swift`, delete `func markdownTextViewToggleShowSource(_ textView: MarkdownTextView)` from the `MarkdownTextViewShortcutDelegate` protocol, and delete the `case "P":` branch (with its three-line comment) from `keyDown(with:)`.

In `DocumentViewController.swift`, delete the now-orphaned `markdownTextViewToggleShowSource(_:)` implementation.

In `Sources/Marginal/Editor/MarkdownStyler.swift`, delete `plainSourceAttributedString(for:font:)` — `codeSourceAttributedString` replaces it. If `MarkdownStylerTests` still references it, delete those assertions; the Task 5 tests cover Code mode properly.

- [ ] **Step 8: Run the full suite**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`
Expected: PASS, every suite. Existing `DocumentViewControllerTests` that exercised Show Source must be updated to the new mode API rather than deleted, unless they duplicate a Task 8 test.

- [ ] **Step 9: Commit**

```bash
git add Sources/Marginal Tests/MarginalTests
git commit -m "feat: three editor modes wired through DocumentViewController"
```

---

## Task 9: The View menu — `⌘⌥1/2/3`, checkmarks, and zoom

**Files:**
- Modify: `Sources/Marginal/App/AppDelegate.swift:81-114` (`validateMenuItem`) and `:165-166` (insert the View menu between Edit and Window)
- Test: `Tests/MarginalTests/AppDelegateMenuTests.swift` (create if absent; otherwise append)

**Interfaces:**
- Consumes: `DocumentViewController.selectEditorMode(_:)`, `DocumentViewController.editorMode`, `EditorMode`.
- Produces: a "View" menu in the main menu, whose mode items carry `tag == EditorMode.allCases` index, `keyEquivalentModifierMask == [.command, .option]`, and a checkmark on the active mode.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MarginalTests/AppDelegateMenuTests.swift`:

```swift
import XCTest
@testable import Marginal

@MainActor
final class AppDelegateMenuTests: XCTestCase {

    private func viewMenu() -> NSMenu {
        let delegate = AppDelegate()
        let mainMenu = AppDelegate.buildMainMenuForTesting(target: delegate)
        guard let menu = mainMenu.items.compactMap(\.submenu).first(where: { $0.title == "View" }) else {
            XCTFail("no View menu")
            return NSMenu()
        }
        return menu
    }

    func testViewMenuCarriesAllThreeModesWithCommandOptionDigits() {
        let items = viewMenu().items.filter { $0.action == #selector(DocumentViewController.selectEditorMode(_:)) }
        XCTAssertEqual(items.map(\.title), ["Code", "Live", "Preview"])
        XCTAssertEqual(items.map(\.keyEquivalent), ["1", "2", "3"])
        XCTAssertEqual(items.map(\.tag), [0, 1, 2])
        for item in items {
            XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option], item.title)
        }
    }

    // ⌘1–⌘9 must stay with tab switching — the mode items must never claim a bare ⌘digit.
    func testTabShortcutsAreNotStolen() {
        let delegate = AppDelegate()
        let mainMenu = AppDelegate.buildMainMenuForTesting(target: delegate)
        let bareCommandDigits = mainMenu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .filter { $0.keyEquivalentModifierMask == [.command] && Int($0.keyEquivalent) != nil }
        XCTAssertEqual(bareCommandDigits.count, 9)
        for item in bareCommandDigits {
            XCTAssertTrue(item.title.hasPrefix("Select Tab"), item.title)
        }
    }

    func testViewMenuCarriesZoomItems() {
        let titles = viewMenu().items.map(\.title)
        XCTAssertTrue(titles.contains("Zoom In"), "\(titles)")
        XCTAssertTrue(titles.contains("Zoom Out"), "\(titles)")
        XCTAssertTrue(titles.contains("Actual Size"), "\(titles)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/AppDelegateMenuTests`
Expected: FAIL — `buildMainMenuForTesting` doesn't exist and there is no View menu.

- [ ] **Step 3: Expose the menu builder and add the View menu**

In `Sources/Marginal/App/AppDelegate.swift`, add next to the existing private `buildMainMenu`:

```swift
    /// Test seam over the private menu builder.
    static func buildMainMenuForTesting(target: AppDelegate) -> NSMenu {
        buildMainMenu(target: target)
    }
```

Then insert, between `mainMenu.addItem(editMenuItem)` and the `let windowMenuItem` line:

```swift
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        // A radio group, not three checkboxes: the modes are mutually exclusive view state,
        // which is what the HIG's checkmark-on-the-active-item pattern is for. ⌘⌥ rather than
        // bare ⌘ because ⌘1–⌘9 belong to tab switching below.
        for (index, mode) in EditorMode.allCases.enumerated() {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(DocumentViewController.selectEditorMode(_:)),
                keyEquivalent: mode.menuKeyEquivalent
            )
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = index
            viewMenu.addItem(item)
        }
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(DocumentViewController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(DocumentViewController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(DocumentViewController.actualSize(_:)), keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
```

- [ ] **Step 4: Add the zoom actions the menu targets**

In `Sources/Marginal/Document/DocumentViewController.swift`, add next to `selectEditorMode(_:)`:

```swift
    @objc func zoomIn(_ sender: Any?) {
        setFontSize(FontSizing.increased(from: editorFontSize))
    }

    @objc func zoomOut(_ sender: Any?) {
        setFontSize(FontSizing.decreased(from: editorFontSize))
    }

    /// Back to the design system's 16px body size.
    @objc func actualSize(_ sender: Any?) {
        setFontSize(16)
    }
```

Change `private func setFontSize(_ size: CGFloat)` (currently in the shortcut-delegate
extension) to non-private so the actions above can reach it, and move it out of the extension
into the main class body.

- [ ] **Step 5: Check the active mode in `validateMenuItem`**

In `AppDelegate.validateMenuItem(_:)`, add before the existing logic:

```swift
        if menuItem.action == #selector(DocumentViewController.selectEditorMode(_:)) {
            let controller = NSApp.keyWindow?.contentViewController as? DocumentViewController
            guard let controller, EditorMode.allCases.indices.contains(menuItem.tag) else {
                menuItem.state = .off
                return false
            }
            menuItem.state = EditorMode.allCases[menuItem.tag] == controller.editorMode ? .on : .off
            return true
        }
```

- [ ] **Step 6: Run the suite**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`
Expected: PASS, every suite.

- [ ] **Step 7: Commit**

```bash
git add Sources/Marginal Tests/MarginalTests
git commit -m "feat: View menu with Code/Live/Preview on cmd-opt-1/2/3 and zoom items"
```

---

## Task 10: The status-bar switch, the Preview status variant, and the all-lines gutter

**Files:**
- Modify: `Sources/Marginal/Editor/EditorChromeViews.swift`
- Modify: `Sources/Marginal/Document/DocumentViewController.swift` (feed the gutter its lines, own the segmented control's action)
- Test: `Tests/MarginalTests/EditorChromeViewsTests.swift` (create)

**Interfaces:**
- Consumes: `EditorMode`, `DocumentStatistics`.
- Produces:
  - On `StatusBarView`: `var selectedMode: EditorMode { get set }`, `var isShowingDocumentStatistics: Bool { get set }`, `func update(with: DocumentStatistics)`, and `var onModeChange: ((EditorMode) -> Void)?`.
  - On `LineNumberGutterView`: `struct GutterLine: Equatable { let number: Int; let centerY: CGFloat; let isCurrent: Bool }` and `var lines: [GutterLine]`, replacing the `lineNumber`/`lineCenterY` pair.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MarginalTests/EditorChromeViewsTests.swift`:

```swift
import XCTest
@testable import Marginal

@MainActor
final class EditorChromeViewsTests: XCTestCase {

    // MARK: - Status bar

    func testSegmentedControlCarriesAllThreeModesInOrder() {
        let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 600, height: StatusBarView.height))
        let segmented = bar.modeControlForTesting
        XCTAssertEqual(segmented.segmentCount, 3)
        for (index, mode) in EditorMode.allCases.enumerated() {
            XCTAssertEqual(segmented.label(forSegment: index), mode.title)
            XCTAssertNotNil(segmented.image(forSegment: index), "\(mode) has no icon")
        }
    }

    func testSelectedModeRoundTripsThroughTheControl() {
        let bar = StatusBarView(frame: .zero)
        bar.selectedMode = .preview
        XCTAssertEqual(bar.modeControlForTesting.selectedSegment, 2)
        XCTAssertEqual(bar.selectedMode, .preview)
    }

    func testClickingASegmentReportsTheModeOnce() {
        let bar = StatusBarView(frame: .zero)
        var reported: [EditorMode] = []
        bar.onModeChange = { reported.append($0) }
        bar.modeControlForTesting.selectedSegment = 0
        bar.modeControlForTesting.performClick(nil)
        XCTAssertEqual(reported, [.code])
    }

    func testPreviewVariantShowsStatisticsAndHidesTheCaretReadouts() {
        let bar = StatusBarView(frame: .zero)
        bar.update(with: CursorStatus(line: 24, column: 13, path: ["h1", "bold"]))
        bar.isShowingDocumentStatistics = true
        bar.update(with: DocumentStatistics.statistics(for: "one two three"))
        XCTAssertEqual(bar.breadcrumbTextForTesting, "3 words · 1 min read")
        XCTAssertEqual(bar.positionTextForTesting, "")
    }

    func testLeavingPreviewRestoresTheCaretReadouts() {
        let bar = StatusBarView(frame: .zero)
        bar.isShowingDocumentStatistics = true
        bar.update(with: DocumentStatistics.statistics(for: "one"))
        bar.isShowingDocumentStatistics = false
        bar.update(with: CursorStatus(line: 7, column: 3, path: ["h2"]))
        XCTAssertEqual(bar.breadcrumbTextForTesting, "h2")
        XCTAssertEqual(bar.positionTextForTesting, "L 7 · C 3")
    }

    // MARK: - Gutter

    func testGutterHoldsEveryVisibleLineAndMarksTheCurrentOne() {
        let gutter = LineNumberGutterView(frame: NSRect(x: 0, y: 0, width: 44, height: 200))
        gutter.lines = [
            .init(number: 4, centerY: 10, isCurrent: false),
            .init(number: 5, centerY: 30, isCurrent: true),
            .init(number: 6, centerY: 50, isCurrent: false)
        ]
        XCTAssertEqual(gutter.lines.count, 3)
        XCTAssertEqual(gutter.lines.filter(\.isCurrent).map(\.number), [5])
    }

    func testEmptyLinesDrawsNothingAndDoesNotCrash() {
        let gutter = LineNumberGutterView(frame: NSRect(x: 0, y: 0, width: 44, height: 200))
        gutter.lines = []
        gutter.draw(gutter.bounds)   // must not crash
        XCTAssertTrue(gutter.lines.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test -only-testing:MarginalTests/EditorChromeViewsTests`
Expected: FAIL — none of `modeControlForTesting`, `selectedMode`, `onModeChange`, `isShowingDocumentStatistics`, `GutterLine`, `lines` exist.

- [ ] **Step 3: Add the segmented control and the Preview variant to `StatusBarView`**

In `Sources/Marginal/Editor/EditorChromeViews.swift`, extend `StatusBarView`. Add stored properties next to the two labels:

```swift
    private let modeControl = NSSegmentedControl()

    /// Called when the user picks a mode in the control.
    var onModeChange: ((EditorMode) -> Void)?

    /// In Preview there is no caret, so the breadcrumb slot carries word count / reading time
    /// and the line-column slot stays empty.
    var isShowingDocumentStatistics = false

    var selectedMode: EditorMode {
        get {
            let index = modeControl.selectedSegment
            guard EditorMode.allCases.indices.contains(index) else { return .live }
            return EditorMode.allCases[index]
        }
        set {
            modeControl.selectedSegment = EditorMode.allCases.firstIndex(of: newValue) ?? 1
        }
    }

    var modeControlForTesting: NSSegmentedControl { modeControl }
    var breadcrumbTextForTesting: String { breadcrumbLabel.stringValue }
    var positionTextForTesting: String { positionLabel.stringValue }
```

In `init(frame:)`, after the existing label setup and before `NSLayoutConstraint.activate`:

```swift
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.segmentStyle = .texturedRounded
        modeControl.trackingMode = .selectOne
        modeControl.segmentCount = EditorMode.allCases.count
        modeControl.controlSize = .small
        modeControl.font = NSFont.systemFont(ofSize: 10)
        for (index, mode) in EditorMode.allCases.enumerated() {
            modeControl.setLabel(mode.title, forSegment: index)
            modeControl.setImage(
                NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: mode.title),
                forSegment: index
            )
            modeControl.setImageScaling(.scaleProportionallyDown, forSegment: index)
            modeControl.setWidth(0, forSegment: index)   // 0 = size to fit
        }
        modeControl.selectedSegment = EditorMode.allCases.firstIndex(of: .live) ?? 1
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged(_:))
        addSubview(modeControl)
```

Change the constraint block so the control sits at the trailing edge and the position label
moves in beside it:

```swift
        NSLayoutConstraint.activate([
            breadcrumbLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            breadcrumbLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            modeControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            modeControl.centerYAnchor.constraint(equalTo: centerYAnchor),
            positionLabel.trailingAnchor.constraint(equalTo: modeControl.leadingAnchor, constant: -12),
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            breadcrumbLabel.trailingAnchor.constraint(lessThanOrEqualTo: positionLabel.leadingAnchor, constant: -12)
        ])
```

Add the action and the statistics update, and guard the existing `update(with: CursorStatus?)`
so it can't overwrite the Preview readout:

```swift
    @objc private func modeControlChanged(_ sender: NSSegmentedControl) {
        onModeChange?(selectedMode)
    }

    /// Preview's readout: word count and reading time in place of the caret breadcrumb.
    func update(with statistics: DocumentStatistics) {
        breadcrumbLabel.stringValue = statistics.statusText
        positionLabel.stringValue = ""
    }
```

and at the top of the existing `update(with status: CursorStatus?)`:

```swift
        guard !isShowingDocumentStatistics else { return }
```

- [ ] **Step 4: Give the gutter an all-lines mode**

In the same file, replace `LineNumberGutterView`'s `lineNumber` and `lineCenterY` properties with:

```swift
    /// One drawn line number: which line, where its text baseline centres, and whether it's the
    /// caret's own line (drawn brighter).
    struct GutterLine: Equatable {
        let number: Int
        let centerY: CGFloat
        let isCurrent: Bool
    }

    /// The line numbers to draw. Empty draws the strip and nothing else — which is what Live
    /// mode wants when the cursor is elsewhere, and what Preview never sees because the whole
    /// gutter hides.
    var lines: [GutterLine] = [] {
        didSet { needsDisplay = true }
    }
```

and replace the body of `draw(_:)` after the hairline fill with:

```swift
        guard !lines.isEmpty else { return }
        let currentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: DesignPalette.textMuted
        ]
        let otherAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: DesignPalette.textFaint
        ]
        for line in lines {
            let attributes = line.isCurrent ? currentAttributes : otherAttributes
            let string = "\(line.number)" as NSString
            let size = string.size(withAttributes: attributes)
            string.draw(
                at: NSPoint(x: bounds.maxX - 9 - size.width, y: line.centerY - size.height / 2),
                withAttributes: attributes
            )
        }
```

- [ ] **Step 5: Feed the gutter and wire the control in `DocumentViewController`**

In `loadView()`, after `statusBar` is created, wire the control:

```swift
        statusBar.onModeChange = { [weak self] mode in
            self?.setEditorMode(mode)
        }
```

In `updateCursorChrome()`, replace the single-line gutter assignment (`gutterView.lineNumber = status.line`, `gutterView.lineCenterY = rectInGutter.midY` and the `gutterView.lineNumber = nil` early exits) with a call to a new method, and add it:

```swift
    /// Populates the gutter: Code mode lists every line fragment on screen, Live shows only the
    /// caret's own line, Preview never sees the gutter at all.
    private func updateGutterLines(currentLine: Int?) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            gutterView.lines = []
            return
        }
        gutterView.fontSize = min(12, max(10, editorFontSize * 0.7))

        guard editorMode == .code else {
            guard let currentLine, let rect = lineFragmentRectForCaret(layoutManager: layoutManager) else {
                gutterView.lines = []
                return
            }
            gutterView.lines = [.init(number: currentLine, centerY: gutterY(for: rect), isCurrent: true)]
            return
        }

        // Code mode: walk the line fragments intersecting the visible rect, counting newlines to
        // get each fragment's 1-based source line. Only the first fragment of a wrapped line
        // gets a number, matching how code editors number source lines rather than visual rows.
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let nsText = textView.string as NSString

        var lines: [LineNumberGutterView.GutterLine] = []
        var index = charRange.location
        while index < NSMaxRange(charRange) {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let number = nsText.substring(to: lineRange.location).components(separatedBy: "\n").count
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: layoutManager.glyphIndexForCharacter(at: lineRange.location),
                effectiveRange: nil
            )
            lines.append(.init(number: number, centerY: gutterY(for: fragmentRect), isCurrent: number == currentLine))
            index = max(NSMaxRange(lineRange), index + 1)
        }
        gutterView.lines = lines
    }

    /// The caret's own line fragment rect, handling the caret-at-very-end cases.
    private func lineFragmentRectForCaret(layoutManager: NSLayoutManager) -> NSRect? {
        let location = textView.selectedRange().location
        guard location != NSNotFound else { return nil }
        if location < (textView.textStorage?.length ?? 0) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
            return layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        }
        var rect = layoutManager.extraLineFragmentRect
        if rect.isEmpty, layoutManager.numberOfGlyphs > 0 {
            rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: nil)
        }
        return rect.isEmpty ? nil : rect
    }

    /// Converts a text-container rect to the gutter's own coordinate space.
    private func gutterY(for rect: NSRect) -> CGFloat {
        var inTextView = rect
        inTextView.origin.y += textView.textContainerInset.height
        return textView.convert(inTextView, to: gutterView).midY
    }
```

Then in `updateCursorChrome()`, use it: the no-cursor path becomes `updateGutterLines(currentLine: nil)` plus `statusBar.update(with: nil)`, and the normal path ends with `updateGutterLines(currentLine: status.line)`. Keep the existing `guard editorMode != .preview else { return }` from Task 8.

In `applyChrome(for:)`, replace the Task 8 note about the status bar being wired later with the
actual wiring — keeping the control in sync so menu and keyboard switches move it too, and
switching the readout to statistics in Preview:

```swift
        statusBar.selectedMode = mode
        statusBar.isShowingDocumentStatistics = isPreview
        if isPreview {
            statusBar.update(with: DocumentStatistics.statistics(for: textView.string))
        }
```

And in `textDidChange(_:)`, keep the statistics live while the reader edits in another window's
tab and comes back — add after `modeController.render()`:

```swift
        if editorMode == .preview {
            statusBar.update(with: DocumentStatistics.statistics(for: textView.string))
        }
```

- [ ] **Step 6: Run the suite**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`
Expected: PASS, every suite. Any pre-existing test that set `gutterView.lineNumber` must move to `gutterView.lines`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Marginal Tests/MarginalTests
git commit -m "feat: status-bar mode switch, Preview statistics readout, all-lines gutter in Code mode"
```

---

## Task 11: Visual verification in the running app, then docs

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `marketing/Marginal Design System/readme.md` (document the mode-switch component)

**Interfaces:**
- Consumes: everything above.
- Produces: no code.

- [ ] **Step 1: Build and launch the real app**

```bash
xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build
open "$(xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug -showBuildSettings | awk -F'= ' '/ BUILT_PRODUCTS_DIR/ {print $2}')/Marginal.app"
```

Open `test/markdown-editor-feature-test.md` in it (File ▸ Open, or `open -a Marginal test/markdown-editor-feature-test.md`).

- [ ] **Step 2: Verify each mode visually, in both appearances**

For light, then dark (System Settings ▸ Appearance, or `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'`), take a screenshot in each mode and read it back with the Read tool. Confirm, and report per item:

1. The status-bar segmented control shows three segments with icon **and** label, the active one highlighted, and it does not crowd the breadcrumb at a 700pt window width.
2. `⌘⌥1`, `⌘⌥2`, `⌘⌥3` each switch mode, and the View menu shows a checkmark on the active one.
3. `⌘1`/`⌘2` still switch **tabs** (open a second document first) — the mode shortcuts must not have stolen them.
4. Code mode: markers visible and tinted, one uniform monospace size, and **nothing shifts vertically** as you move the caret through a heading and a horizontal rule. This is the acceptance test for the whole feature.
5. Code mode gutter numbers every visible line, caret's line brighter.
6. Preview: the multi-line paragraph in the test document renders as one flowing paragraph, the gutter is gone, and the status bar reads word count and reading time.
7. Position preservation: scroll to the middle in Live, switch to Preview — you land in the same region; scroll in Preview, switch back to Live — the caret is on the topmost visible block.
8. `⌘+`/`⌘−` change type size in Preview as well as in Code and Live.

- [ ] **Step 3: Quit the app cleanly**

```bash
osascript -e 'tell application "Marginal" to quit'
```

- [ ] **Step 4: Update `README.md`**

Replace the planned-features bullet `` `View ▸ Show Source` raw markdown toggle, plus `⌘⌥C` to copy raw markdown from any selection `` with:

```markdown
- Three view modes — **Code** (tinted markdown source, nothing hides or reflows), **Live**
  (WYSIWYG with reveal-at-cursor), **Preview** (read-only render where paragraphs flow) — on
  `⌘⌥1`/`⌘⌥2`/`⌘⌥3` and a status-bar switch, plus `⌘⌥C` to copy raw markdown from any selection
```

- [ ] **Step 5: Update `CHANGELOG.md`**

Add a new `## Unreleased` section at the top (or extend the existing one):

```markdown
### Added
- Three explicit view modes — Code, Live and Preview — with a status-bar switch, a View menu,
  and `⌘⌥1`/`⌘⌥2`/`⌘⌥3`. Code mode shows the markdown source with tinted markers at a single
  uniform size, so nothing reflows while you edit. Preview renders the document read-only, so a
  paragraph's hard-wrapped source lines flow as one paragraph.
- Code mode numbers every visible line in the gutter; Preview reports word count and reading
  time in the status bar.
- View menu items for Zoom In, Zoom Out and Actual Size, which were keyboard-only before.

### Changed
- The undiscoverable `⌘⇧P` "Show Source" toggle is replaced by the three-mode switch.
- Preview and PDF export now share one stylesheet, so the screen and the exported page match.
  Exported PDFs pick up two refinements as a result: `####`-and-deeper headings are sized from
  the app's own heading scale rather than the browser default, and blockquotes are muted grey.
```

- [ ] **Step 6: Document the component in the design system**

In `marketing/Marginal Design System/readme.md`, add a "Mode switch" entry to the components
section describing: status-bar placement, `NSSegmentedControl` with `.texturedRounded` and
`.small` control size, icon + 10pt label per segment, accent fill on the selected segment, and
the reasoning (status bar rather than a toolbar, because the app has no toolbar and the switch
should read as document state).

- [ ] **Step 7: Full suite, then commit**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`
Expected: PASS, every suite.

```bash
git add README.md CHANGELOG.md "marketing/Marginal Design System/readme.md"
git commit -m "docs: three view modes in README, CHANGELOG and the design system"
```

---

## Self-Review

**1. Spec coverage.** Every spec section maps to a task: mode model → 1; switch control → 10;
View menu and shortcuts → 9; Code mode styling → 5; Code mode gutter → 10; Live mode unchanged →
verified by Task 8's `testSettingLiveModeRestoresWysiwygHeadingSize` and by the untouched
existing `MarkdownStylerTests`; Preview render → 6; stylesheet extraction → 3; Preview status bar
→ 2 and 10; position preservation → 4 and 8; `EditorModeController` refactor → 7 and 8;
`⌘⇧P` retirement → 8; testing → distributed; docs → 11. No spec requirement is unimplemented.

**2. Placeholder scan.** No "TBD", no "handle edge cases", no "similar to Task N", no step that
describes code without showing it. Every test step contains runnable test code and every
implementation step contains the actual source.

**3. Type consistency.** Checked across tasks: `EditorMode.title`/`symbolName`/`menuKeyEquivalent`
(Task 1) are used verbatim in Tasks 9 and 10. `EditorModeHost`'s four methods (Task 7) are the
four implemented in Task 8. `MarkdownStylesheet.screenCSS(appearance:bodyPointSize:)` and
`document(body:title:css:)` (Task 3) are called with those exact labels in Tasks 3 and 6.
`MarkdownHTMLRenderer.blockSourceLines(fromMarkdown:)` and
`blockLine(nearestAtOrBefore:in:)` (Task 4) are used in Task 6 and Task 8.
`DocumentStatistics.statusText` (Task 2) is used in Task 10. `LineNumberGutterView.GutterLine`
(Task 10) replaces the `lineNumber`/`lineCenterY` pair, and Task 10 Step 5 updates the only
call site.

**4. Ordering.** Tasks 1–7 are leaves with no dependency on the view controller, so each is
independently testable. Task 8 is the integration point and is the first task that changes app
behaviour; mode switching becomes reachable by the user in Task 9. The build is green at the end
of every task.
