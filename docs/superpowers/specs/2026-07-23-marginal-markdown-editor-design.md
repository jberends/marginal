# Marginal — Design Spec

**Date:** 2026-07-23
**Status:** Approved for planning

## Summary

Marginal is a native macOS markdown editor and beautiful viewer. It opens a single `.md` file at a time, renders markdown formatting live as you type (WYSIWYG, in the style of iA Writer/Bear/Notion — not raw-source-always-visible like TextMate), and registers as the default handler for markdown files. It is free, open source, and aims for App Store distribution. It does exactly one job — editing a markdown file — and does not manage projects, folders, or note collections.

## Goals

- Be a genuinely fast, lightweight, native alternative to heavy editors (TextMate, Electron-based tools) for editing markdown files.
- Feel beautiful by default, following Apple's Human Interface Guidelines closely.
- Be a strong candidate for macOS default-app registration for `.md`/`.markdown` files.
- Ship on the Mac App Store, free, open source (Apache 2.0), with donation support via the project website.
- Include a small, well-scoped optional AI writing-assistant feature.

## Non-goals (explicitly out of scope)

- No project, folder, or multi-file management — ever, by design. This is a single-document editor.
- No sidebar, no file tree, no notes database.
- No Spotlight/Quick Look extension (candidate future idea, not v1).
- No bundled/hosted AI backend — AI features are BYOK (bring your own API key) only.
- No multi-cursor editing, no plugin/extension system.
- No iOS/iPadOS/Catalyst version — macOS only.

## Prior art / competitive landscape

This category is more crowded than it first appears: MarkEdit, Markdown Mate, MacDown, Marked 3, Bear, iA Writer, Ulysses, Typora, and Markwell (a WYSIWYG editor with a raw-source toggle, aimed at AI-agent workflows) all occupy adjacent space. Marginal's differentiation is the combination of: seamless animated reveal-on-cursor WYSIWYG editing, a live editable table grid, a deliberately tiny and well-scoped BYOK AI feature, and unusually close adherence to Apple's current HIG (materials, dark mode, typography) for a "default app" feel. Before submission, a proper trademark/App Store name search should be done (the collision checks done during design were directional web searches, not a legal clearance).

## Architecture

- **Language/framework:** Swift, native AppKit. No web view or Electron-style shell anywhere in the stack.
- **Document model:** One `NSDocument` subclass, one primary window/tab controller. Autosave, the Versions browser, and Open Recent are inherited from `NSDocument` for free.
- **Editing surface:** A custom `TextKit 2` layer built on `NSTextView`, responsible for:
  - Parsing markdown incrementally as the user types.
  - Applying inline styling (bold/italic font traits, header point sizes, link styling, strikethrough/underline).
  - Hiding markdown delimiter characters when the cursor is outside their span, and revealing them as real, editable characters with animated reflow when the cursor enters the span.
  - Rendering fenced code blocks with monospace font + basic syntax highlighting.
  - Rendering images inline from local relative paths or remote URLs.
- **Tables:** A dedicated table view/attachment embedded in the text flow, rendered as a live editable grid rather than raw pipe syntax. Tab/Shift-Tab navigate and grow cells (standard spreadsheet/document convention); Tab outside a table performs normal text indentation. The underlying markdown pipe-table syntax is generated/parsed transparently.
- **Minimum OS:** macOS 14 (Sonoma) and macOS 15 (Sequoia). Free to use current AppKit/TextKit APIs without back-compat shims.
- **System integration:**
  - Supports macOS's built-in system Writing Tools (on-device proofread/rewrite/summarize) automatically, since it's a standard `NSTextView`-based editor — no additional implementation required.
  - Registers `.md`/`.markdown` as supported/editable document types via `CFBundleDocumentTypes`. Users set Marginal as their default handler themselves via Finder's "Get Info ▸ Open With ▸ Change All" — macOS provides no API for an app to set itself as default programmatically.

## De-risking plan

Because the reveal-on-cursor animated WYSIWYG behavior is the riskiest and most novel part of the implementation, the first implementation milestone should be a small throwaway proof-of-concept: a single `NSTextView` subclass handling just bold text and one heading level, with cursor-triggered reveal and reflow. This validates feel and technical approach before any further app scaffolding.

## Editing behavior details

- **Formatting support:** bold, italic, strikethrough, underline, headers (all levels), ordered/unordered lists, links, inline code, fenced code blocks (with basic syntax highlighting), images, tables, blockquotes, horizontal rules.
- **Clipboard behavior:**
  - `⌘C` copies rendered rich text (formatted paste into Mail/Word/etc.).
  - `⌘⌥C` copies the raw markdown source of the current selection.
- **Raw source escape hatch:** `View ▸ Show Source` toggles the entire window between rendered WYSIWYG and plain raw markdown text, and back.
- **Font:** system font (SF Pro) by default via macOS text styles; switchable to a serif or monospace family in Settings. `⌘+`/`⌘-` adjusts text size.
- **Undo/redo, spellcheck, dictation, Services menu, accessibility (VoiceOver):** inherited from standard AppKit text editing — no custom work required, but must be verified to still function correctly with the custom TextKit rendering layer.

## Visual design

Follows Apple's Human Interface Guidelines (Typography, Dark Mode, Layout, Materials) closely:

- **Light mode:** editorial/minimalist — generous whitespace and margins, near-invisible chrome (no visible toolbar by default), optional focus mode that dims all but the current paragraph.
- **Dark mode:** a deliberately crisper, higher-contrast treatment rather than a simple color inversion — true dark backgrounds using semantic/dynamic `NSColor`, so it adapts correctly to system appearance and accent color changes.
- **Materials:** subtle `NSVisualEffectView` vibrancy for window chrome, used sparingly.
- **Layout:** respects HIG guidance on window minimum size and content margins; no split-view chrome since the app is intentionally single-pane.

## AI feature (BYOK)

- User supplies their own API key (OpenAI, Anthropic, or similar) in Settings. The feature is inactive/hidden until a key is set. No backend is bundled or hosted by the project — no ongoing cost, no infrastructure.
- A single lightweight "AI" menu with a small, fixed set of actions:
  - **Selection actions** (act on the current selection): Improve writing, Fix grammar & spelling, Make more concise, Roast this paragraph (funny/critical tone). Result either replaces the selection or is shown as an accept/reject diff.
  - **Whole-document critique**: one action opens a side panel with critique comments (tone configurable between earnest and funny/harsh); it does not modify the document.
- This is intentionally separate from and complementary to the OS's built-in Writing Tools, which any `NSTextView`-based app gets automatically.

## File handling & macOS integration

- Standard `NSDocument`-based app: File ▸ New/Open, native macOS tabs (`⌘T`) and multiple windows, both supported simultaneously.
- Autosave, Versions browser, Open Recent — all provided by `NSDocument`, no custom implementation.
- `File ▸ Export As…` supports basic HTML and PDF export in v1.

## Distribution, licensing, monetization

- **Distribution:** Mac App Store, sandboxed.
- **Pricing:** Free. No in-app purchases, no paywalled features.
- **License:** Apache License 2.0. Repository is public and open source.
- **Donations:** handled externally via the project website (e.g., GitHub Sponsors or Ko-fi style), not via in-app purchase. Website domain to be finalized during launch prep (marginal.io and marginal.app were found to be already in use/registered by unrelated parties during design; a workaround domain such as marginal.online or getmarginal.com is expected).

## Naming

**Marginal.** Chosen after a structured elimination exercise across 25 candidate names, filtered for collision risk via web search (directional, not a legal trademark search) and narrowed by direct user rating. Two other finalists (Markwell, Markly) were dropped due to existing same-space or same-platform products sharing the name.

## Testing considerations

- Given the custom TextKit rendering layer is the highest-risk component, unit/snapshot tests should cover: markdown parsing correctness, cursor-triggered reveal/hide of delimiters, and round-trip fidelity (opening a `.md` file, editing, saving, and confirming the on-disk markdown is unchanged for untouched content).
- Table grid editing should be tested for cell navigation, row/column growth, and correct pipe-table serialization.
- AI feature tests should mock the BYOK API client; no real API calls in automated tests.
