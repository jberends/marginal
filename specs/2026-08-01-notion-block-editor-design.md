# Notion-style block editor over markdown storage — design

Date: 2026-08-01 · Branch: `notion-block-editor` · Status: approved for planning

## Vision

Marginal becomes a true **block editor** — Notion's look, feel, and editing experience — with
plain markdown as the storage format ("an underground of markdown"), plus a synced **Code
mode**: a raw-markdown source view in the WordPerfect reveal-codes tradition, switchable at
will. This replaces the previous architecture (one NSTextView rendering the literal source
with hidden markers and kern-positioned tables), which could not deliver block-editor UX and
whose table geometry collapsed under its own complexity — see
`/tmp/marginal-notion-pivot-handoff.md` for the full post-mortem.

Rendering quality bar: the measured token sheet in `specs/notion-design-tokens.md`.

## Scope

**In (v1):**
- Live mode: block editor re-platforming the existing feature set — paragraphs, headings 1–6,
  bulleted/ordered/task lists (nested), blockquotes, fenced code with the existing
  highlighter, pipe tables, dividers, links, inline styles (bold/italic/strike/underline/
  inline code), emoji `:shortcodes:`.
- Block Enter/Backspace semantics, markdown shorthand conversion, and live inline
  autoformatting — per the observed behavior inventory below.
- In-place table editing (per-cell views, Tab/Enter navigation).
- Code mode: full-document raw markdown editor, two-way switch in the status bar, synced by
  construction.
- Selection: character-granular inside a block; **whole-block escalation** across boundaries.

**Out (explicitly, per product decision):**
- Slash menu, drag handles / hover chrome / `+` button.
- Preview mode (dropped; PDF export and Copy as HTML remain as commands).
- New block types (callouts, toggles, images).
- Cross-block *character* selection (roadmap; see Selection).
- Cross-mode undo continuity.

## Architecture decision

**One editable view per block over a shared block model** (chosen over: (B) a single
NSTextView rendering generated display text — a better-disguised version of the abandoned
approach, with NSTextTable fragility; and (C) WKWebView + ProseMirror — fastest to Notion UX
but forfeits the native-app identity).

The trade-off accepted: per-block views cannot natively render Notion's modern cross-block
character selection (verified live, 2026-08-01: Notion selects character-granularly across
blocks). v1 ships the coherent older-Notion behavior — selection escalates to whole blocks at
a boundary — and cross-block character selection is a roadmap milestone (design sketch: a
logical selection in the model; native selection in the focused view; painted highlights in
other views; copy/delete routed through the selection controller).

## Components

```
MarkdownBlockParser ──▶ BlockDocument ◀── edits from BlockEditController
        ▲                    │ ▲                    ▲
   (md string)               │ └── serialize ──▶ MarkdownSerializer ──▶ canonical md
                             ▼                          (save, Code mode, exports)
                     BlockEditorViewController
                     (stack of per-block views)
```

### BlockDocument (model — pure Swift, no AppKit)

- Ordered array of `Block`s; each has a stable `UUID` identity.
- Nesting is a flat `indentLevel` on list items (Notion's own model), not a tree.
- Kinds: `paragraph(InlineText)`, `heading(level, InlineText)`,
  `listItem(style: bullet|ordered|task(done:), indent, InlineText)`, `quote(InlineText)`,
  `codeBlock(language, String)`, `table(alignments, header: [InlineText], rows: [[InlineText]])`,
  `divider`.
- `InlineText`: runs of text with style flags (bold/italic/strikethrough/underline/code),
  link URL, emoji. **No delimiters exist in the model.**
- All mutations go through typed operations (split, merge, convert, indent, outdent, insert,
  delete, table cell/row ops) — the unit of undo and of testing.

### MarkdownBlockParser / MarkdownSerializer

- Parser: markdown → `[Block]`, reusing the proven span logic inside `MarkdownParser`.
  **Never fails, never drops content**: unrecognized constructs become paragraphs holding the
  literal text and serialize back verbatim.
- Serializer: `[Block]` → **canonical** markdown (decision: normalize freely). One
  deterministic style: `-` bullets, `1.` sequential numbering, `**bold**`, `*italic*`, padded
  pipe tables, ``` fences, `---` dividers, blank line between blocks. Emits a block→line-range
  map for caret mapping.
- Round-trip law (tested): `serialize(parse(x))` is idempotent after one pass; and
  `parse(serialize(doc)) == doc` for every representable document.

### BlockEditorViewController (Live mode)

- NSScrollView + vertical stack of per-block views, width-tracking; block identity drives
  incremental view updates (insert/remove/refresh only affected views). Lazy view recycling
  is a later optimization, not v1.
- Text-ish blocks (`paragraph`, `heading`, `quote`, `listItem`): one `BlockTextView`
  (NSTextView subclass) rendering `InlineText` as attributed text with the token-sheet fonts.
  List marker (bullet shape / number / checkbox) drawn in a fixed leading gutter per indent
  level; quote bar drawn as chrome. Smart quotes/dashes/text replacement disabled; undo
  routed to the document (see Undo).
- `codeBlock`: one monospaced BlockTextView on the rounded card (85%, radius 10, 1.375em
  inset), existing `parseCodeHighlightTokens` reused.
- `table`: `BlockTableView` — a grid of per-cell BlockTextViews with Notion-measured chrome
  (hairline grid, tinted medium-weight header row, 0.5625em cell padding). Columns share the
  available width like a browser auto-layout (proportional with a minimum); cells wrap
  naturally; rows grow. In-place editing is native by construction.
- `divider`: a 1px hairline view.
- Focus/boundary choreography: arrow-up at a block's first line / arrow-down at its last line
  move focus to the adjacent block preserving the caret x-position; click focuses the block
  under the mouse.

### BlockEditController (edit semantics)

Receives boundary/shorthand events from block views, applies operations to the model,
patches views, moves focus. **The rules are the observed behavior inventory below — captured
live from Notion (2026-08-01) by driving its real editor, not from memory.** Two entries
corrected wrong assumptions (9, 10 differ per block type; 11 reflects modern Notion).

| # | Interaction | Behavior (v1 contract) |
|---|---|---|
| 1 | Enter mid-paragraph | Split into two blocks of the same kind; caret at start of second |
| 2 | Backspace at paragraph start | Merge into previous block; caret at the join. If previous is a divider/table/code block: select it instead of merging |
| 3 | `# `…`###### `, `- `/`* `, `1. `, `> `, `[] `, ` ``` `, `---` at block start | Convert block type; marker consumed |
| 4 | Enter at end of — or inside — a heading | The block after the split is a paragraph, never another heading (text before the caret stays a heading) |
| 5 | Enter on a list item with content | New item, same style and indent |
| 6 | Tab / Shift-Tab on a list item | Indent under previous item / outdent (max one deeper than previous item) |
| 7 | Enter on an empty list item | Outdent one level; at top level, convert to paragraph (matches existing `ListContinuation` rules, which transfer) |
| 8 | Completed `**…**`, `*…*`, `` `…` ``, `~~…~~` while typing | Convert live to styled text, delimiters consumed. ⌘B/⌘I/⌘U/⌘⇧S toggle styles on the selection |
| 9 | Backspace at heading start | Merge into previous block (content adopts the previous block's type) |
| 10 | Backspace at list-item start | Convert to paragraph **in place** (no merge) |
| 11 | Selection crossing a block boundary | Escalate to whole-block selection (highlight overlays); Delete/Copy act on whole blocks; Copy puts canonical markdown on the pasteboard. (Modern Notion does character-granular cross-block selection — deliberate v1 divergence, on the roadmap) |
| 12 | Tab in a table cell | Next cell (wraps to next row; on the last cell, appends a row) |
| 13 | Enter in a table cell | Down one row, same column |

### Undo

One undo stack on the document model: each user gesture maps to an operation (or coalesced
typing run) with inverse. Registered with the window's NSUndoManager so ⌘Z works regardless
of which block view has focus. Typing coalesces per block until focus moves or a structural
operation occurs.

### Code mode and sync

- Status-bar **Live / Code** switch (two-way; the abandoned branch's three-way switch UI is
  the reference, minus Preview).
- Code mode: one plain monospaced NSTextView over the full canonical serialization — line
  numbers from the existing gutter, smart substitutions off.
- Switch Live→Code: serialize; place caret at the focused block's first source line (from the
  serializer's line map). Switch Code→Live: parse; focus the block containing the caret's
  line. No incremental reconciliation exists or is needed — both modes are faces of one
  document, converted whole.
- Undo history resets on mode switch (v1 simplification).

### File I/O

- Open: read → parse → BlockDocument. Save/autosave: serialize canonical markdown, whichever
  mode is active. Because normalization is free (product decision), opening + saving a file
  may reformat markdown *syntax*; it can never lose content (parser safety rule).
- Exports unchanged: PDF and Copy as HTML consume the canonical serialization via
  `MarkdownHTMLRenderer` / `MarkdownStylesheet`.

## Error handling

- Parser: total function; garbage in → literal paragraphs out.
- Serializer: total function over the model; no representable document fails to serialize.
- Mode switch: cannot fail (both directions are total). Malformed table rows (ragged pipes)
  parse to a table padded with empty cells.

## Testing

- **Model & converters (the bulk):** pure-Swift unit tests — round-trip laws, every edit
  operation, every behavior-inventory row as a controller-level test ("Backspace at offset 0
  of block 3 → expect blocks X, Y, caret Z"). No UI required.
- **Visual:** harness v2 renders the block stack offscreen to PNG (same proven
  pattern as `VisualRenderHarnessTests`), checked against the Notion token sheet.
- **Interaction smoke tests:** first-responder hops at block boundaries via XCTest sending
  key events to the real views.
- Re-test the outstanding .md drag-and-drop regression on the new view hierarchy.

## What carries over from main

`MarkdownParser` span logic, `parseCodeHighlightTokens`, `GemojiTable`, `DesignPalette` +
token sheet, `ListContinuation` rules (as model operations), `MarkdownHTMLRenderer` +
`MarkdownStylesheet`, native window tabs, the offscreen-PNG verification workflow. Retired:
`MarkdownStyler`, `MarkdownLayoutManager`, `CursorRevealController` (their Notion-parity
knowledge lives on in the token sheet and this spec).

## Risks / open questions

- **Focus choreography** is the architecture's hard part (boundary key events, caret-x
  preservation, block selection state machine) — spike it first in the plan.
- **Performance** with hundreds of blocks: acceptable for realistic markdown documents;
  view recycling is the known lever if not.
- **Typing-time autoformat** (row 8) needs careful cursor bookkeeping in BlockTextView;
  scope it as its own plan task.

## Behavior-inventory provenance

Captured live from Notion's editor (app.notion.com, 2026-08-01) by driving real keystrokes
via Chrome DevTools Protocol against the `markdown-editor-feature-test` page and inspecting
the block DOM after each step; all scratch edits were undone. Session captures (screenshots,
DOM diffs) in `~/Library/Caches/superpowers/browser/2026-07-30/session-1785390091158/`.
