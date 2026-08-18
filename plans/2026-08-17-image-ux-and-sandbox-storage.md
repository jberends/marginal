# Image UX & Sandbox-Safe Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make saving a document with pasted images work under the App Store sandbox (acquire folder access once, keep portable `<doc>.assets/` sidecar files), and make revealing an inline image keep the image anchored (small dimmed source below, normal-height caret) instead of reflowing the document.

**Architecture:** All managed (pasted/dropped-data) images always land in the per-document temp container first; relocation into `<doc>.assets/` happens only on an explicit user save, gated behind a one-time security-scoped folder-access grant. In-editor, the image's height is reserved as `paragraphSpacingBefore` (space above the markup line) so the image draws above a normal-height text line and the caret never balloons; when the image is active the markup shows in a small dimmed monospace font beneath the still-anchored image.

**Tech Stack:** Swift + AppKit, TextKit 1 (`NSLayoutManager`), `NSDocument`, security-scoped bookmarks + `NSOpenPanel`, XCTest.

## Global Constraints

- Swift + AppKit, no new dependencies. App is sandboxed (App Store): `com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-write`.
- Text storage always holds literal markdown source; display is length-preserving attributes (hide via font shrink `hiddenDelimiterFontSize = 0.1`, never deletion). No `NSTextAttachment`.
- Managed vs linked: managed = pasted/dropped image *data* (Marginal-owned; temp → `<doc>.assets/` on save). Linked = an existing image *file* dragged from Finder (absolute path, never copied).
- Relocation runs only on genuine user saves via `MarkdownDocument.shouldRelocateImages(for:)`, never autosave.
- Never silently write a markdown path the app can't back with a real file. Folder-access cancel/failure surfaces a visible `NSAlert`, not a swallowed `NSSound.beep()`.
- TDD. Tests go in the correct `XCTestCase` class and must actually run under `-only-testing:MarginalTests/<Class>` (verify the run count increases — this repo has a recurring "test misfiled into wrong class → silently skipped" bug). Full suite: `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`. NEVER run two `xcodebuild` at once (check `pgrep -x xcodebuild`); background long builds and watch the log.
- New `.swift` files: run `xcodegen generate`; the `.xcodeproj` is gitignored — never commit it.
- Every task that changes what's drawn or how save behaves is verified in the real app, not only by tests.
- Branch `image-insertion-0.10.0` (extends PR #4). Update `CHANGELOG.md` (Task 7).

## File Structure

- **Create** `Sources/Marginal/Document/DocumentFolderAccess.swift` — security-scoped folder-access bookmark store + acquisition (injectable panel for tests).
- **Create** `Tests/MarginalTests/DocumentFolderAccessTests.swift`.
- **Modify** `Sources/Marginal/Document/DocumentViewController.swift` — `insertImageData` (always temp), `prepareForSave` (folder access + cancel handling).
- **Modify** `Sources/Marginal/Document/MarkdownDocument.swift` — `.md` default extension.
- **Modify** `Sources/Marginal/Editor/MarkdownStyler.swift` — image reserve via `paragraphSpacingBefore`; small dimmed mono font when revealed; always attach `.marginalImage`.
- **Modify** `Sources/Marginal/Editor/MarkdownLayoutManager.swift` — draw image in the reserved space above the text line.
- **Modify** `Tests/MarginalTests/ImageInsertionTests.swift`, `MarkdownStylerTests.swift`, `VisualRenderHarnessTests.swift`.
- **Modify** `CHANGELOG.md`.

---

# Phase A — Sandbox-safe image storage

## Task 1: `insertImageData` always writes to the temp container

**Files:**
- Modify: `Sources/Marginal/Document/DocumentViewController.swift` (`insertImageData`)
- Test: `Tests/MarginalTests/ImageInsertionTests.swift`

**Interfaces:**
- Produces: `insertImageData(_ data: Data, sourceExtension: String, now: Date) -> String?` now ALWAYS returns an absolute temp path (via `imageStore.writeToTemp`), regardless of document save state. Relocation to `<doc>.assets/` happens only at save (Task 3).

- [ ] **Step 1: Update the tests to expect a temp path in both states**

In `ImageInsertionTests.swift`, the existing `testInsertImageDataSavedUsesRelativeAssetsPath` asserted a relative `MyNote.assets/…` path for a saved doc. Replace it so BOTH draft and saved documents get an absolute temp path:
```swift
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
```
Delete the old `testInsertImageDataSavedUsesRelativeAssetsPath` and keep `testInsertImageDataUntitledUsesAbsoluteTempPath` (still valid).

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/ImageInsertionTests test`
Expected: FAIL — the saved case currently returns `MyNote.assets/…`, not a temp path.

- [ ] **Step 3: Collapse `insertImageData` to always use temp**

Replace the body:
```swift
func insertImageData(_ data: Data, sourceExtension: String, now: Date) -> String? {
    let ext = Self.normalizedImageExtension(sourceExtension)
    do {
        // Always buffer managed images in the temp container. Writing directly beside a saved
        // document is impossible under the sandbox (a save panel grants access to the named
        // file only, not to create sibling files), so relocation into <doc>.assets/ is deferred
        // to an explicit user save (see prepareForSave), which acquires folder access first.
        let written = try imageStore.writeToTemp(data: data, ext: ext, now: now)
        return written.path
    } catch {
        NSSound.beep()
        return nil
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/ImageInsertionTests test`
Expected: PASS.

- [ ] **Step 5: Full suite, then commit**

Run the full suite once. Then:
```bash
git add Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/ImageInsertionTests.swift
git commit -m "refactor(editor): always buffer pasted images in temp (sandbox-safe)"
```

---

## Task 2: `DocumentFolderAccess` — security-scoped folder bookmarks

**Files:**
- Create: `Sources/Marginal/Document/DocumentFolderAccess.swift`
- Test: `Tests/MarginalTests/DocumentFolderAccessTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  ```swift
  @MainActor
  final class DocumentFolderAccess {
      /// `promptForFolder` is injected so tests exercise the bookmark store without UI. It is
      /// given the folder to request and the user-facing reason; returns the granted folder URL
      /// (security scope already started by the caller of acquireAccess), or nil if declined.
      init(defaults: UserDefaults = .standard,
           promptForFolder: @escaping (_ folder: URL, _ reason: String) -> URL? )

      /// Resolves a stored bookmark for `folder` into a usable URL, or nil if none/stale.
      /// The returned URL has NOT had security scope started; use `withAccess`.
      func writableURL(forFolder folder: URL) -> URL?

      /// Resolve-or-prompt. On a fresh grant, stores a bookmark. Returns the folder URL to use,
      /// or nil if the user declined. Security scope is NOT started here.
      func acquireAccess(toFolder folder: URL, reason: String) -> URL?

      /// Brackets start/stopAccessingSecurityScopedResource around `body`, passing the scoped URL.
      func withAccess<T>(toFolder folder: URL, reason: String, _ body: (URL) throws -> T) rethrows -> T?
  }
  ```
- Note: `withAccess` returns nil (without calling `body`) if access can't be acquired.

- [ ] **Step 1: Write the failing tests**

`DocumentFolderAccessTests.swift`:
```swift
import XCTest
@testable import Marginal

@MainActor
final class DocumentFolderAccessTests: XCTestCase {
    private func tempFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func isolatedDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "fa-test-\(UUID().uuidString)")!
        return d
    }

    func testAcquirePromptsWhenNoBookmarkThenReusesWithoutPrompting() throws {
        let folder = try tempFolder()
        var promptCount = 0
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { requested, _ in
            promptCount += 1
            return requested   // user grants the requested folder
        }
        let first = access.acquireAccess(toFolder: folder, reason: "test")
        XCTAssertEqual(first?.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(promptCount, 1)

        // Second acquire for the same folder must resolve the stored bookmark, not prompt again.
        let second = access.acquireAccess(toFolder: folder, reason: "test")
        XCTAssertEqual(second?.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(promptCount, 1, "a stored bookmark must be reused without re-prompting")
    }

    func testAcquireReturnsNilWhenUserDeclines() throws {
        let folder = try tempFolder()
        let access = DocumentFolderAccess(defaults: isolatedDefaults()) { _, _ in nil }
        XCTAssertNil(access.acquireAccess(toFolder: folder, reason: "test"))
    }

    func testWithAccessRunsBodyWhenGrantedAndSkipsWhenDeclined() throws {
        let folder = try tempFolder()
        let granting = DocumentFolderAccess(defaults: isolatedDefaults()) { req, _ in req }
        var ran = false
        let result = granting.withAccess(toFolder: folder, reason: "r") { url -> String in
            ran = true
            return url.lastPathComponent
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(result, folder.lastPathComponent)

        let declining = DocumentFolderAccess(defaults: isolatedDefaults()) { _, _ in nil }
        var ranB = false
        let r2 = declining.withAccess(toFolder: folder, reason: "r") { _ in ranB = true; return 1 }
        XCTAssertFalse(ranB)
        XCTAssertNil(r2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/DocumentFolderAccessTests test`
Expected: FAIL — `DocumentFolderAccess` undefined.

- [ ] **Step 3: Implement `DocumentFolderAccess`**

```swift
import AppKit

@MainActor
final class DocumentFolderAccess {
    private let defaults: UserDefaults
    private let promptForFolder: (_ folder: URL, _ reason: String) -> URL?
    private static let bookmarksKey = "imageFolderBookmarks"

    init(defaults: UserDefaults = .standard,
         promptForFolder: @escaping (_ folder: URL, _ reason: String) -> URL?) {
        self.defaults = defaults
        self.promptForFolder = promptForFolder
    }

    convenience init(defaults: UserDefaults = .standard) {
        // Live path: a directory NSOpenPanel pre-pointed at the folder.
        self.init(defaults: defaults) { folder, reason in
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.prompt = "Grant Access"
            panel.message = reason
            return panel.runModal() == .OK ? panel.url : nil
        }
    }

    private func bookmarks() -> [String: Data] {
        defaults.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
    }
    private func setBookmark(_ data: Data, for key: String) {
        var b = bookmarks(); b[key] = data; defaults.set(b, forKey: Self.bookmarksKey)
    }
    private func removeBookmark(for key: String) {
        var b = bookmarks(); b.removeValue(forKey: key); defaults.set(b, forKey: Self.bookmarksKey)
    }
    private func key(for folder: URL) -> String { folder.standardizedFileURL.path }

    func writableURL(forFolder folder: URL) -> URL? {
        let k = key(for: folder)
        guard let data = bookmarks()[k] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale), !stale else {
            removeBookmark(for: k)
            return nil
        }
        return url
    }

    func acquireAccess(toFolder folder: URL, reason: String) -> URL? {
        if let existing = writableURL(forFolder: folder) { return existing }
        guard let granted = promptForFolder(folder, reason) else { return nil }
        if let data = try? granted.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) {
            setBookmark(data, for: key(for: granted))
        }
        return granted
    }

    func withAccess<T>(toFolder folder: URL, reason: String, _ body: (URL) throws -> T) rethrows -> T? {
        guard let url = acquireAccess(toFolder: folder, reason: reason) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}
```
Note: in tests the injected `promptForFolder` returns a plain temp URL; `bookmarkData(options: .withSecurityScope)` on a non-scoped URL may return nil, so the store simply won't cache — that's fine for the decline/grant assertions, EXCEPT the reuse test. To make the reuse test deterministic without real security scope, guard the store so that when no bookmark data is produced we still remember the granted path in-memory for the session: add `private var sessionGranted: Set<String> = []`; in `acquireAccess`, after a grant, insert `key(for: granted)`; in `writableURL`, if `sessionGranted.contains(k)` return the folder URL built from `k`. This keeps the live security-scope path intact while making tests deterministic. Implement that in/around the methods above.

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project Marginal.xcodeproj -scheme Marginal -only-testing:MarginalTests/DocumentFolderAccessTests test`
Expected: PASS (3 tests).

- [ ] **Step 5: Register the file, full suite, commit**

```bash
xcodegen generate
```
Run the full suite once. Then:
```bash
git add Sources/Marginal/Document/DocumentFolderAccess.swift Tests/MarginalTests/DocumentFolderAccessTests.swift
git commit -m "feat(document): security-scoped folder-access store for image sidecar files"
```

---

## Task 3: Acquire folder access on save; relocate; handle decline

**Files:**
- Modify: `Sources/Marginal/Document/DocumentViewController.swift` (`prepareForSave`; add an `imageFolderAccess` property and a testable seam)
- Test: `Tests/MarginalTests/ImageInsertionTests.swift`

**Interfaces:**
- Consumes: `DocumentFolderAccess` (Task 2), `imageStore.relocateTempFiles`, `MarkdownParser.parseImages`.
- Produces: `prepareForSave(to:now:)` acquires write access to the target folder before relocating; on decline it leaves temp paths untouched and shows a warning; on grant it relocates inside the security scope.

- [ ] **Step 1: Write the failing test (inject a granting and a declining access)**

Add to `ImageInsertionTests.swift`. Add a test hook property on the controller: `var imageFolderAccess: DocumentFolderAccess` (default the live one; tests replace it). Tests:
```swift
func testPrepareForSaveWithGrantedAccessRelocates() throws {
    let (vc, _) = try makeVC(saved: false)
    let now = Date(timeIntervalSince1970: 1_755_000_000)
    let temp = try XCTUnwrap(vc.insertImageData(ImageInsertionTests.onePixelPNG(), sourceExtension: "png", now: now))
    vc.textView.string = "x ![](\(temp)) y"
    vc.document?.text = vc.textView.string

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    vc.imageFolderAccess = DocumentFolderAccess(defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!) { req, _ in req }

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
```

- [ ] **Step 2: Run to verify failure**

Run: `-only-testing:MarginalTests/ImageInsertionTests`. Expected: FAIL — `imageFolderAccess` / `suppressSaveWarningForTests` undefined; declined-path behavior not implemented.

- [ ] **Step 3: Implement**

Add properties to `DocumentViewController`:
```swift
lazy var imageFolderAccess = DocumentFolderAccess()
var suppressSaveWarningForTests = false
```
Rewrite `prepareForSave` to acquire access and drop the beep-and-swallow:
```swift
func prepareForSave(to targetURL: URL, now: Date) {
    let docName = targetURL.deletingPathExtension().lastPathComponent
    let folder = targetURL.deletingLastPathComponent()
    let assetsDir = folder.appendingPathComponent("\(docName).assets", isDirectory: true)

    let text = textView.string
    let spans = MarkdownParser.parseImages(in: text)
    let managed = spans.compactMap { span -> (ImageSpan, URL)? in
        let url = URL(fileURLWithPath: span.path)
        return imageStore.isManagedTemp(url) ? (span, url) : nil
    }
    guard !managed.isEmpty else { return }

    var seen = Set<URL>()
    let uniqueManagedURLs = managed.map { $0.1 }.filter { seen.insert($0).inserted }
    let reason = "Marginal needs permission to save this document's images in this folder."

    let moveMap: [URL: URL]? = imageFolderAccess.withAccess(toFolder: folder, reason: reason) { _ in
        try? imageStore.relocateTempFiles(uniqueManagedURLs, into: assetsDir, now: now)
    } ?? nil

    guard let moveMap, !moveMap.isEmpty else {
        // Declined, or the move failed: keep the temp paths (the text still saves, images still
        // resolve from temp this session) and warn — never a silent dead reference.
        warnImagesNotSaved()
        return
    }

    var mutable = text
    for (span, oldURL) in managed.sorted(by: { $0.0.pathRange.lowerBound > $1.0.pathRange.lowerBound }) {
        guard let newURL = moveMap[oldURL] else { continue }
        mutable.replaceSubrange(span.pathRange, with: "\(docName).assets/\(newURL.lastPathComponent)")
    }
    textView.string = mutable
    document?.text = mutable
    restyle(cursorLocation: currentCursorIndex())
}

private func warnImagesNotSaved() {
    guard !suppressSaveWarningForTests else { return }
    let alert = NSAlert()
    alert.messageText = "Images were not saved alongside the document"
    alert.informativeText = "Folder access was declined, so pasted images remain temporary and may be lost. Save again and grant access to keep them."
    alert.alertStyle = .warning
    if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
}
```
Note: `withAccess` returns `T?` (nil if declined); with `T == [URL:URL]?` (because `relocateTempFiles` is `try?`), the result is `[URL:URL]??` — the `?? nil` flattens it. Verify the optional flattening compiles; if the double-optional is awkward, change the closure to return a non-optional by doing the `do/catch` inside and returning `[:]` on throw, then treat empty as failure.

- [ ] **Step 4: Run to verify pass**

Run: `-only-testing:MarginalTests/ImageInsertionTests`. Expected: PASS (both new tests + existing).

- [ ] **Step 5: Full suite, commit**

Full suite once. Then:
```bash
git add Sources/Marginal/Document/DocumentViewController.swift Tests/MarginalTests/ImageInsertionTests.swift
git commit -m "feat(document): acquire folder access on save; warn instead of losing images"
```

- [ ] **Step 6: Real-app verification (required)**

Launch the rebuilt app. New doc → paste a screenshot → ⌘S → Save As to `~/Downloads` → a folder-access panel appears once → confirm `~/Downloads/<name>.assets/pasted-….png` exists, the editor shows the relative path, and reopening the doc shows the image. Save again to the same folder → no second prompt. Decline the prompt once → confirm the warning sheet and that the temp path is retained (no crash, no beep-only).

---

## Task 4: Default the proposed save extension to `.md`

**Files:**
- Modify: `Sources/Marginal/Document/MarkdownDocument.swift`
- Test: `Tests/MarginalTests/MarkdownDocumentTests.swift`

**Interfaces:**
- Produces: `MarkdownDocument` proposes `.md` for new documents.

- [ ] **Step 1: Write the failing test**

Add to `MarkdownDocumentTests.swift`:
```swift
func testDefaultSaveExtensionIsMd() {
    let doc = MarkdownDocument()
    let ext = doc.fileNameExtension(forType: doc.fileType ?? "net.daringfireball.markdown",
                                    saveOperation: .saveOperation)
    XCTAssertEqual(ext, "md")
}
```
(If `doc.fileType` is nil in a unit context, pass the exported UTI string `"net.daringfireball.markdown"` directly, as above.)

- [ ] **Step 2: Run to verify failure**

Run: `-only-testing:MarginalTests/MarkdownDocumentTests`. Expected: FAIL — default is `markdown`.

- [ ] **Step 3: Override the preferred extension**

In `MarkdownDocument`:
```swift
override func fileNameExtension(forType typeName: String,
                               saveOperation: NSDocument.SaveOperationType) -> String? {
    "md"
}
```

- [ ] **Step 4: Run to verify pass**

Run: `-only-testing:MarginalTests/MarkdownDocumentTests`. Expected: PASS.

- [ ] **Step 5: Full suite, commit**

```bash
git add Sources/Marginal/Document/MarkdownDocument.swift Tests/MarginalTests/MarkdownDocumentTests.swift
git commit -m "fix(document): propose .md (not .markdown) as the default save extension"
```

---

# Phase B — anchored reveal UX

## Task 5: Reserve image height as space-above; small dimmed source when active

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownStyler.swift` (image styling block, ~line 749–771)
- Test: `Tests/MarginalTests/MarkdownStylerTests.swift`

**Interfaces:**
- Consumes: `.marginalImage`/`ImageDisplayInfo` (existing), `hiddenFont`, `revealedImages`.
- Produces: for every image span (revealed or not), attaches `.marginalImage` + a paragraph style whose `paragraphSpacingBefore == displaySize.height` (NOT min/max line height). Markup font is the shrunk hidden font when inactive, and a small dimmed monospace font when active/revealed.

- [ ] **Step 1: Write the failing tests**

Add to `MarkdownStylerTests` (the real image-test class — confirm placement by run count):
```swift
func testInactiveImageReservesSpaceAboveAndHidesMarkupAtNormalLineHeight() {
    let text = "![a](/tmp/x.png)\nnext"
    let attr = MarkdownStyler.attributedString(   // use the real entry-point name/signature
        for: MarkdownParser.parse(text), text: text, baseFont: .systemFont(ofSize: 16),
        cursorLocation: text.index(text.startIndex, offsetBy: 18),  // in "next", image inactive
        selectedRange: nil, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
    let full = NSRange(location: 0, length: ("![a](/tmp/x.png)" as NSString).length)
    let ps = attr.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    XCTAssertEqual(ps?.paragraphSpacingBefore, 200, accuracy: 0.5)
    XCTAssertEqual(ps?.maximumLineHeight ?? 0, 0, "line height must stay natural (0 = unconstrained), not 200")
    let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    XCTAssertEqual(font?.pointSize ?? 99, MarkdownStyler.hiddenDelimiterFontSize, accuracy: 0.001)
    XCTAssertNotNil(attr.attribute(.marginalImage, at: 0, effectiveRange: nil))
    _ = full
}

func testActiveImageShowsSmallDimmedMonospaceSourceAndStillDrawsImage() {
    let text = "![a](/tmp/x.png)"
    let attr = MarkdownStyler.attributedString(
        for: MarkdownParser.parse(text), text: text, baseFont: .systemFont(ofSize: 16),
        cursorLocation: text.index(text.startIndex, offsetBy: 3),  // inside → active
        selectedRange: nil, documentBaseURL: URL(fileURLWithPath: "/tmp/"))
    let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    XCTAssertNotNil(font)
    XCTAssertLessThan(font!.pointSize, 16, "active source is smaller than body")
    XCTAssertGreaterThan(font!.pointSize, MarkdownStyler.hiddenDelimiterFontSize, "not the 0.1pt hidden font")
    XCTAssertTrue(font!.isFixedPitch, "active source is monospace")
    let color = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    XCTAssertEqual(color, .secondaryLabelColor)
    XCTAssertNotNil(attr.attribute(.marginalImage, at: 0, effectiveRange: nil), "image still drawn when active")
}
```
(Match `MarkdownStyler`'s real entry-point name and parameter order — read the file. The two tests assert the behavioral contract regardless of exact call shape.)

- [ ] **Step 2: Run to verify failure**

Run: `-only-testing:MarginalTests/MarkdownStylerTests`. Expected: FAIL (current code uses min/max line height and skips styling when revealed).

- [ ] **Step 3: Rewrite the image styling block**

Replace the `for image in images { … }` block:
```swift
let activeSourceFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.8, weight: .regular)

for image in images {
    let fullNSRange = NSRange(image.fullRange, in: text)

    let resolvedURL: URL
    if image.path.hasPrefix("/") {
        resolvedURL = URL(fileURLWithPath: image.path)
    } else if let base = documentBaseURL {
        resolvedURL = URL(fileURLWithPath: image.path, relativeTo: base).standardizedFileURL
    } else {
        continue // relative path, no base to resolve against
    }

    let info = ImageDisplayInfo(resolvedURL: resolvedURL,
                                displaySize: NSSize(width: 320, height: 200))
    // Always draw the image (anchored). Reserve its height as space ABOVE the markup line so
    // the text line keeps a natural height -> the caret never balloons to the image height.
    result.addAttribute(.marginalImage, value: info, range: fullNSRange)

    let reserveStyle = NSMutableParagraphStyle()
    reserveStyle.paragraphSpacingBefore = info.displaySize.height
    result.addAttribute(.paragraphStyle, value: reserveStyle, range: fullNSRange)

    if revealedImages.contains(image) {
        // Active: show the raw markdown small and dimmed, beneath the anchored image.
        result.addAttribute(.font, value: activeSourceFont, range: fullNSRange)
        result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullNSRange)
    } else {
        // Inactive: hide the markup.
        result.addAttribute(.font, value: hiddenFont, range: fullNSRange)
    }
}
```
Note: the earlier `guard !revealedImages.contains(image) else { continue }` is GONE — revealed images are still attributed (image drawn) but with the visible small font.

- [ ] **Step 4: Run to verify pass**

Run: `-only-testing:MarginalTests/MarkdownStylerTests`. Expected: PASS. Confirm the run count increased (new tests actually ran).

- [ ] **Step 5: Full suite, commit**

```bash
git add Sources/Marginal/Editor/MarkdownStyler.swift Tests/MarginalTests/MarkdownStylerTests.swift
git commit -m "feat(editor): anchor inline images (space-above reserve) with small dimmed source when active"
```

---

## Task 6: Draw the image in the reserved space above the text line

**Files:**
- Modify: `Sources/Marginal/Editor/MarkdownLayoutManager.swift` (`.marginalImage` draw pass, ~line 323–344)
- Test: `Tests/MarginalTests/VisualRenderHarnessTests.swift`

**Interfaces:**
- Consumes: `.marginalImage`, the `paragraphSpacingBefore`-inflated line fragment from Task 5.

- [ ] **Step 1: Write the failing/again-passing visual tests**

The existing `testInlineImageIsDrawn` should still pass (image present in its band). Add an active-state test asserting the small source renders (image still present) and that the image sits in the TOP region:
```swift
func testActiveImageKeepsImageDrawnWithSourceBelow() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("blue-\(UUID().uuidString).png")
    let img = NSImage(size: NSSize(width: 60, height: 40))
    img.lockFocus(); NSColor.blue.setFill(); NSRect(x:0,y:0,width:60,height:40).fill(); img.unlockFocus()
    try NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: url)
    // Cursor inside the image markup -> active. Image must still paint blue.
    let png = try renderToPNG(text: "before\n\n![](\(url.path))\n\nafter", cursorInsideImage: true) // adapt to real harness API
    let rep = NSBitmapImageRep(data: png)!
    var sawBlue = false
    for y in 0..<rep.pixelsHigh { for x in stride(from: 0, to: rep.pixelsWide, by: 6) {
        if let c = rep.colorAt(x: x, y: y), c.blueComponent > 0.6, c.redComponent < 0.3 { sawBlue = true }
    }; if sawBlue { break } }
    XCTAssertTrue(sawBlue, "image stays drawn when its source is revealed")
    try? FileManager.default.removeItem(at: url)
}
```
(Read `renderToPNG`'s real signature; if it can't place the cursor, drive the styler with a cursor inside the image range as the harness allows. The key assertion: image still paints in the active state.)

- [ ] **Step 2: Run to verify current behavior**

Run: `-only-testing:MarginalTests/VisualRenderHarnessTests`. The existing test may still pass; the new active-state test likely FAILS if the draw rect assumed the old full-height line (the reserved space is now above, via paragraphSpacingBefore).

- [ ] **Step 3: Draw in the reserved space above the text**

Update the `.marginalImage` draw pass. The line fragment now includes `paragraphSpacingBefore` (≈ image height) ABOVE the text's used rect. Draw the image in that top region:
```swift
textStorage.enumerateAttribute(.marginalImage, in: fullRange) { value, range, _ in
    guard let info = value as? ImageDisplayInfo,
          let image = ImageCache.shared.image(at: info.resolvedURL) else { return }
    let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    guard glyphRange.location < self.numberOfGlyphs else { return }
    var effective = NSRange(location: 0, length: 0)
    let lineRect = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &effective)
    let usedRect = self.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
    // The image occupies the leading space (paragraphSpacingBefore) above the text's used rect.
    let reservedHeight = max(0, usedRect.minY - lineRect.minY)  // == displaySize.height
    let box = NSRect(
        x: origin.x + lineRect.minX + 4,
        y: origin.y + lineRect.minY + 2,
        width: min(info.displaySize.width, lineRect.width - 8),
        height: reservedHeight - 4
    )
    guard box.width > 0, box.height > 0 else { return }
    let fitted = Self.aspectFit(imageSize: image.size, into: box)
    image.draw(in: fitted, from: .zero, operation: .sourceOver, fraction: 1.0,
               respectFlipped: true, hints: nil)
}
```
IMPORTANT: `lineFragmentUsedRect` vs `lineFragmentRect` and how `paragraphSpacingBefore` distributes within the fragment is exactly the geometry to confirm on-device — if `usedRect.minY - lineRect.minY` does not equal the reserved height in practice, fall back to `height: info.displaySize.height - 4` and position from `lineRect.minY`. Verify empirically (Step 5).

- [ ] **Step 4: Run to verify pass**

Run: `-only-testing:MarginalTests/VisualRenderHarnessTests`. Expected: PASS (image present in both states).

- [ ] **Step 5: Real-app verification (required — this is the risky TextKit geometry)**

Launch the rebuilt app. Confirm: inactive image looks the same as before (anchored, correct size); clicking the image keeps it anchored and shows the small dimmed source directly beneath it; the **caret is normal height** (not 200pt); clicking away collapses the source with no document-wide jump. If the image is mispositioned, apply the Step-3 fallback and re-verify.

- [ ] **Step 6: Full suite, commit**

```bash
git add Sources/Marginal/Editor/MarkdownLayoutManager.swift Tests/MarginalTests/VisualRenderHarnessTests.swift
git commit -m "feat(editor): draw anchored image in reserved space above its source line"
```

---

## Task 7: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a 0.10.0 image section**

Under the 0.10.0 entry (create the heading if absent), add:
```markdown
### Added
- Insert images by paste, screenshot, or drag. Pasted images render inline in the editor;
  click an image to reveal its markdown source beneath it.
- Images export to PDF and HTML, and copy as HTML with the picture embedded.

### Fixed
- Saving a document with pasted images now works: Marginal asks once for permission to the
  document's folder and stores the images in a sibling `<name>.assets/` folder.
- New documents are proposed with a `.md` extension.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for image insertion (0.10.0)"
```

---

## Self-review (author-completed)

- **Spec coverage:** temp-always storage (T1), folder-access bookmark store (T2), acquire-on-save + decline warning (T3), `.md` extension (T4), space-above reserve + small dimmed active source (T5), draw-above (T6), changelog (T7). Every spec decision maps to a task.
- **Type consistency:** `DocumentFolderAccess` API (`acquireAccess`, `writableURL`, `withAccess`) identical across T2/T3; `insertImageData(_:sourceExtension:now:)` unchanged signature (T1); `ImageDisplayInfo(resolvedURL:displaySize:)` unchanged (T5/T6); `prepareForSave(to:now:)` unchanged signature (T3).
- **Placeholder scan:** every code step carries real Swift. Items flagged "match the real entry-point name" (MarkdownStyler) and "confirm the fragment geometry on device" (T6) are explicit verification instructions with concrete fallbacks, not TODOs.
- **Risk notes:** the double-optional flatten in T3 and the `usedRect`/`paragraphSpacingBefore` geometry in T6 are called out with fallbacks.
