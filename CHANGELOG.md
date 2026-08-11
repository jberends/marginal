# Changelog

All notable changes to Marginal are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [0.8.0] — 2026-08-11

### Added

- **Notion-style block editor**: Live mode is now a true block editor over a
  `BlockDocument` model instead of a single styled text view. Each block (heading,
  paragraph, list item, quote, code block, divider, table) is its own view with
  Notion's own vertical rhythm, heading scale, quote bar, list gutters, and rounded
  code cards.
- **Code mode**: a synced raw-markdown view. Switching Live → Code serialises the
  document and puts the caret on the focused block's line; switching back parses the
  source and focuses the block under the caret. Undo stacks reset on each switch.
- **In-place table editing**: tables render as an editable grid. Tab/Shift-Tab walk the
  cells, Enter moves down a column, and Tab past the last cell appends a row.
- **Whole-block selection**: Escape, or Shift+Up/Down past a block's own bounds,
  selects entire blocks. ⌫ deletes them and ⌘C copies them as canonical markdown.
- **Style shortcuts**: ⌘B / ⌘I / ⌘U / ⌘⇧S toggle bold, italic, underline and
  strikethrough over the selection, alongside live `**bold**`-as-you-type autoformat.
- **Document-level undo** across structural edits, coalesced per typing burst.

### Changed

- Markdown is now canonicalised on save: the document is serialised from the block
  model, so `1) x` is written back as `1. x`.
- The old hidden-marker rendering path (`MarkdownStyler`, `MarkdownLayoutManager`,
  `CursorRevealController`) has been removed.

### Fixed

- A table cell containing a literal `|` no longer drops the rest of the row when the
  file is re-read.
- Identifiers like `snake_case_word`, `__init__` and URLs containing underscores are no
  longer rewritten to `*`-emphasis on save. Underscore emphasis now requires a word
  boundary, matching CommonMark.
- Caret positions are counted in characters rather than UTF-16 units, so blocks
  containing emoji no longer split or autoformat one character off.

## [0.3.0] — 2026-07-29

### Added

- **Clickable task checkboxes**: click a drawn checkbox to toggle `[ ]` ↔ `[x]` in the
  source — undoable, and the caret stays where it was.
- **List continuation**: Return inside a bulleted, ordered, or task item starts the
  next line with the right marker (`- `, the next number, `- [ ] `). Return on an
  empty item outdents one level; on an empty top-level item it leaves the list.
- **Reveal-at-cursor for task markers**: a task item whose line contains the cursor
  shows its literal `- [ ]` / `- [x]` source, like every other marker.

### Fixed

- Horizontal rules are clickable again: the hidden `---` line kept a near-zero
  height, so the cursor could never reach it to reveal the source.

### Changed

- Signed with the KE-works BV team; display name "Marginal - Markdown Editor".

## [0.2.0] — 2026-07-29

### Added

- **Export as PDF** (File → Export as PDF…, ⇧⌘E): renders the document through the
  HTML renderer into a paginated A4 PDF, styled on the design-system tokens.
- **Check for Updates** (Marginal → Check for Updates…): compares the running version
  against the newest GitHub release — and can now download and install the update
  itself. The app quits, a small script swaps in the new version, and it relaunches.
- **Line-number gutter**: a sidebar a tad lighter than the paper shows the caret's
  line number, very faintly, aligned with the caret's own line — and nothing at all
  when the cursor isn't in the text.
- **Status bar**: the markdown context at the cursor as a breadcrumb ("h1 › bold")
  plus the position ("L 24 · C 13").

### Changed

- The whole app now follows the design-system token sheet: warm paper page, violet
  accent (inline code, links, checked task boxes), warm syntax-highlight palette,
  hairline table grids, violet-tinted selection.
- Bold renders at semibold (600) — the product's heaviest weight; 700 no longer
  appears anywhere.
- Base type size is 16px (headings scale 1.25 / 1.5 / 1.875 from it).
- App icon updated to the icon-3 mark.

### Fixed

- Swift 6 strict-concurrency crashes-in-waiting: main-actor isolation for the app
  delegate, document storage, and the PDF print callback (which fires on a
  background thread).

## [0.1.0] — 2026-07-27

### Added

- First tagged release: true-WYSIWYG markdown editing with reveal-at-cursor syntax,
  Notion-grade rendering (tables, code cards, task lists, auto-renumbered ordered
  lists, blockquotes, emoji shortcodes), plain `.md` files, native AppKit app with
  macOS tabs (⌘1–⌘9), copy as Markdown or HTML, light and dark mode.

[0.3.0]: https://github.com/jberends/marginal/releases/tag/v0.3.0
[0.2.0]: https://github.com/jberends/marginal/releases/tag/v0.2.0
[0.1.0]: https://github.com/jberends/marginal/releases/tag/v0.1.0
