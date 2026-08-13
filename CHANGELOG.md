# Changelog

All notable changes to Marginal are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [0.9.0] — 2026-08-13

### Added

- **Autolinks**: bare URLs and email addresses written straight into the prose become real
  links, without needing `[text](url)` syntax. Trailing punctuation follows GFM's rules, so
  `https://example.com.` links without the full stop, `(https://example.com/path).` drops the
  wrapping paren *and* the stop, and a URL whose own parentheses balance —
  `…/Markdown_(markup_language)` — keeps them. Emails link as `mailto:`.
- **⌘-click opens a link** in the default browser, with a pointing-hand cursor over links. A
  plain click still just moves the caret, so a link stays editable text.
- **In-document anchor links** (`[Heading](#heading)`, as a hand-written table of contents
  uses) scroll to the matching heading, resolved with GitHub's slug rules. Relative paths
  resolve against the document's own folder.
- **Typographic substitution**: `"` `'` `...` `--` and `---` display as `“ ” ‘ ’ … – —`.
- **HTML entity decoding**: `&copy;`, `&amp;`, `&#169;` and `&#x00A9;` display as the character
  they stand for — named, decimal and hexadecimal.
  Both substitutions are display-only: the file on disk keeps exactly what you typed, and
  neither applies inside code, on a `---` rule line, in a table's alignment row, or in the
  hidden parts of a link.
- **Word and character counts** in the status bar. Click the `L · C` indicator to swap it for
  counts and click again to swap back. It shows where you are, not just how big the file is —
  `Chars 23 / 26374 · Words 4 / 3995` — and reports the selection when text is selected.
- **File ▸ Open Recent**, holding the last ten documents.
- **`.txt` files open in Marginal**, from the Dock, from Finder and by dropping one on the
  window — plain text is now a declared document type, and a dropped `.txt` opens in its own
  tab exactly like a `.md`.
- **Leaving without saving**: hold ⌘Q or ⌘W, or press it again while the save sheet is up, to
  close or quit and **discard** the unsaved changes.

### Changed

- **Typography.** The editor sets in Avenir Next — the typeface behind Bear's feel, a humanist
  sans whose open letterforms read far warmer at length than the system UI font, which is drawn
  for interface chrome rather than prose. Body text sets at a 1.32 line height and the blank
  lines markdown puts between blocks render at half height. (The usual 1.5–1.6 advice assumes
  HTML, where a blank line between paragraphs does not exist in the output; here the document
  *is* the markdown, so that multiple inflated the text and every gap at once.)
- Headings carry more air above than below — 1.1/0.85/0.6em above, 0.45em below — so a heading
  binds to the text it introduces instead of floating between two blocks.
- Links render in Marginal's purple accent, underlined with a hairline in a lighter tint of it,
  the way Notion does.
- Markdown is unchanged on disk unless you edit it: a URL containing underscores
  (`…/some_path/file_name`) is no longer read as italic emphasis and rewritten on save.

### Fixed

- **Nested blockquotes** render as nested, one bar per level with the content indented.
- **Lists and fenced code blocks inside a blockquote** render properly instead of showing their
  literal `-` and ``` ``` ``` markers, with quoted lists indented to the quote's text and the
  `>` markers hidden inside quoted code.
- **Strikethrough inside bold** (`**~~deleted~~**`) renders as both. Markdown written inside
  backticks stays literal.
- Selecting text inside a code block shows the selection.
- Substituted characters (`…`, `–`, `—`), list numbers and emoji sit on the text baseline
  instead of hanging below it.
- Blocks no longer collapse on top of one another, and a document opens with its first line —
  and the caret — at the top of the window rather than the bottom.

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
