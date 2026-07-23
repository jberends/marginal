# Marginal Phase 1: Foundation & Core WYSIWYG Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a native macOS app that opens/saves `.md` files and renders bold, italic, strikethrough, underline, headers, lists, and links live as you type, with markdown syntax hidden except where the cursor currently is — the de-risking POC the spec calls for, built out into a real, working document editor.

**Architecture:** Native Swift + AppKit, no web view. One `NSDocument` subclass backs each file. A pure-Swift `MarkdownParser` scans the raw string for spans (bold/italic/strikethrough/underline/headers/lists/links). A pure `MarkdownStyler` turns those spans + the current cursor position into an `NSAttributedString`, hiding delimiter characters by shrinking their rendered font size to near-zero rather than removing them from the text — the underlying string is always the real, unmodified markdown. `CursorRevealController` decides, per span, whether the cursor is inside it and therefore whether its delimiters should be shown at full size.

**Tech Stack:** Swift 6, AppKit (`NSDocument`, `NSTextView`, `TextKit`), XCTest. Project generated via [XcodeGen](https://github.com/yonaskolb/XcodeGen) from a checked-in `project.yml` (deterministic, diffable, no manually-maintained `.xcodeproj`).

## Global Constraints

- macOS 14.0 (Sonoma) minimum deployment target (spec: "macOS 14+").
- Native Swift + AppKit only — no web view, no Electron-style shell (spec: "not a webbrowser based one").
- The file on disk is always plain UTF-8 markdown; WYSIWYG rendering is a display-time transformation only and must never alter the underlying characters (spec: "The file on disk is always plain markdown — the WYSIWYG rendering is purely a view").
- No project/folder/multi-file management (spec non-goal).
- Repository is Apache-2.0 licensed (already applied at repo root; no license work needed in this plan).
- Out of scope for this plan (each gets its own future plan): live table grid, inline images, code-block syntax highlighting, BYOK AI feature, dark-mode/materials/HIG visual polish, HTML/PDF export, App Store packaging/signing for release, full menu bar / Preferences window.

---

## File Structure

```
marginal/
  project.yml                                  # XcodeGen project definition
  Sources/Marginal/
    App/
      main.swift                                # app entry point
      AppDelegate.swift                          # NSApplicationDelegate, minimal main menu
      Info.plist                                  # bundle metadata, document type registration
      Marginal.entitlements                       # App Sandbox entitlements
    Document/
      MarkdownDocument.swift                      # NSDocument subclass: read/write UTF-8 text
      DocumentViewController.swift                # hosts the text view, owns parse+style pipeline
    Editor/
      MarkdownTextView.swift                      # NSTextView subclass, custom keyDown shortcuts
      MarkdownParser.swift                        # pure functions: string -> spans
      MarkdownDocumentModel.swift                 # span types + container struct
      MarkdownStyler.swift                        # spans + cursor -> NSAttributedString
      CursorRevealController.swift                # pure: which spans does the cursor reveal?
      FontSizing.swift                            # pure: clamped point-size stepping
  Tests/MarginalTests/
    MarkdownParserTests.swift
    MarkdownStylerTests.swift
    CursorRevealControllerTests.swift
    FontSizingTests.swift
    MarkdownDocumentTests.swift
    DocumentViewControllerTests.swift
```

---

## Task 1: Bootstrap the Xcode project with XcodeGen

**Files:**
- Create: `project.yml`
- Create: `Sources/Marginal/App/main.swift`
- Create: `Sources/Marginal/App/AppDelegate.swift`
- Create: `Sources/Marginal/App/Info.plist`
- Create: `Sources/Marginal/App/Marginal.entitlements`

**Interfaces:**
- Produces: a buildable `Marginal.xcodeproj` (generated, gitignored) targeting `Marginal.app`, plus a `MarginalTests` unit test target that later tasks add test files to.

- [ ] **Step 1: Install XcodeGen if not already present**

Run: `which xcodegen || brew install xcodegen`
Expected: prints a path to the `xcodegen` binary.

- [ ] **Step 2: Write `project.yml`**

```yaml
name: Marginal
options:
  bundleIdPrefix: com.jochemberends
  deploymentTarget:
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    GENERATE_INFOPLIST_FILE: NO
targets:
  Marginal:
    type: application
    platform: macOS
    sources:
      - path: Sources/Marginal
    info:
      path: Sources/Marginal/App/Info.plist
    entitlements:
      path: Sources/Marginal/App/Marginal.entitlements
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.jochemberends.marginal
        PRODUCT_NAME: Marginal
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_STYLE: Automatic
  MarginalTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests/MarginalTests
    dependencies:
      - target: Marginal
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
schemes:
  Marginal:
    build:
      targets:
        Marginal: all
        MarginalTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - MarginalTests
```

- [ ] **Step 3: Write `Sources/Marginal/App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Jochem Berends. Licensed under Apache License 2.0.</string>
</dict>
</plist>
```

Note: `CFBundleDocumentTypes`/`NSDocumentClass`/`UTExportedTypeDeclarations` are added in Task 2, once `MarkdownDocument` exists.

- [ ] **Step 4: Write `Sources/Marginal/App/Marginal.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Write `Sources/Marginal/App/AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.buildMainMenu()
    }

    private static func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Marginal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        return mainMenu
    }
}
```

- [ ] **Step 6: Write `Sources/Marginal/App/main.swift`**

```swift
import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
```

- [ ] **Step 7: Generate the Xcode project and build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Add generated project artifacts to `.gitignore`**

Add these lines to the existing `.gitignore` (it already ignores `*.xcodeproj/*` with exceptions — replace that block since we now fully regenerate the project rather than hand-editing it):

```
# XcodeGen-generated project (regenerate with `xcodegen generate`)
*.xcodeproj/
```

- [ ] **Step 9: Commit**

```bash
git add project.yml Sources/Marginal/App .gitignore
git commit -m "Bootstrap Xcode project via XcodeGen with minimal app shell"
```

---

## Task 2: `MarkdownDocument` — NSDocument read/write round-trip

**Files:**
- Create: `Sources/Marginal/Document/MarkdownDocument.swift`
- Modify: `Sources/Marginal/App/Info.plist` (add document type registration)
- Test: `Tests/MarginalTests/MarkdownDocumentTests.swift`

**Interfaces:**
- Produces: `MarkdownDocument.text: String` (get/set), `MarkdownDocument.data(ofType:) throws -> Data`, `MarkdownDocument.read(from:ofType:) throws`. Task 3 sets `viewController.document` and keeps `document.text` in sync with the live text view.

- [ ] **Step 1: Write the failing test**

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownDocumentTests`
Expected: FAIL — `MarkdownDocument` not found.

- [ ] **Step 3: Write `Sources/Marginal/Document/MarkdownDocument.swift`**

```swift
import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {

    var text: String = ""

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let viewController = DocumentViewController()
        viewController.document = self

        let window = NSWindow(contentViewController: viewController)
        window.setContentSize(NSSize(width: 700, height: 600))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]

        let windowController = NSWindowController(window: window)
        addWindowController(windowController)

        viewController.loadInitialText(text)
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
}
```

This references `DocumentViewController`, created in Task 3 — that's fine, it only needs to compile once Task 3 lands; this task's own test (`MarkdownDocumentTests`) never calls `makeWindowControllers()`, so it passes independently of `DocumentViewController` existing yet. To keep Task 2 compiling standalone, add a placeholder now (Task 3 replaces its body):

```swift
import AppKit

final class DocumentViewController: NSViewController {
    weak var document: MarkdownDocument?
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
    }
    func loadInitialText(_ text: String) {}
}
```

Save this placeholder as `Sources/Marginal/Document/DocumentViewController.swift`.

- [ ] **Step 4: Add document type registration to `Sources/Marginal/App/Info.plist`**

Insert before the closing `</dict>`:

```xml
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>NSDocumentClass</key>
            <string>MarkdownDocument</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                </array>
            </dict>
        </dict>
    </array>
```

- [ ] **Step 5: Regenerate project and run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownDocumentTests`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Document Sources/Marginal/App/Info.plist Tests/MarginalTests/MarkdownDocumentTests.swift
git commit -m "Add MarkdownDocument with UTF-8 read/write round-trip and register .md document type"
```

---

## Task 3: Real document window — plain `NSTextView` bound to the document

**Files:**
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Modify: `Sources/Marginal/App/AppDelegate.swift` (open an untitled document on launch)
- Create: `Sources/Marginal/Editor/MarkdownTextView.swift`

**Interfaces:**
- Produces: `DocumentViewController.textView: MarkdownTextView!`, `DocumentViewController.loadInitialText(_ text: String)`. Task 8 extends `textDidChange`/`textViewDidChangeSelection` on this class; Task 9 reads `textView.selectedRange()` here.
- Consumes: `MarkdownDocument` from Task 2.

- [ ] **Step 1: Write `Sources/Marginal/Editor/MarkdownTextView.swift`**

```swift
import AppKit

/// Extension point for later phases (custom key handling is added in Task 10/11).
final class MarkdownTextView: NSTextView {}
```

- [ ] **Step 2: Replace `DocumentViewController.swift` with the real implementation**

```swift
import AppKit

final class DocumentViewController: NSViewController {

    private(set) var textView: MarkdownTextView!
    private var isApplyingProgrammaticEdit = false

    weak var document: MarkdownDocument?

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = MarkdownTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.textView = textView
        self.view = containerView
    }

    func loadInitialText(_ text: String) {
        textView.string = text
    }
}

extension DocumentViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        document?.text = textView.string
        document?.updateChangeCount(.changeDone)
    }
}
```

(Styling and cursor-reveal are added to this delegate in Tasks 8–9. `isApplyingProgrammaticEdit` isn't used yet but stays — Task 8 needs it.)

- [ ] **Step 3: Make the app open an untitled document on launch**

Modify `AppDelegate.swift`, adding this method inside the class:

```swift
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
```

- [ ] **Step 4: Regenerate, build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual end-to-end verification**

Run: `open /path/to/DerivedData/.../Build/Products/Debug/Marginal.app` (or press Run in Xcode).
1. App launches with one empty, untitled window containing a text view.
2. Type `Hello **world**` — text appears as plain characters (no styling yet — that's Task 8).
3. Press `⌘S`, save as `test.md` to `~/Desktop`.
4. Quit the app (`⌘Q`), relaunch, `File ▸ Open…`, choose `~/Desktop/test.md`.
5. Confirm the text `Hello **world**` reappears exactly.

Expected: all five steps succeed.

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownTextView.swift Sources/Marginal/Document/DocumentViewController.swift Sources/Marginal/App/AppDelegate.swift
git commit -m "Wire a real NSTextView-backed window to MarkdownDocument, open untitled doc on launch"
```

---

## Task 4: `MarkdownParser` — inline styles (bold, italic, strikethrough, underline)

**Files:**
- Create: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Create: `Sources/Marginal/Editor/MarkdownParser.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`

**Interfaces:**
- Produces: `InlineStyleKind` (`.bold`, `.italic`, `.strikethrough`, `.underline`), `InlineStyleSpan { kind, contentRange, openingDelimiterRange, closingDelimiterRange }`, `MarkdownParser.parseInlineStyles(in: String) -> [InlineStyleSpan]`. Tasks 5–9 add more parser functions and consume these types via `MarkdownDocumentModel`.

**Design decision (document this in the file's header comment):** underline has no CommonMark syntax, so Marginal uses inline HTML `<u>...</u>` — valid, portable markdown (CommonMark permits raw inline HTML) that other renderers (e.g. GitHub) also display as underlined.

**Known v1 limitation (document this too):** this is a pragmatic single-pass parser, not a full CommonMark implementation. It does not apply CommonMark's intraword-emphasis flanking rules, so `snake_case_like_this` can be misdetected as containing italic emphasis, and triple-delimiter bold+italic nesting (`***text***`) is only partially handled (recognized as bold, with the extra asterisk left as a literal character). Revisit only if this proves disruptive in practice.

- [ ] **Step 1: Write `Sources/Marginal/Editor/MarkdownDocumentModel.swift`**

```swift
import Foundation

enum InlineStyleKind: Equatable {
    case bold
    case italic
    case strikethrough
    case underline
}

struct InlineStyleSpan: Equatable {
    let kind: InlineStyleKind
    let contentRange: Range<String.Index>
    let openingDelimiterRange: Range<String.Index>
    let closingDelimiterRange: Range<String.Index>
}

struct MarkdownDocumentModel: Equatable {
    var inlineStyles: [InlineStyleSpan] = []
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import Marginal

final class MarkdownParserInlineStyleTests: XCTestCase {

    func testParsesBoldWithAsterisks() {
        let text = "Hello **world** today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .bold)
        XCTAssertEqual(String(text[spans[0].contentRange]), "world")
    }

    func testParsesBoldWithUnderscores() {
        let text = "Hello __world__ today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .bold)
    }

    func testParsesItalicWithSingleAsterisk() {
        let text = "Hello *world* today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .italic)
        XCTAssertEqual(String(text[spans[0].contentRange]), "world")
    }

    func testParsesItalicWithSingleUnderscore() {
        let text = "Hello _world_ today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .italic)
    }

    func testBoldTakesPrecedenceAndTripleDelimiterStillYieldsABoldSpan() {
        let text = "Hello ***world*** today"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertTrue(spans.contains { $0.kind == .bold })
    }

    func testParsesStrikethrough() {
        let text = "This is ~~wrong~~ right"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .strikethrough)
    }

    func testParsesUnderlineHTMLTag() {
        let text = "This is <u>underlined</u> text"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].kind, .underline)
        XCTAssertEqual(String(text[spans[0].contentRange]), "underlined")
    }

    func testPlainTextHasNoSpans() {
        let text = "Just a normal sentence."
        XCTAssertTrue(MarkdownParser.parseInlineStyles(in: text).isEmpty)
    }

    func testMultipleNonOverlappingSpansAreAllFound() {
        let text = "**one** and *two* and ~~three~~"
        let spans = MarkdownParser.parseInlineStyles(in: text)
        XCTAssertEqual(spans.count, 3)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserInlineStyleTests`
Expected: FAIL — `MarkdownParser` not found.

- [ ] **Step 4: Write `Sources/Marginal/Editor/MarkdownParser.swift`**

```swift
import Foundation

/// Underline has no CommonMark syntax, so Marginal represents it with inline
/// HTML `<u>...</u>` — valid CommonMark (raw inline HTML is permitted) and
/// rendered as underlined by other tools (e.g. GitHub).
///
/// This is a pragmatic single-pass parser, not a full CommonMark
/// implementation: it does not apply CommonMark's intraword-emphasis
/// flanking rules (so `snake_case_like_this` can be misdetected as italic),
/// and `***bold+italic***` nesting is only partially handled (recognized as
/// bold, with the extra asterisk left as a literal character).
struct MarkdownParser {

    static func parseInlineStyles(in text: String) -> [InlineStyleSpan] {
        var spans: [InlineStyleSpan] = []
        var claimed = Set<Int>()

        func offset(_ index: String.Index) -> Int {
            text.distance(from: text.startIndex, to: index)
        }

        func claim(_ range: Range<String.Index>) {
            for i in offset(range.lowerBound)..<offset(range.upperBound) {
                claimed.insert(i)
            }
        }

        func isClaimed(_ range: Range<String.Index>) -> Bool {
            for i in offset(range.lowerBound)..<offset(range.upperBound) where claimed.contains(i) {
                return true
            }
            return false
        }

        func findMatches(pattern: String, kind: InlineStyleKind, openLength: Int, closeLength: Int) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
                guard let match,
                      let fullRange = Range(match.range, in: text),
                      let contentRange = Range(match.range(at: 1), in: text) else { return }
                if isClaimed(fullRange) { return }

                let openStart = fullRange.lowerBound
                let openEnd = text.index(openStart, offsetBy: openLength)
                let closeEnd = fullRange.upperBound
                let closeStart = text.index(closeEnd, offsetBy: -closeLength)

                spans.append(InlineStyleSpan(
                    kind: kind,
                    contentRange: contentRange,
                    openingDelimiterRange: openStart..<openEnd,
                    closingDelimiterRange: closeStart..<closeEnd
                ))
                claim(fullRange)
            }
        }

        // Order matters: higher-priority (longer/more specific) delimiters
        // claim their ranges first so shorter delimiters don't cut through them.
        findMatches(pattern: "\\*\\*(.+?)\\*\\*", kind: .bold, openLength: 2, closeLength: 2)
        findMatches(pattern: "__(.+?)__", kind: .bold, openLength: 2, closeLength: 2)
        findMatches(pattern: "~~(.+?)~~", kind: .strikethrough, openLength: 2, closeLength: 2)
        findMatches(pattern: "<u>(.+?)</u>", kind: .underline, openLength: 3, closeLength: 4)
        findMatches(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", kind: .italic, openLength: 1, closeLength: 1)
        findMatches(pattern: "(?<!_)_([^_\\n]+?)_(?!_)", kind: .italic, openLength: 1, closeLength: 1)

        return spans.sorted { $0.contentRange.lowerBound < $1.contentRange.lowerBound }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserInlineStyleTests`
Expected: PASS (all 9 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Tests/MarginalTests/MarkdownParserTests.swift
git commit -m "Add MarkdownParser inline style detection (bold/italic/strikethrough/underline)"
```

---

## Task 5: `MarkdownParser` — headers and single-level lists

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Modify: `Sources/Marginal/Editor/MarkdownParser.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`

**Interfaces:**
- Produces: `HeaderSpan { level, markerRange, contentRange, lineRange }`, `ListMarkerKind` (`.unordered`, `.ordered(number: Int)`), `ListItemSpan { kind, markerRange, contentRange, lineRange }`, `MarkdownParser.parseHeaders(in:) -> [HeaderSpan]`, `MarkdownParser.parseListItems(in:) -> [ListItemSpan]`.

**Known v1 limitation:** lists are single-level only — nested/indented lists are not detected as nested (each line is evaluated independently). Full nested-list layout is deferred to a future phase.

- [ ] **Step 1: Add types to `MarkdownDocumentModel.swift`**

```swift
struct HeaderSpan: Equatable {
    let level: Int
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
}

enum ListMarkerKind: Equatable {
    case unordered
    case ordered(number: Int)
}

struct ListItemSpan: Equatable {
    let kind: ListMarkerKind
    let markerRange: Range<String.Index>
    let contentRange: Range<String.Index>
    let lineRange: Range<String.Index>
}
```

Add `var headers: [HeaderSpan] = []` and `var listItems: [ListItemSpan] = []` to `MarkdownDocumentModel`.

- [ ] **Step 2: Write the failing tests**

```swift
final class MarkdownParserHeaderAndListTests: XCTestCase {

    func testParsesH1Header() {
        let text = "# Title\nBody text"
        let headers = MarkdownParser.parseHeaders(in: text)
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers[0].level, 1)
        XCTAssertEqual(String(text[headers[0].contentRange]), "Title")
    }

    func testParsesH2ThroughH6() {
        for level in 2...6 {
            let marker = String(repeating: "#", count: level)
            let text = "\(marker) Heading\nmore"
            let headers = MarkdownParser.parseHeaders(in: text)
            XCTAssertEqual(headers.count, 1, "level \(level)")
            XCTAssertEqual(headers.first?.level, level)
        }
    }

    func testSevenHashesIsNotAHeader() {
        XCTAssertTrue(MarkdownParser.parseHeaders(in: "####### Not a header").isEmpty)
    }

    func testHashWithoutSpaceIsNotAHeader() {
        XCTAssertTrue(MarkdownParser.parseHeaders(in: "#NotAHeader").isEmpty)
    }

    func testParsesUnorderedListWithHyphen() {
        let text = "- first item\n- second item"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].kind, .unordered)
        XCTAssertEqual(String(text[items[0].contentRange]), "first item")
    }

    func testParsesUnorderedListWithAsteriskAndPlus() {
        let items = MarkdownParser.parseListItems(in: "* one\n+ two")
        XCTAssertEqual(items.count, 2)
    }

    func testParsesOrderedList() {
        let text = "1. first\n2. second\n10. tenth"
        let items = MarkdownParser.parseListItems(in: text)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].kind, .ordered(number: 1))
        XCTAssertEqual(items[2].kind, .ordered(number: 10))
    }

    func testPlainLineIsNotAListItem() {
        XCTAssertTrue(MarkdownParser.parseListItems(in: "Just a normal sentence.").isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserHeaderAndListTests`
Expected: FAIL — `parseHeaders`/`parseListItems` not found.

- [ ] **Step 4: Add parsing functions to `MarkdownParser.swift`** (inside the `MarkdownParser` struct)

```swift
    static func parseHeaders(in text: String) -> [HeaderSpan] {
        var headers: [HeaderSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = line.range(of: "^#{1,6} ", options: .regularExpression) {
                let level = line.distance(from: markerRange.lowerBound, to: markerRange.upperBound) - 1
                headers.append(HeaderSpan(
                    level: level,
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return headers
    }

    static func parseListItems(in text: String) -> [ListItemSpan] {
        var items: [ListItemSpan] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            if let markerRange = line.range(of: "^[-*+] ", options: .regularExpression) {
                items.append(ListItemSpan(
                    kind: .unordered,
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            } else if let markerRange = line.range(of: "^[0-9]+\\. ", options: .regularExpression) {
                let digits = line[markerRange].prefix { $0.isNumber }
                items.append(ListItemSpan(
                    kind: .ordered(number: Int(digits) ?? 0),
                    markerRange: markerRange,
                    contentRange: markerRange.upperBound..<lineEnd,
                    lineRange: lineStart..<lineEnd
                ))
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return items
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserHeaderAndListTests`
Expected: PASS (all 8 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Tests/MarginalTests/MarkdownParserTests.swift
git commit -m "Add MarkdownParser support for headers (H1-H6) and single-level lists"
```

---

## Task 6: `MarkdownParser` — links

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownDocumentModel.swift`
- Modify: `Sources/Marginal/Editor/MarkdownParser.swift`
- Test: `Tests/MarginalTests/MarkdownParserTests.swift`

**Interfaces:**
- Produces: `LinkSpan { textRange, urlRange, fullRange, url: String }`, `MarkdownParser.parseLinks(in:) -> [LinkSpan]`.

- [ ] **Step 1: Add type to `MarkdownDocumentModel.swift`**

```swift
struct LinkSpan: Equatable {
    let textRange: Range<String.Index>
    let urlRange: Range<String.Index>
    let fullRange: Range<String.Index>
    let url: String
}
```

Add `var links: [LinkSpan] = []` to `MarkdownDocumentModel`.

- [ ] **Step 2: Write the failing tests**

```swift
final class MarkdownParserLinkTests: XCTestCase {

    func testParsesSingleLink() {
        let text = "Check [this site](https://example.com) out"
        let links = MarkdownParser.parseLinks(in: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(String(text[links[0].textRange]), "this site")
        XCTAssertEqual(links[0].url, "https://example.com")
    }

    func testParsesMultipleLinks() {
        let text = "[one](https://a.com) and [two](https://b.com)"
        XCTAssertEqual(MarkdownParser.parseLinks(in: text).count, 2)
    }

    func testTextWithoutLinksReturnsEmpty() {
        XCTAssertTrue(MarkdownParser.parseLinks(in: "No links here.").isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserLinkTests`
Expected: FAIL — `parseLinks` not found.

- [ ] **Step 4: Add to `MarkdownParser.swift`**

```swift
    static func parseLinks(in text: String) -> [LinkSpan] {
        var links: [LinkSpan] = []
        guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") else { return links }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let textRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { return }
            links.append(LinkSpan(textRange: textRange, urlRange: urlRange, fullRange: fullRange, url: String(text[urlRange])))
        }
        return links
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownParserLinkTests`
Expected: PASS (all 3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownDocumentModel.swift Sources/Marginal/Editor/MarkdownParser.swift Tests/MarginalTests/MarkdownParserTests.swift
git commit -m "Add MarkdownParser support for [text](url) links"
```

---

## Task 7: `MarkdownStyler` — spans + cursor to `NSAttributedString`

**Files:**
- Create: `Sources/Marginal/Editor/CursorRevealController.swift`
- Create: `Sources/Marginal/Editor/MarkdownStyler.swift`
- Test: `Tests/MarginalTests/CursorRevealControllerTests.swift`
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`

**Interfaces:**
- Produces: `CursorRevealController.revealedInlineStyleSpans(in:cursorLocation:) -> [InlineStyleSpan]`, `CursorRevealController.revealedHeaderSpans(in:cursorLocation:) -> [HeaderSpan]`, `MarkdownStyler.hiddenDelimiterFontSize: CGFloat`, `MarkdownStyler.attributedString(for:model:baseFont:cursorLocation:) -> NSAttributedString`.
- Consumes: `MarkdownDocumentModel` and span types from Tasks 4–6.

**Design decision:** delimiter characters are never removed from the text. They're hidden by shrinking their rendered font size to `hiddenDelimiterFontSize` (0.1pt) — a real, selectable, undo-safe character with near-zero visual width — and restored to the base font size when the cursor is inside their span. This is why `⌘⌥C` (Task 11) can just copy the plain string: the raw markdown is always there.

**Known v1 limitation:** overlapping styles (e.g. bold text inside a header) aren't composed — whichever attribute is applied last wins. Acceptable for v1; revisit in the visual-polish phase if it looks wrong in practice.

- [ ] **Step 1: Write the failing tests for `CursorRevealController`**

```swift
import XCTest
@testable import Marginal

final class CursorRevealControllerTests: XCTestCase {

    func testCursorOutsideSpanDoesNotRevealIt() {
        let text = "Hello **world** today"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.startIndex
        XCTAssertTrue(CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor).isEmpty)
    }

    func testCursorInsideSpanRevealsIt() {
        let text = "Hello **world** today"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 9) // inside "world"
        XCTAssertEqual(CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorAtOpeningDelimiterRevealsSpan() {
        let text = "Hello **world** today"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 6) // right at opening **
        XCTAssertEqual(CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorInHeaderLineRevealsHeaderMarker() {
        let text = "# Title\nBody"
        let model = MarkdownDocumentModel(headers: MarkdownParser.parseHeaders(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 3) // inside "Title"
        XCTAssertEqual(CursorRevealController.revealedHeaderSpans(in: model, cursorLocation: cursor).count, 1)
    }

    func testCursorOnOtherLineDoesNotRevealHeaderMarker() {
        let text = "# Title\nBody"
        let model = MarkdownDocumentModel(headers: MarkdownParser.parseHeaders(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 9) // inside "Body"
        XCTAssertTrue(CursorRevealController.revealedHeaderSpans(in: model, cursorLocation: cursor).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: FAIL — `CursorRevealController` not found.

- [ ] **Step 3: Write `Sources/Marginal/Editor/CursorRevealController.swift`**

```swift
import Foundation

struct CursorRevealController {

    static func revealedInlineStyleSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [InlineStyleSpan] {
        model.inlineStyles.filter { span in
            let fullRange = span.openingDelimiterRange.lowerBound..<span.closingDelimiterRange.upperBound
            return cursorLocation >= fullRange.lowerBound && cursorLocation <= fullRange.upperBound
        }
    }

    static func revealedHeaderSpans(in model: MarkdownDocumentModel, cursorLocation: String.Index) -> [HeaderSpan] {
        model.headers.filter { header in
            cursorLocation >= header.lineRange.lowerBound && cursorLocation <= header.lineRange.upperBound
        }
    }
}
```

- [ ] **Step 4: Run to verify `CursorRevealControllerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/CursorRevealControllerTests`
Expected: PASS (all 5 tests).

- [ ] **Step 5: Write the failing tests for `MarkdownStyler`**

```swift
import XCTest
import AppKit
@testable import Marginal

final class MarkdownStylerTests: XCTestCase {

    func testBoldContentGetsBoldFont() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "world")!.lowerBound)
        let font = attributed.attribute(.font, at: location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testHiddenDelimiterUsesTinyFont() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let openingDelimiterLocation = 6 // the first "*" of "**world**"
        let font = attributed.attribute(.font, at: openingDelimiterLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, MarkdownStyler.hiddenDelimiterFontSize)
    }

    func testCursorInsideSpanRevealsDelimiterAtFullSize() {
        let text = "Hello **world**"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let cursor = text.index(text.startIndex, offsetBy: 9) // inside "world"
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: cursor)
        let openingDelimiterLocation = 6
        let font = attributed.attribute(.font, at: openingDelimiterLocation, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testHeaderContentGetsLargerFontThanBase() {
        let text = "# Title\nBody"
        let model = MarkdownDocumentModel(headers: MarkdownParser.parseHeaders(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let font = attributed.attribute(.font, at: 2, effectiveRange: nil) as? NSFont // inside "Title"
        XCTAssertGreaterThan(font?.pointSize ?? 0, 14)
    }

    func testStrikethroughContentGetsStrikethroughAttribute() {
        let text = "This is ~~wrong~~"
        let model = MarkdownDocumentModel(inlineStyles: MarkdownParser.parseInlineStyles(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "wrong")!.lowerBound)
        let style = attributed.attribute(.strikethroughStyle, at: location, effectiveRange: nil) as? Int
        XCTAssertEqual(style, NSUnderlineStyle.single.rawValue)
    }

    func testLinkGetsLinkAttributeAndURL() {
        let text = "Check [this](https://example.com) out"
        let model = MarkdownDocumentModel(links: MarkdownParser.parseLinks(in: text))
        let attributed = MarkdownStyler.attributedString(for: text, model: model, baseFont: .systemFont(ofSize: 14), cursorLocation: nil)
        let location = text.distance(from: text.startIndex, to: text.range(of: "this")!.lowerBound)
        let url = attributed.attribute(.link, at: location, effectiveRange: nil) as? String
        XCTAssertEqual(url, "https://example.com")
    }
}
```

- [ ] **Step 6: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: FAIL — `MarkdownStyler` not found.

- [ ] **Step 7: Write `Sources/Marginal/Editor/MarkdownStyler.swift`**

```swift
import AppKit

struct MarkdownStyler {

    static let hiddenDelimiterFontSize: CGFloat = 0.1

    static func attributedString(
        for text: String,
        model: MarkdownDocumentModel,
        baseFont: NSFont,
        cursorLocation: String.Index?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ])

        let revealedStyles = cursorLocation.map {
            CursorRevealController.revealedInlineStyleSpans(in: model, cursorLocation: $0)
        } ?? []
        let revealedHeaders = cursorLocation.map {
            CursorRevealController.revealedHeaderSpans(in: model, cursorLocation: $0)
        } ?? []
        let hiddenFont = NSFont.systemFont(ofSize: hiddenDelimiterFontSize)

        for header in model.headers {
            let headerFont = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: headerPointSize(for: header.level, baseSize: baseFont.pointSize)),
                toHaveTrait: .boldFontMask
            )
            result.addAttribute(.font, value: headerFont, range: NSRange(header.contentRange, in: text))

            let markerRange = NSRange(header.markerRange, in: text)
            result.addAttribute(.font, value: revealedHeaders.contains(header) ? headerFont : hiddenFont, range: markerRange)
        }

        for span in model.inlineStyles {
            let contentRange = NSRange(span.contentRange, in: text)
            switch span.kind {
            case .bold:
                result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask), range: contentRange)
            case .italic:
                result.addAttribute(.font, value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask), range: contentRange)
            case .strikethrough:
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            case .underline:
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }

            let delimiterFont = revealedStyles.contains(span) ? baseFont : hiddenFont
            result.addAttribute(.font, value: delimiterFont, range: NSRange(span.openingDelimiterRange, in: text))
            result.addAttribute(.font, value: delimiterFont, range: NSRange(span.closingDelimiterRange, in: text))
        }

        for link in model.links {
            let textRange = NSRange(link.textRange, in: text)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            result.addAttribute(.link, value: link.url, range: textRange)
        }

        for item in model.listItems {
            result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(item.markerRange, in: text))
        }

        return result
    }

    static func plainSourceAttributedString(for text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
    }

    private static func headerPointSize(for level: Int, baseSize: CGFloat) -> CGFloat {
        let scale: [Int: CGFloat] = [1: 2.0, 2: 1.6, 3: 1.35, 4: 1.15, 5: 1.0, 6: 0.9]
        return baseSize * (scale[level] ?? 1.0)
    }
}
```

- [ ] **Step 8: Run to verify `MarkdownStylerTests` pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/MarkdownStylerTests`
Expected: PASS (all 6 tests).

- [ ] **Step 9: Commit**

```bash
git add Sources/Marginal/Editor/CursorRevealController.swift Sources/Marginal/Editor/MarkdownStyler.swift Tests/MarginalTests/CursorRevealControllerTests.swift Tests/MarginalTests/MarkdownStylerTests.swift
git commit -m "Add CursorRevealController and MarkdownStyler (spans + cursor -> NSAttributedString)"
```

---

## Task 8: Wire live styling into the editor

**Files:**
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`

**Interfaces:**
- Consumes: `MarkdownParser`, `MarkdownDocumentModel`, `MarkdownStyler` (Tasks 4–7).
- Produces: `DocumentViewController.currentCursorIndex() -> String.Index?` — Task 9 doesn't need this (reveal is already wired here), but Task 11 reuses it for `copyAsMarkdown`.

This task has no new pure-logic unit tests of its own — it wires already-tested pure functions together. Verification is the manual end-to-end check in Step 3.

- [ ] **Step 1: Replace `DocumentViewController.swift` with the styling-aware version**

```swift
import AppKit

final class DocumentViewController: NSViewController {

    private(set) var textView: MarkdownTextView!
    private var isApplyingProgrammaticEdit = false

    weak var document: MarkdownDocument?

    override func loadView() {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = MarkdownTextView()
        textView.isEditable = true
        textView.isRichText = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 40, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self

        scrollView.documentView = textView
        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.textView = textView
        self.view = containerView
    }

    func loadInitialText(_ text: String) {
        textView.string = text
        restyle(cursorLocation: nil)
    }

    func currentCursorIndex() -> String.Index? {
        let text = textView.string
        let location = textView.selectedRange().location
        guard location != NSNotFound, let range = Range(NSRange(location: location, length: 0), in: text) else { return nil }
        return range.lowerBound
    }

    private func restyle(cursorLocation: String.Index?) {
        let text = textView.string
        let model = MarkdownDocumentModel(
            inlineStyles: MarkdownParser.parseInlineStyles(in: text),
            headers: MarkdownParser.parseHeaders(in: text),
            listItems: MarkdownParser.parseListItems(in: text),
            links: MarkdownParser.parseLinks(in: text)
        )
        let attributed = MarkdownStyler.attributedString(
            for: text,
            model: model,
            baseFont: textView.font ?? NSFont.systemFont(ofSize: 15),
            cursorLocation: cursorLocation
        )

        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticEdit = true
        textView.textStorage?.beginEditing()
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            textView.textStorage?.setAttributes(attrs, range: range)
        }
        textView.textStorage?.endEditing()
        textView.setSelectedRange(selectedRange)
        isApplyingProgrammaticEdit = false
    }
}

extension DocumentViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        document?.text = textView.string
        document?.updateChangeCount(.changeDone)
        restyle(cursorLocation: currentCursorIndex())
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticEdit else { return }
        restyle(cursorLocation: currentCursorIndex())
    }
}
```

Note the restyle applies attributes via `setAttributes(_:range:)` on the existing `NSTextStorage`, never replacing the string — this only ever touches `.editedAttributes`, not `.editedCharacters`, keeping the string identity (and therefore undo of actual typing) intact.

- [ ] **Step 2: Regenerate and build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual end-to-end verification**

Launch the app (Xcode Run, or `open` the built `.app`).
1. Type `# Hello` — text renders large and bold, and the `# ` marker shrinks to invisible once you move the cursor off that line.
2. Click back into the header line — the `# ` marker reappears at normal size.
3. Type `Some **bold** and *italic* and ~~gone~~ and <u>under</u> text.` — confirm each renders with the correct style and delimiters are invisible when the cursor is elsewhere, visible when the cursor is inside that span.
4. Type `- one` then Enter then `- two` — confirm both lines are detected as list items (marker shown in a muted color).
5. Type `[a link](https://example.com)` — confirm the link text is colored/underlined.
6. Press `⌘Z` repeatedly after typing a sentence — confirm normal character-by-character undo still works (this validates the attribute-only restyle didn't corrupt undo).

Expected: all six checks pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Marginal/Document/DocumentViewController.swift
git commit -m "Wire live markdown parsing/styling into the editor on text and selection change"
```

---

## Task 9: Font size adjustment (⌘+ / ⌘-)

**Files:**
- Create: `Sources/Marginal/Editor/FontSizing.swift`
- Modify: `Sources/Marginal/Editor/MarkdownTextView.swift`
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Test: `Tests/MarginalTests/FontSizingTests.swift`

**Interfaces:**
- Produces: `FontSizing.minimumPointSize`, `FontSizing.maximumPointSize`, `FontSizing.increased(from:) -> CGFloat`, `FontSizing.decreased(from:) -> CGFloat`.

**Design decision:** Phase 1 has no full menu bar (see Global Constraints), so `⌘=`/`⌘-` (the same key combination Safari and other Mac apps use for zoom, since `=`/`+` share a key) are handled via a `keyDown(_:)` override on `MarkdownTextView` rather than menu items.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Marginal

final class FontSizingTests: XCTestCase {

    func testIncreaseAddsOnePoint() {
        XCTAssertEqual(FontSizing.increased(from: 14), 15)
    }

    func testIncreaseClampsAtMaximum() {
        XCTAssertEqual(FontSizing.increased(from: FontSizing.maximumPointSize), FontSizing.maximumPointSize)
    }

    func testDecreaseSubtractsOnePoint() {
        XCTAssertEqual(FontSizing.decreased(from: 14), 13)
    }

    func testDecreaseClampsAtMinimum() {
        XCTAssertEqual(FontSizing.decreased(from: FontSizing.minimumPointSize), FontSizing.minimumPointSize)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/FontSizingTests`
Expected: FAIL — `FontSizing` not found.

- [ ] **Step 3: Write `Sources/Marginal/Editor/FontSizing.swift`**

```swift
import CoreGraphics

struct FontSizing {
    static let minimumPointSize: CGFloat = 10
    static let maximumPointSize: CGFloat = 36
    static let step: CGFloat = 1

    static func increased(from size: CGFloat) -> CGFloat {
        min(size + step, maximumPointSize)
    }

    static func decreased(from size: CGFloat) -> CGFloat {
        max(size - step, minimumPointSize)
    }
}
```

- [ ] **Step 4: Run to verify tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/FontSizingTests`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Add a delegate protocol and wire `keyDown` in `MarkdownTextView.swift`**

```swift
import AppKit

protocol MarkdownTextViewShortcutDelegate: AnyObject {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView)
}

final class MarkdownTextView: NSTextView {

    weak var shortcutDelegate: MarkdownTextViewShortcutDelegate?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let characters = event.charactersIgnoringModifiers {
            switch characters {
            case "=":
                shortcutDelegate?.markdownTextViewIncreaseFontSize(self)
                return
            case "-":
                shortcutDelegate?.markdownTextViewDecreaseFontSize(self)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}
```

- [ ] **Step 6: Conform `DocumentViewController` to the delegate and persist size**

Add to `DocumentViewController.swift`, inside `loadView()` right after `textView.delegate = self`:

```swift
        textView.shortcutDelegate = self
        let savedSize = UserDefaults.standard.double(forKey: "editorFontPointSize")
        textView.font = NSFont.systemFont(ofSize: savedSize > 0 ? savedSize : 15)
```

Add a new extension at the bottom of the file:

```swift
extension DocumentViewController: MarkdownTextViewShortcutDelegate {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.increased(from: textView.font?.pointSize ?? 15))
    }

    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView) {
        setFontSize(FontSizing.decreased(from: textView.font?.pointSize ?? 15))
    }

    private func setFontSize(_ size: CGFloat) {
        textView.font = NSFont.systemFont(ofSize: size)
        UserDefaults.standard.set(size, forKey: "editorFontPointSize")
        restylePublic()
    }
}
```

Rename the existing `private func restyle(cursorLocation:)` to `func restylePublic(cursorLocation: String.Index? = nil)` — wait, keep it simpler: change its access level from `private` to `fileprivate` isn't needed since the new code is in the same file. Just call the existing `restyle(cursorLocation: currentCursorIndex())` directly instead of introducing `restylePublic`:

```swift
    private func setFontSize(_ size: CGFloat) {
        textView.font = NSFont.systemFont(ofSize: size)
        UserDefaults.standard.set(size, forKey: "editorFontPointSize")
        restyle(cursorLocation: currentCursorIndex())
    }
```

(Both `setFontSize` and `restyle` are defined in the same file, so `private` access is fine — no rename needed.)

- [ ] **Step 7: Regenerate, build**

Run: `xcodegen generate && xcodebuild -project Marginal.xcodeproj -scheme Marginal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Manual verification**

Launch the app, press `⌘=` five times — text visibly grows. Press `⌘-` five times — text shrinks back and stops at the 10pt floor if pressed further. Quit and relaunch — confirm the size persisted.

- [ ] **Step 9: Commit**

```bash
git add Sources/Marginal/Editor/FontSizing.swift Sources/Marginal/Editor/MarkdownTextView.swift Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/FontSizingTests.swift
git commit -m "Add persisted font size adjustment via Cmd+=/Cmd+-"
```

---

## Task 10: Show Source toggle and raw-markdown copy (`⌘⌥C`)

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownTextView.swift`
- Modify: `Sources/Marginal/Document/DocumentViewController.swift`
- Test: `Tests/MarginalTests/DocumentViewControllerTests.swift`

**Interfaces:**
- Produces: `DocumentViewController.toggleShowSource()`, `DocumentViewController.copyCurrentSelectionAsMarkdown()`.
- Consumes: `MarkdownStyler.plainSourceAttributedString` (Task 7), `currentCursorIndex()` / `restyle` (Task 8).

**Design decision:** ordinary `⌘C` already copies rendered rich text for free — that's simply `NSTextView`'s default `copy(_:)` behavior, since our text storage carries real `NSAttributedString` formatting. `⌘⌥C` is the new, custom shortcut for raw markdown.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import AppKit
@testable import Marginal

final class DocumentViewControllerTests: XCTestCase {

    func testCopyCurrentSelectionAsMarkdownPutsRawTextOnPasteboard() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("Hello **world**")
        viewController.textView.setSelectedRange(NSRange(location: 6, length: 9)) // "**world**"

        viewController.copyCurrentSelectionAsMarkdown()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**world**")
    }

    func testToggleShowSourceRendersPlainMonospaceText() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("# Title\n**bold**")

        viewController.toggleShowSource()

        let font = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.isFixedPitch ?? false)
    }

    func testToggleShowSourceTwiceRestoresStyledRendering() {
        let viewController = DocumentViewController()
        _ = viewController.view
        viewController.loadInitialText("**bold**")

        viewController.toggleShowSource()
        viewController.toggleShowSource()

        let font = viewController.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertFalse(font?.isFixedPitch ?? true)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/DocumentViewControllerTests`
Expected: FAIL — `copyCurrentSelectionAsMarkdown`/`toggleShowSource` not found.

- [ ] **Step 3: Add the `⌘⌥C` and Show Source shortcut to `MarkdownTextView.swift`**

Extend the protocol and `keyDown`:

```swift
protocol MarkdownTextViewShortcutDelegate: AnyObject {
    func markdownTextViewIncreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewDecreaseFontSize(_ textView: MarkdownTextView)
    func markdownTextViewCopyAsMarkdown(_ textView: MarkdownTextView)
    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView)
}
```

In `keyDown(with:)`, add two more cases before the `default: break`:

```swift
            case "c" where event.modifierFlags.contains(.option):
                shortcutDelegate?.markdownTextViewCopyAsMarkdown(self)
                return
            case "p" where event.modifierFlags.contains(.shift):
                shortcutDelegate?.markdownTextViewToggleShowSource(self)
                return
```

(Swift's `switch` on `characters` with `where` clauses on the already-matched `.command` outer condition works because both new shortcuts also require Command, matching the outer `if event.modifierFlags.contains(.command)` check; `.option`/`.shift` are additional modifiers checked in the `where` clause.)

- [ ] **Step 4: Implement in `DocumentViewController.swift`**

Add `private var isShowingSource = false` near the other stored properties, and these two methods plus delegate conformance:

```swift
    func copyCurrentSelectionAsMarkdown() {
        guard let range = Range(textView.selectedRange(), in: textView.string) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(textView.string[range]), forType: .string)
    }

    func toggleShowSource() {
        isShowingSource.toggle()
        let selectedRange = textView.selectedRange()
        isApplyingProgrammaticEdit = true
        if isShowingSource {
            let plain = MarkdownStyler.plainSourceAttributedString(for: textView.string, font: textView.font ?? NSFont.systemFont(ofSize: 15))
            textView.textStorage?.setAttributedString(plain)
        }
        isApplyingProgrammaticEdit = false
        textView.setSelectedRange(selectedRange)
        if !isShowingSource {
            restyle(cursorLocation: currentCursorIndex())
        }
    }
```

Add to the `MarkdownTextViewShortcutDelegate` extension:

```swift
    func markdownTextViewCopyAsMarkdown(_ textView: MarkdownTextView) {
        copyCurrentSelectionAsMarkdown()
    }

    func markdownTextViewToggleShowSource(_ textView: MarkdownTextView) {
        toggleShowSource()
    }
```

Note: `toggleShowSource`'s "on" branch uses `setAttributedString` (a full character-identity replace) rather than attribute-only `setAttributes`, because we're intentionally not touching content — this is fine since Show Source is a full-window display-mode flip the user explicitly invokes, not a per-keystroke operation, so any undo-stack disruption here is an accepted, isolated tradeoff (documented, not a placeholder).

- [ ] **Step 5: Run to verify tests pass**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/DocumentViewControllerTests`
Expected: PASS (all 3 tests).

- [ ] **Step 6: Manual verification**

Launch the app, type `Hello **world**`, select `**world**`, press `⌘⌥C`, paste into TextEdit or Notes — confirm the pasted text is the literal `**world**`, not styled bold text. Then select the same text and press plain `⌘C`, paste elsewhere — confirm it pastes as styled bold rich text. Press `⌘⇧P` — confirm the whole document flips to plain monospace raw markdown; press it again — confirm it flips back to styled rendering.

- [ ] **Step 7: Commit**

```bash
git add Sources/Marginal/Editor/MarkdownTextView.swift Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/DocumentViewControllerTests.swift
git commit -m "Add Cmd+Opt+C raw markdown copy and Cmd+Shift+P Show Source toggle"
```

---

## Task 11: Final Phase 1 verification pass and status update

**Files:**
- Modify: `/Users/jochem/dev/marginal/README.md`

**Interfaces:** none — this task only verifies and documents, no new production code.

- [ ] **Step 1: Run the full test suite**

Run: `xcodegen generate && xcodebuild test -project Marginal.xcodeproj -scheme Marginal`
Expected: all tests across `MarkdownParserTests`, `MarkdownStylerTests`, `CursorRevealControllerTests`, `FontSizingTests`, `MarkdownDocumentTests`, and `DocumentViewControllerTests` PASS.

- [ ] **Step 2: Full manual regression pass**

Repeat every manual verification step from Tasks 3, 8, 9, and 10 in one continuous session against a single fresh document, in this order: create new doc, exercise every formatting type, save, quit, reopen, adjust font size, toggle show source, copy-as-markdown, undo stress test. Confirm nothing regressed.

- [ ] **Step 3: Update `README.md` status line**

Change:
```markdown
> **Status: 🚧 In design.** Implementation hasn't started yet — see [`specs`](specs) for the current design spec.
```
to:
```markdown
> **Status: 🚧 Phase 1 complete (foundation + core WYSIWYG engine).** Tables, images, code highlighting, AI, visual polish, and export are not yet implemented — see [`specs`](specs) and [`plans`](plans).
```

- [ ] **Step 4: Commit and push**

```bash
git add README.md
git commit -m "Complete Phase 1: foundation + core WYSIWYG engine"
git push
```

---

## Self-Review Notes

- **Spec coverage:** bold/italic/strikethrough/underline/headers/lists/links rendering ✅ (Tasks 4–8); reveal-on-cursor ✅ (Task 7–8); native document architecture (open/save/autosave via `NSDocument`) ✅ (Tasks 2–3); font sizing ✅ (Task 9); Show Source + raw-markdown copy escape hatches ✅ (Task 10). Tables, images, code-block highlighting, AI, HIG visual polish (dark mode/materials/font family switch), export, and App Store packaging are explicitly deferred to future phase plans, per Global Constraints.
- **Placeholder scan:** no TBD/TODO markers; the two "Known v1 limitation" notes (Tasks 4, 5, 7) are concrete, bounded scope decisions, not unresolved gaps.
- **Type consistency:** `MarkdownDocumentModel`, `InlineStyleSpan`, `HeaderSpan`, `ListItemSpan`, `LinkSpan`, `MarkdownParser.parse*`, `MarkdownStyler.attributedString`/`plainSourceAttributedString`, `CursorRevealController.revealed*`, `FontSizing.increased/decreased`, `DocumentViewController.currentCursorIndex/copyCurrentSelectionAsMarkdown/toggleShowSource` are used with identical names and signatures everywhere they're referenced across tasks.
