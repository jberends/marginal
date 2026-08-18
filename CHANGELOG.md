# Changelog

All notable changes to Marginal are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [0.10.0] — Unreleased

### Added

- **Images**: insert an image by paste, screenshot, or drag-and-drop. An image renders inline as a
  tidy **figure card** — the picture centered in a rounded container that floats on the page (no
  fill, a whisper-thin hairline edge, and a soft shadow) with a **caption** beneath it (the alt
  text, or the filename when there's no alt).
  Click it to reveal its `![](path)` markdown source as a small dimmed line beneath the still-
  anchored card (clicking away collapses it, without the page jumping). Dragging an image **file**
  from Finder links it by absolute path.
- **Image export**: images render as real `<img>` in **PDF and HTML export** and are embedded as
  self-contained data URIs, so exports and **Copy as HTML** carry the picture with them. Exported
  PDF images are capped to about half a page tall (keeping their aspect ratio) so a single image
  no longer takes over a page.
- When a document references **externally-linked images** (ones dragged in from elsewhere on
  disk), the **Save panel** shows a checkbox to also **copy them into the document's `.assets/`
  folder**, making the document self-contained. (Pasted images always go there regardless, so the
  checkbox only appears when there's an external image to copy.)
- Inserted images get **alt text auto-filled from the filename** (accessibility and a caption).
- An image that can't be loaded now shows an **"image unavailable" placeholder** with its path,
  instead of a blank gap.
- Images **dragged in from elsewhere on disk are remembered across reopen** (per-file access is
  preserved on the same Mac), so linked images still display the next time you open the document.
- The **line-number gutter** now draws a faint vertical bar spanning the caret line's full height,
  so a tall line (like an image figure card) reads as tall at a glance.
- **Tab / Shift-Tab indent and outdent** list items by one level — two spaces, matching the list
  parser's nesting unit — instead of inserting a literal tab (which rendered ~8 columns wide and
  wasn't recognized as list nesting). Works across a multi-line selection and is undoable.
- **Tab-indented list items now nest** (one tab = one level), so a list indented with tabs — from
  the Tab key or a pasted document — renders as a proper nested list with sub-bullets and even
  spacing, instead of literal `-` lines with uneven gaps.

### Fixed

- **Saving a document with pasted images now works under the sandbox.** Pasted images buffer in a
  temporary location and, on the first save, Marginal asks once for permission to the document's
  folder (remembered afterwards) and writes the images into a sibling `<name>.assets/` folder next
  to the `.md`. If access is declined, Marginal warns rather than silently losing the images.
- New documents are proposed with a **`.md`** extension instead of `.markdown`.
- **An image on the very first line now renders** (card, image, or "unavailable" placeholder)
  instead of showing as bare `![](…)` text. The image band was reserved as space-above-the-line,
  which TextKit silently drops for the first paragraph; it's now reserved as line height (honored
  everywhere) with the caret kept a normal height.
- **The Save panel's "copy linked images" checkbox now works for a document whose only image is an
  externally-linked path** (e.g. one dragged from the Desktop). Such a document was skipped before
  the copy step ran, so ticking the box did nothing; it now copies the linked image into the
  `<name>.assets/` folder and rewrites the reference to a relative path.
- **Opening any saved document no longer hangs the app** (beachball, needing Force Quit). Reopening
  a file-backed document walked its folder's ancestors looking for a remembered image-folder grant,
  but the walk never terminated at the filesystem root and spun a CPU core at 100%. The walk now
  stops correctly at the root.

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
  literal `-` and ``` ``` ``` markers. Quoted lists indent to the quote's text, and a quoted code
  block keeps the quote bar to its left with the `>` markers hidden inside the card.
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
