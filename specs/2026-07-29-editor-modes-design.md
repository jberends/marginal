# Marginal Editor Modes: Code · Live · Preview — Design Spec

**Date:** 2026-07-29
**Status:** Approved for planning

## Summary

Marginal today has exactly one editing surface — live WYSIWYG with reveal-at-cursor — plus a
hidden `⌘⇧P` "Show Source" toggle that renders bare monospace with no highlighting and has no
menu item, no visible control, and no state indicator anywhere in the window. Editing is
consequently hard in two distinct ways: markers hide themselves and line heights shift as the
caret moves, and there is no true rendered view, because the text storage is the literal file
and therefore always shows a paragraph's hard-wrapped source lines as separate lines.

This spec replaces the binary toggle with three explicit modes — **Code**, **Live**,
**Preview** — exposed through a status-bar segmented control, a new View menu, and `⌘⌥1/2/3`.
Code mode is a real source editor (all markers visible and tinted, uniform monospace, nothing
reflows). Live mode is today's behaviour, unchanged. Preview mode is a true read-only render in
a `WKWebView` driven by the existing `MarkdownHTMLRenderer`, where soft newlines collapse into
flowing paragraphs as markdown specifies.

## Motivation

The two problems are separate and both real:

1. **Editing precision.** In Live mode, revealing and hiding markers changes font sizes, which
   changes line heights, which shifts text as the caret moves. Fine for reading, hostile for
   sustained editing. There is no mode where the source sits still.
2. **No true render.** `MarkdownStyler` maps display attributes 1:1 onto source indices — a
   load-bearing invariant (the string is never mutated, so autosave always writes exactly what
   was opened). That invariant makes soft-newline collapsing impossible in Live mode by
   construction, not by omission.

The existing `⌘⇧P` addresses neither: it is undiscoverable, and its output is unstyled.

## Design decisions and rationale

Grounded in Laws of UX and the Apple Human Interface Guidelines, as requested.

**Three modes, not two.** Live is the product's differentiator (it is the README's and the
landing page's entire pitch) so it stays the default. Code and Preview are the two escape
hatches it lacks.

**Status-bar segmented control, not a toolbar.** A toolbar would be the conventional macOS
location (Jakob's Law — Xcode, Notes, Numbers all put view switchers there) but Marginal has no
toolbar at all today: `MarkdownDocument.makeWindowControllers` builds a plain titled window. A
toolbar means ~52pt of permanent new chrome in an app whose stated value is having none. The
status bar already exists (26pt, breadcrumb left, `L · C` right), so the switch costs zero new
chrome and sits by Law of Proximity with the other document-state readouts. Precedent exists on
the Mac: BBEdit, Nova and Sublime all carry mode controls in the status bar.

**Icon + label, not icon alone.** At 26pt tall the segments are short; labels roughly double the
target width (Fitts's Law), and `text.cursor` does not self-evidently mean "markers reveal at
the caret" (recognition over recall).

**All three segments visible, not a cycling button.** Hick's Law argues for showing the options;
a single button that advances through three states makes every click a guess, and the HIG warns
against controls whose meaning changes on each press.

**`⌘⌥1/2/3`, not `⌘1/2/3`.** `⌘1`–`⌘9` are already bound to iTerm2-style "Select Tab N"
(`AppDelegate.buildMainMenu`), a shipped and documented feature. `⌘⌥` is free and Xcode already
trains it for editor-mode variants.

**Preview via WKWebView and the existing renderer, not a second text engine.** The alternative —
building a rendered `NSTextStorage` — requires a new renderer plus an index-mapping layer
between rendered position and source position, and would make Preview look different from PDF
export. Reusing `MarkdownHTMLRenderer` means one renderer and one stylesheet serve three
outputs (screen, PDF, Copy as HTML), and the soft-newline collapsing is already implemented
there: `MarkdownHTMLRenderer` joins a paragraph's lines with a space before emitting `<p>`.
WebKit is already linked and already used by `PDFExporter`.

**Preview is read-only.** A scrolled web view has no caret to defend, and bidirectional scroll
sync already returns the reader to the right region on leaving, so click-to-edit-here buys
little for real added machinery (a `WKScriptMessageHandler` plus reverse element→line mapping).
Deferred deliberately, not designed out.

## Scope

### Mode model

- `enum EditorMode { case code, live, preview }`.
- One mode per **window**, so two tabs may sit in different modes.
- Last-chosen mode persisted globally in `UserDefaults` under `editorMode`, mirroring the
  existing `editorFontPointSize` precedent. New documents open in the last-used mode.
- The file on disk is unaffected by mode. Text storage remains the literal source in Code and
  Live; Preview renders from a copy and never writes back. The never-mutate-the-string
  invariant is preserved unchanged.

### The switch

- `NSSegmentedControl` (`.selectOne`, icon + label) added to `StatusBarView`, trailing edge.
- Segments: **Code** (`chevron.left.forwardslash.chevron.right`), **Live** (`text.cursor`),
  **Preview** (`eye`).
- New **View menu** in `AppDelegate.buildMainMenu`, as a radio group with a checkmark on the
  active mode (the HIG pattern for mutually exclusive view state), carrying `⌘⌥1/2/3`. The
  menu also gains Zoom In / Zoom Out / Actual Size, which are keyboard-only today.
- `⌘⇧P` and `MarkdownTextViewShortcutDelegate.markdownTextViewToggleShowSource` retire.
- Menu state is driven through the existing `NSMenuItemValidation` conformance on
  `AppDelegate`.

### Code mode

- Uniform monospace at one size. Every marker visible; no hiding, no reveal-at-cursor, and
  **no font-size variation anywhere**, so no line ever reflows while editing. This is the
  editing-precision fix.
- Markers tinted: `DesignPalette.accent` for structural markers (`#`, `**`, `_`, `` ` ``,
  `[x]`, `>`), `DesignPalette.textFaint` for list bullets and table pipes.
- Replaces `MarkdownStyler.plainSourceAttributedString`, which is currently monospace +
  `labelColor` and nothing else. It is a second, simpler styling pass over the same
  `MarkdownDocumentModel` the Live pass already builds — no new parsing.
- Gutter shows **all** line numbers, with the caret's line emphasised. Today
  `LineNumberGutterView` draws only the caret's own number.

### Live mode

Unchanged. Same parse, same `MarkdownStyler.attributedString`, same `CursorRevealController`,
same gutter behaviour (caret's line only).

### Preview mode

- `WKWebView` shown in place of the scroll view, loaded via `loadHTMLString` from
  `MarkdownHTMLRenderer.html(fromMarkdown:)` wrapped in a shared stylesheet.
- The stylesheet currently inlined in `PDFExporter.pageHTML` is extracted to a new
  `MarkdownStylesheet` with light and dark variants. `PDFExporter` keeps the light variant
  (print is always on white paper); Preview follows the window's effective appearance and
  reloads on appearance change.
- Read-only: `isEditable` is irrelevant for a web view, but text selection stays enabled and
  copies plain rendered text.
- The gutter hides. The status bar's left slot shows word count and reading time in place of
  the breadcrumb, and the `L · C` readout hides — both are meaningless without a caret.
- The web view is created lazily on first entry to Preview and torn down when the document
  closes, so documents never visited in Preview pay no web-process cost.

### Position preservation

- `MarkdownHTMLRenderer` gains a `data-line="N"` attribute on each emitted block element,
  carrying the 1-based source line where that block starts.
- Code/Live → Preview: scroll to the block whose `data-line` is the greatest value not
  exceeding the caret's line.
- Preview → Code/Live: place the caret at the start of the first line of the topmost visible
  block, and scroll that line into view.
- The mapping is computed in Swift from the emitted anchors; only the "which block is topmost"
  query needs JavaScript evaluation in the web view.

## Architecture

Two new types, one extraction, one refactor.

**`EditorMode`** (new, `Sources/Marginal/Editor/EditorMode.swift`) — the enum plus its
`UserDefaults` persistence and its display metadata (title, SF Symbol name, keyboard tag).

**`EditorModeController`** (new, `Sources/Marginal/Editor/EditorModeController.swift`) — owns
the active mode and a single `render()` dispatch. This exists because
`DocumentViewController` is already 384 lines juggling view construction, chrome updates,
styling, delegate callbacks, PDF export, drag-and-drop and font sizing, and the branch
`isShowingSource ? applyPlainSourceRendering() : restyle(…)` is **duplicated in four places**
(`toggleShowSource`, `textDidChange`, `textViewDidChangeSelection`, `setFontSize`). Turning
that into a three-way branch in four places is how this feature rots. The controller collapses
it to one call site per event.

**`MarkdownStylesheet`** (new, `Sources/Marginal/Editor/MarkdownStylesheet.swift`) — the CSS
extracted from `PDFExporter.pageHTML`, with light/dark variants, consumed by both Preview and
`PDFExporter`.

**`MarkdownStyler.codeSourceAttributedString(for:model:font:)`** (new, replacing
`plainSourceAttributedString`) — the tinted monospace pass.

Everything else extends existing types: `StatusBarView` gains the segmented control and the
word-count display, `LineNumberGutterView` gains an all-lines drawing mode,
`MarkdownHTMLRenderer` gains line anchors, `AppDelegate` gains the View menu,
`DocumentViewController` delegates mode handling to `EditorModeController`.

The never-mutate-the-string invariant is untouched: Code mode is pure attributes over the
literal source, and Preview reads the source into a separate view that has no write path.

## Testing

Following the project's established philosophy — pure logic gets unit tests, visual behaviour
gets verified against the real running app via Accessibility scripting plus a screenshot read
back.

**Unit tests:**
- `EditorMode` persistence round-trip and default-on-first-launch.
- `EditorModeController` transitions: every ordered pair of modes, and that each event
  (text change, selection change, font-size change) renders through exactly one path.
- `MarkdownHTMLRenderer` `data-line` anchors: correct line for every block kind, and correct
  behaviour for a paragraph whose source spans several lines.
- Caret-line → block and topmost-block → caret-line mapping math, including the boundaries
  (before the first block, after the last, inside a multi-line paragraph).
- `MarkdownStyler.codeSourceAttributedString`: marker ranges get the accent colour, list
  bullets get the faint colour, and **every** character in the output carries the same font
  size (the no-reflow guarantee, asserted directly).
- Word count and reading time.
- `MarkdownStylesheet` light/dark variants both emit valid non-empty CSS, and `PDFExporter`
  still emits the light variant.

**Visual verification against the running app:** the segmented control's appearance and hit
targets at both appearances, the all-lines gutter, Preview's rendering including the collapsed
paragraph, and scroll-position preservation in both directions. `WKWebView` pixel output is not
meaningfully unit-testable; the tests target the emitted HTML and the mapping arithmetic, and
the rendered result is confirmed by screenshot.

## Out of scope

- Click-in-Preview-to-edit-at-that-spot (needs a `WKScriptMessageHandler` and reverse
  element→line mapping; bidirectional scroll sync covers most of the need).
- Split view / side-by-side source and preview.
- Per-document mode persistence written to disk.
- Printing directly from Preview (File ▸ Export as PDF already covers it).
- Per-language syntax highlighting in Code mode beyond markdown's own markers.

## Self-Review

- **Placeholder scan:** none. Every decision resolves to a named type, file, or existing call
  site.
- **Internal consistency:** the mode model, the switch, and the three rendering paths agree.
  `EditorModeController` is the single dispatch point named consistently throughout. The
  never-mutate-the-string invariant is stated once and honoured by both new rendering paths.
- **Scope check:** appropriately sized for one plan — comparable to Phase 2's shape, with one
  extraction, two new types, and edits to six existing files.
- **Ambiguity check:** three points were ambiguous on first pass and are now explicit — mode
  is per-window with a global persisted default (not per-document); `PDFExporter` keeps the
  light stylesheet variant rather than following appearance; and the caret→block mapping uses
  "greatest `data-line` not exceeding the caret line" rather than "nearest", which is
  well-defined inside a multi-line paragraph.
