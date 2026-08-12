# Block editor (PR #2): post-mortem, salvage, and the 0.3.0 visual plan

**Date:** 2026-08-12
**Status:** PR #2 (`notion-block-editor`) is **scrapped**. Do not merge it.
**Decision:** keep 0.3.0's engine; fix 0.3.0's *appearance* instead of replacing its architecture.

---

## 1. TL;DR

PR #2 replaced the hidden-marker single-`NSTextView` renderer with a Notion-style block
editor (16 tasks, ~4,000 lines, `Sources/Marginal/Blocks/` + `Sources/Marginal/BlockEditor/`).
It ends at 224 passing tests and a visual harness PNG that looks correct — and it is still
**less usable than 0.3.0**. The user's verdict after running it: *"0.3.0 is way better, only
looking worse."*

The original complaint was **visual** ("styling is not so great"). The response was
**architectural**. That mismatch is the root cause of everything below.

---

## 2. Evidence: what was actually wrong in the shipped 0.8.0 build

Found by *using* the app, not by reading it. None of these were caught by 224 tests or by the
offscreen render harness.

| Defect | Why the tests missed it |
|---|---|
| **Typing `# ` gives body-sized text.** The block's `kind` becomes `.heading` in the model, but the text view keeps its previous typing attributes, so the characters you type render at paragraph size. | Tests assert `document.blocks[0].kind == .heading(1)` — which is *true*. The harness renders a freshly **parsed** document, where the heading path works. Nothing exercised the **typing** path's rendering. |
| **⌘A could not select the document.** It reached only the focused block's text view. | No test for "select all, then delete" — the most basic destructive edit there is. |
| **Caret/content pinned to the bottom of the window** on an empty or short document. `NSScrollView` puts a too-short document view at the origin, which in AppKit's default (non-flipped) space is the *bottom*. | Layout geometry was never asserted; the harness sized its own canvas to the content, so it never hit the short-document case. |
| **Line-number gutter disappeared** in Live (default) mode — it was explicitly `isHidden` there. | Deliberate-looking code, no test, no one looked at the window. |
| Blocks collapsed to zero height and painted on top of each other (fixed mid-stream). | `NSTextView` reports no intrinsic height; only the PNG revealed it. |

The last three were fixed (commit `bff7ec6`); the **heading-typing bug is still open** and is on its
own a reason not to ship this branch.

---

## 3. Takeaways

1. **Match the fix to the complaint.** A styling problem justifies a styling change. Rewriting
   the rendering engine to change fonts and spacing multiplied the risk surface by ~100x for no
   visual gain that the old engine couldn't have delivered.
2. **A render harness is not usage.** It proves pixels *can* be produced. It cannot show that a
   command does nothing, that a control vanished, or that the caret is in the wrong place.
   **Launch the app.** The plan's own Task 16 Step 5 said to; skipping it caused every defect above.
3. **Model-level tests pass while the product is unusable.** Assertions gravitate to what is easy
   to assert (the data model) rather than what the user experiences (what is drawn, what a
   keystroke does). If a feature's value is visual or interactive, a model assertion is not
   coverage.
4. **Ship a build early and often.** All feedback arrived after task 16 of 16. A build in the
   user's hands after task ~10 would have ended this far earlier and far cheaper.
5. **Scale review effort to risk, not to diff size.** Heavy adversarial review was run on a branch
   that should not have existed. Rigor applied to the wrong artifact is pure cost.
6. **Absence is invisible in a diff.** Every review here read a diff. A diff cannot show you the
   feature that is *missing* (⌘A, gutter, font sizing) — only running the thing can.

---

## 4. What to salvage from the branch

The branch is not worthless. `Sources/Marginal/Blocks/` is pure Swift, AppKit-free, and well
tested — and it is independently useful **without any editor change**:

- **`MarkdownBlockParser`** can give `MarkdownHTMLRenderer` the **table support it lacks**, which
  fixes **tables in PDF export** — the most-used feature in daily use. `MarkdownHTMLRenderer`
  today never calls `parseTables`, so table lines fall through to the paragraph branch and export
  as literal `| a | b |` text. Related known gaps in the same renderer: `listItemText` doesn't skip
  `item.taskMarkerRange` (so `- [x] done` exports as `[x] done`), and list grouping is flat (no
  nesting).
  - Prior art: table emission for the HTML renderer exists on the abandoned branch
    `mode-switch-code-live-preview`, commit `29ca1e5`.
- **`MarkdownSerializer`** is a canonical-markdown formatter (bullets, numbering, table padding).
  Useful later for a "Format document" command — but note it **reflows hard-wrapped paragraphs**,
  so it must never run implicitly on save in 0.3.0.
- **`specs/notion-design-tokens.md`** is the real deliverable of this whole effort: a measured
  token table (heading scale, block rhythm, code card, table, colors) with per-token status. Use it
  as the checklist for section 5.

Everything under `Sources/Marginal/BlockEditor/` can be discarded.

---

## 5. The 0.3.0 visual plan

**Key insight: 0.3.0's architecture is _better suited_ to Notion's look than the block editor was.**

Notion's vertical rhythm is per-block top/bottom padding. In the block editor every block is its
own text view, so `paragraphSpacingBefore` / `paragraphSpacing` are dropped by TextKit (they only
apply *between* paragraphs sharing a text container) — the spacing had to be hand-rolled with
`NSStackView.setCustomSpacing`. **In 0.3.0's single text view those attributes just work.** The
thing that was hardest in the new architecture is nearly free in the old one.

Work in this order — highest visual payoff per unit of risk first. One change, one build, one look.

1. **Block rhythm (biggest win, smallest change).** Per-line-type `paragraphSpacingBefore` /
   `paragraphSpacing` in `MarkdownStyler`. Target values from the token spec, as ratios of the
   editor font size (at 16pt): H1 30/6, H2 26/6, H3 22/6, body 6/6, list item 6/1, quote 8/8.
   The current cramped look is mostly this.
2. **Heading scale and weight.** Scale `[1.875, 1.5, 1.25, 1.125, 1.0, 0.875] × base`, semibold.
   Note: the design system's "bold" is **semibold (600)**, never 700.
3. **Code block card.** A rounded 10pt `DesignPalette.surfaceCode` rect behind the fenced range,
   content inset ~1.375em, mono at 0.85×, line height 1.5. This is custom drawing —
   `MarkdownLayoutManager` already draws quote bars and bullet glyphs, so it is the natural home
   and the pattern already exists there.
4. **Table grid.** Hairline `DesignPalette.hairline` rules + `surfaceCode` header tint, header
   weight `.medium` (500), cell padding 0.5625em. Same drawing approach as (3).
5. **Inline code chip.** Rounded background + padding behind inline code runs (the token spec marks
   this deferred precisely because it needs custom drawing).

Before starting: open a real daily-driver document in 0.3.0, screenshot it next to
`specs/notion-design-tokens.md`, and write down what actually looks wrong. Your eye on real
content beats the spec.

---

## 6. Known defects if anyone ever revisits the branch

- **Heading typing bug (open).** After a shorthand kind change, the text view's typing attributes
  are stale, so typed characters render with the old block kind's font.
- `__bold__` at the very start/end of a block no longer renders bold — a side effect of the
  flanking guard added to stop `snake_case_word` being rewritten to `my*function*name` on save.
- No block-aware paste: multi-paragraph markdown lands in one block.
- ⌘+/⌘− font sizing is unreachable in Live mode (implemented only in Code mode's text view).
- Status-bar Live/Code switch was implemented as a View menu item (⌘⇧P) instead.
- 4-space indented code blocks are flattened into one paragraph by the block parser.

---

## 7. Environment gotchas (these cost the most wall-clock time)

- **`xcodebuild` wedges at 0% CPU** after concurrent builds or a `kill -9` of a test host. Symptom:
  a build process alive for an hour with no CPU and no log output. Fix:
  `pkill -9 -f xcodebuild; rm -rf ~/Library/Developer/Xcode/DerivedData/Marginal-* ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex`.
  **Never run two builds at once** — they corrupt the shared module cache.
- **Pin `-derivedDataPath`** when building from a git worktree, otherwise every run cold-builds
  (~7-10 min) because the worktree path hashes to a new DerivedData directory.
- **`DocumentViewControllerTests.testToggleShowSourceTwiceRestoresStyledRendering` fails locally**
  when a real app run has left a zoomed font size behind: the test reads
  `UserDefaults.standard`'s `editorFontPointSize` (expects 16, gets e.g. 27). Fix:
  `defaults delete com.jochemberends.marginal editorFontPointSize`. On clean CI the key is unset
  and the code falls back to 16, so it is green there. The test suite reading real user defaults is
  the underlying bug.
- **Never call `NSTextView.mouseDown` in a headless test** — it enters AppKit's modal
  mouse-tracking loop waiting for a mouse-up that never arrives and hangs the entire suite
  indefinitely. Drive the delegate hook instead.
- A full `xcodebuild test` run is ~7-10 minutes; it exceeds most agent tool timeouts. Run it in the
  background and watch the log, or scope with `-only-testing:`.

---

## 8. Open cleanup

- [ ] Close PR #2. Keep the branch on the remote so `Sources/Marginal/Blocks/` stays salvageable
      for the HTML-renderer/table work in section 4.
- [ ] Remove the side-by-side build: `rm -rf /Applications/Marginal-0.8.0.app`
      (bundle id `com.jochemberends.marginal.v080`, ad-hoc signed, local only — never distribute it).
- [ ] Decide whether to keep the `0.8.0` version bump (`project.yml`) or revert to `0.3.x` for the
      visual-parity work.
