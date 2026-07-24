# Marginal Phase 2: Formatting Engine Completion — Design Spec

**Date:** 2026-07-24
**Status:** Approved for planning

## Summary

Phase 1 shipped the foundation and core WYSIWYG engine: bold, italic, strikethrough, underline, headers, lists, and links, plus font sizing, Show Source, and raw-markdown copy. Phase 2 finishes the remaining "plain text" formatting the spec calls for (inline code, fenced code blocks, blockquotes, horizontal rules), and fixes four real gaps found through direct use of the running app: links never hid their `[]()` syntax, list markers never became visual bullets, ⌘+ didn't alias to font-increase, and cursor-reveal ranges let adjacent spans both reveal at a shared boundary.

## Scope

**New formatting (extends `MarkdownParser`/`MarkdownStyler`/`CursorRevealController`, same pattern as Phase 1):**
- Inline code (`` `code` ``) — monospace font + subtle background tint, no delimiter-hide/reveal (always shown plainly, matching how bold/italic delimiters *do* hide — inline code's backticks *do* hide/reveal like other inline styles, see Task breakdown).
- Fenced code blocks — monospace block with background, plus basic heuristic syntax highlighting (string literals, line comments, numbers) via generic language-agnostic regex — not a per-language tokenizer.
- Blockquotes — single-level only (matches Phase 1's list-nesting precedent), left border bar + muted text.
- Horizontal rules — a real drawn divider line.

**Fixes (real gaps found via live GUI testing, not new formatting):**
- Links never hide their `[`/`]`/`(`/`)`/URL syntax — extend `CursorRevealController` + `MarkdownStyler` to hide/reveal link delimiters the same way headers and inline styles already do.
- List markers render as literal `-`/`*`/`+` — substitute a real bullet glyph for unordered markers without changing the underlying character, via `NSGlyphInfo`.
- ⌘+ (i.e. ⌘⇧=) doesn't register as font-increase alongside ⌘= — `charactersIgnoringModifiers` strips Option/Command/Control but honors Shift, so ⌘+ produces `"+"`, which matches no `keyDown` case today.
- `CursorRevealController`'s reveal check uses `>=`/`<=` on both span boundaries, so a cursor sitting exactly between two touching spans reveals both.

**Out of scope (future phases):** tables, images, the BYOK AI feature, HIG visual polish (dark mode/materials/focus mode/font family switching), export, full menu bar refinement beyond what Phase 1.5's hotfix added, App Store packaging.

## Architecture

Extends Phase 1's exact pattern (pure `MarkdownParser` functions producing spans, `MarkdownStyler` turning spans into `NSAttributedString` attributes, `CursorRevealController` deciding what's revealed at the cursor). Three additions, each de-risked with a compiled spike before this plan was written:

1. **Multi-line span parsing.** Fenced code blocks span many lines (unlike Phase 1's single-line headers/list items), so `MarkdownParser.parseFencedCodeBlocks` uses a line-scanning state machine that tracks "inside fence" state between an opening and closing ` ``` ` line.

2. **Glyph substitution without string mutation.** List bullets use `NSGlyphInfo(glyphName: "bullet", for:baseString:)` set as the `.glyphInfo` attribute on the marker character's range. Verified by spike: the attributed string's `.string` stays literally `"-"`/`"*"`/`"+"`, while the glyph actually drawn is the font's bullet glyph — a pure-attribute technique, no new invariant risk.

3. **Paragraph-level decoration via a custom `NSLayoutManager`.** Both the blockquote left bar and the horizontal rule line are drawn by a `MarkdownLayoutManager: NSLayoutManager` subclass overriding `drawBackground(forGlyphRange:at:)`, keyed off custom `NSAttributedString.Key`s (`.marginalBlockquoteMarker`, `.marginalHorizontalRuleMarker`) that `MarkdownStyler` applies to the relevant paragraph ranges. Verified by spike: `NSTextAttachment` was the original hypothesis for the horizontal rule, but it inserts a literal U+FFFC character into the string — a real mutation, ruled out. The custom-layout-manager draw technique was verified instead to correctly span multi-line wrapped paragraphs (needed for blockquotes) and works equally well for the single-line horizontal rule.

Everything continues to satisfy the core invariant: the underlying string is never mutated, only display attributes/decorations change.

## Testing

Same philosophy as Phase 1: every new `MarkdownParser` function and the highlighting-token function get pure unit tests. `MarkdownStyler`/`CursorRevealController` extensions get unit tests the same way Phase 1's did. The custom `NSLayoutManager` drawing and the `NSGlyphInfo` glyph substitution are visual — verified via a real running app (build, launch, Accessibility-scripted interaction, and a screenshot read back for visual confirmation), not deferred to "a human" as Phase 1 sometimes did, since that capability is now confirmed to work in this environment.

## Self-Review

- **Placeholder scan:** none — every decision above resolves to a concrete technique, verified by spike where novel.
- **Internal consistency:** the three architectural additions (multi-line parsing, glyph substitution, layout-manager decoration) don't conflict with each other or with Phase 1's existing pure-attribute styling for bold/italic/strikethrough/underline/links/headers.
- **Scope check:** appropriately sized for one plan — comparable in shape to Phase 1's 11 tasks.
