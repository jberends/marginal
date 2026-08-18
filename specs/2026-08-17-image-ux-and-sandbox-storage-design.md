# Image UX & sandbox-safe storage — design

**Date:** 2026-08-17
**Status:** Approved, ready for implementation plan.
**Context:** Follow-up polish on the image-insertion feature (PR #4, branch `image-insertion-0.10.0`), driven by daily-use feedback. Two independent problems surfaced, plus one trivial fix.

---

## Problem 1 — sidecar images can't be written under the App Store sandbox

Saving a document with a pasted image to a normal location (e.g. `~/Downloads`) fails: no `<doc>.assets/` folder is created and the app beeps. Root cause (confirmed against Apple's App Sandbox docs): a save panel extends the sandbox to **exactly the file URL the user named**, not to the containing directory, so creating a sibling `<doc>.assets/` directory is denied. `relocateTempFiles` throws → `prepareForSave`'s `catch { NSSound.beep() }` → the document is saved with the image's **absolute temp path**, which breaks once the temp container is cleared. Marginal ships on the App Store, so the sandbox is mandatory.

### Decision: keep sidecar files (portable images beside the `.md`), acquire folder access once

1. **All managed images always go to the temp container first.** Drop `insertImageData`'s current "saved document → write straight into `<doc>.assets/`" branch (that write hits the same sandbox wall). Every pasted/dropped-data image is written to the per-document temp dir with an **absolute** path, regardless of whether the document is saved. Consequence: pasting never needs a permission prompt, and the image resolves/renders immediately from its absolute temp path.
2. **Folder access is acquired only at an explicit user save.** When the save funnel runs for a genuine user save (`.saveOperation`/`.saveAsOperation`/`.saveToOperation`, never autosave) and the document contains managed temp images, the app must be able to write `<doc>.assets/` beside the target. If it does not already hold write access to the target folder, it presents a one-time **`NSOpenPanel`** — directories only, pre-pointed at `targetURL.deletingLastPathComponent()`, with a clear message ("Marginal needs permission to save this document's images in this folder"). On the user's selection it obtains and persists a **security-scoped bookmark**, then wraps the `<doc>.assets/` writes in `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.
3. **Bookmarks are reused.** Stored in `UserDefaults` keyed by the resolved folder path. A later save (or a future paste-then-save) into the same folder finds a valid bookmark and does not re-prompt. Stale bookmarks (the `bookmarkDataIsStale` flag, or a resolve failure) are discarded and re-acquired.
4. **Cancel is safe, never silent data loss.** If the user cancels the permission prompt, the app does NOT rewrite paths to a location it can't write. It leaves the images at their absolute temp paths, still saves the text, and surfaces a visible, dismissible warning (an `NSAlert` sheet: "Images were not saved alongside the document because folder access was declined; they remain temporary and may be lost."). Better a visible warning than a silently dead reference.

### Components
- **`DocumentFolderAccess`** (new, `Sources/Marginal/Document/DocumentFolderAccess.swift`, `@MainActor`): owns the bookmark store and access acquisition.
  - `func writableURL(forFolder folder: URL) -> URL?` — returns a security-scoped URL the caller may write into, resolving a stored bookmark if present (refreshing on stale), else returning `nil` (caller must prompt).
  - `func acquireAccess(toFolder folder: URL, prompt: String) -> URL?` — resolves an existing bookmark or presents the directory `NSOpenPanel`; on grant, stores the bookmark and returns the scoped URL; on cancel returns `nil`.
  - `func withAccess(toFolder:_ body:)` helper that brackets `start/stopAccessingSecurityScopedResource`.
  - Bookmark persistence: `UserDefaults` dict `imageFolderBookmarks: [folderPath: Data]`.
  - Unit-testable seam: the panel-presentation is injected (a closure returning an optional URL) so tests exercise the bookmark store + resolve/stale logic without UI; the live path uses `NSOpenPanel`.
- **`insertImageData`** (`DocumentViewController`): collapses to always `writeToTemp` (absolute). No document-state branch.
- **`prepareForSave`** (`DocumentViewController`): unchanged gating (user saves only). Before relocating, calls `DocumentFolderAccess.acquireAccess(toFolder: assetsDir.deletingLastPathComponent(), …)`; if `nil` (cancelled/failed), abort relocation, keep temp paths, show the warning, do NOT beep-and-swallow. If granted, bracket the relocate in `withAccess`.

### Testing
- `DocumentFolderAccessTests`: bookmark round-trip (store → resolve returns a usable URL), stale handling (a stale/invalid bookmark is discarded and `writableURL` returns nil), and that a granted (injected) folder yields a scoped URL. The real `NSOpenPanel` path is covered by manual verification.
- `insertImageData` tests: both draft and saved documents now write to temp (absolute path) — update the existing "saved → relative" assertion accordingly.
- Save-relocation tests: with an injected granting folder-access, a user save relocates temp → `<doc>.assets/` and rewrites relative (existing tests adapted to go through the access seam); with an injected cancel, paths stay absolute and no exception escapes.
- **Real-app verification (required):** paste into an untitled doc → Save As to `~/Downloads` → permission prompt appears once → `<doc>.assets/` is created with the image → the markdown shows the relative path → reopening resolves the image. Second save to the same folder does not re-prompt.

---

## Problem 2 — revealing an image reflows the whole document (and a giant caret)

Clicking an image swaps its compact ~200pt rendered box for its raw `![](path)` markdown wrapped across several lines, so everything below jumps; and the caret on/near the image balloons to ~200pt tall. Both stem from reserving the image's height as the markup line's **line height** (`minimumLineHeight`/`maximumLineHeight` = 200) and hiding the markup only when inactive.

Framed against Laws of UX: the layout shift undercuts the **Doherty Threshold** (instant but destabilising), and it violates **Jakob's Law** — the editors users know (Typora, Obsidian live-preview, Notion) keep the image anchored on click. The fix should also read as one grouped unit (**Law of Common Region / Uniform Connectedness**).

### Decision: image stays anchored; small dimmed source appears below; reserve height as space-*above*

- **Reserve the image's height as `paragraphSpacingBefore` on the markup paragraph, not as line height.** The image is drawn into that reserved space *above* the markup's text line (same layout-manager drawing, targeting the top region of the line fragment). The markup line itself keeps a **normal text line height**, so the caret is normal-sized in every state — this removes the giant caret.
- **Inactive** (caret/selection not on the image): markup hidden via the existing shrunk hidden-delimiter font; only the image shows (in the reserved space above the ~0-height hidden line). Visually unchanged from today's inactive look.
- **Active** (caret on the image / selection intersects): the markup renders in a **small, dimmed monospace** font (≈0.8× base size, `secondaryLabelColor`) — NOT the 0.1pt hidden font and NOT full body size — appearing as a compact source line directly beneath the still-anchored image. Editing happens there. Toggling active only adds/removes that small source line below the image; the image never moves.

### Components
- **`MarkdownStyler`** (image styling block, ~line 749): replace the `minimumLineHeight/maximumLineHeight` reserve with `paragraphSpacingBefore = info.displaySize.height` on the markup range; when the image is *active/revealed*, apply the small dimmed monospace font over the markup range instead of leaving it fully body-styled (and still attach `.marginalImage` so the image draws above); when inactive, keep the hidden-delimiter font as today.
- **`MarkdownLayoutManager`** (`drawBackground`, image pass): draw the image in the top `displaySize.height` region of the line fragment (the `paragraphSpacingBefore` area) rather than the whole fragment; keep aspect-fit; keep the decode cache.

### Testing
- `MarkdownStylerTests`: inactive → markup run carries the hidden font + `.marginalImage` + `paragraphSpacingBefore == displaySize.height` and normal line height; active → markup run carries the small dimmed monospace font (assert point size and `secondaryLabelColor`) + still `.marginalImage`, and the line height is normal (NOT 200).
- `VisualRenderHarnessTests`: image present in its reserved band in BOTH states; in the active state the small source band is present *below* the image; assert the markup line-fragment height is normal (≈ a text line, not ~200pt) so the caret can't be giant.
- **Real-app verification (required):** click an image → image holds position, small dimmed source appears beneath it, caret is normal height; click away → source collapses, no document-wide jump.

---

## Problem 3 (trivial) — default save extension

New documents propose a `.markdown` filename. Default the proposed extension to **`.md`** (the type already lists both; make `md` the preferred/first extension and, if needed, override `NSDocument.fileNameExtension(forType:saveOperation:)` to return `"md"`). Do not otherwise touch the user-chosen URL (the sandbox forbids "fixing" it).

---

## Global constraints (bind every task)

- Swift + AppKit, no new dependencies. App is sandboxed (App Store): `com.apple.security.app-sandbox`, `files.user-selected.read-write`.
- Text storage always holds literal markdown source; all display is length-preserving attributes (hide via font-shrink, never deletion). No `NSTextAttachment`.
- Managed vs linked rule unchanged: managed = pasted/dropped image *data* (Marginal-owned, temp → `<doc>.assets/` on save); linked = an existing image *file* dragged from Finder (absolute path, never copied).
- Relocation runs only on genuine user saves (`shouldRelocateImages`), never autosave.
- Never silently write a path the app can't back with a real file — cancel/failure surfaces a visible warning, not a swallowed beep.
- TDD; tests live in the correct `XCTestCase` class and must actually run under the class-scoped filter (this repo has a recurring misfiling bug). Test target `MarginalTests`; full run `xcodebuild -project Marginal.xcodeproj -scheme Marginal test`; never run two `xcodebuild` at once.
- Every task that changes what's drawn or how a keystroke/save behaves is verified in the real app, not just by tests.
- Lands on branch `image-insertion-0.10.0` (extends PR #4). Update `CHANGELOG.md`.
