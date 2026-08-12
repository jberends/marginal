# Changelog

All notable changes to Marginal are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org).

## [0.9.0] — unreleased

### Added

- **Autolinks**: bare URLs and email addresses written straight into the prose become real
  links, without needing `[text](url)` syntax. Trailing punctuation follows GFM's rules, so
  `https://example.com.` links without the full stop, `(https://example.com/path).` drops
  the wrapping paren *and* the stop, and a URL whose own parentheses balance —
  `…/Markdown_(markup_language)` — keeps them. Emails link as `mailto:`.
- **⌘-click opens a link** in the default browser. A plain click still just moves the
  caret, so a link remains editable text.
- **Typographic substitution**: `"` `'` `...` `--` and `---` display as `“ ” ‘ ’ … – —`.
- **HTML entity decoding**: `&copy;`, `&amp;`, `&#169;` and `&#x00A9;` all display as the
  character they stand for — named, decimal and hexadecimal.

  Both substitutions are display-only: the file on disk keeps exactly what you typed, and
  neither applies inside code blocks, inline code, or on a `---` horizontal-rule line.

### Changed

- Links keep their purple accent colour but are underlined with a hairline in a lighter
  tint of it, the way Notion does — a quiet affordance instead of a heavily ruled line.
- Headings carry Notion's vertical rhythm — more air above than below, scaled by level, so a
  heading reads as introducing the text beneath it.
- A URL containing underscores (`…/some_path/file_name`) is no longer mis-read as italic
  emphasis and no longer has its underscores hidden.

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
