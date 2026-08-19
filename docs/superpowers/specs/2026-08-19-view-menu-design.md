# View menu — design

**Date:** 2026-08-19
**Ships in:** 0.11.0 (on the existing `tables-0.11.0` branch and PR)

## Problem

Three commands exist only as keyboard shortcuts, with nothing in the menu bar to announce them:

| Shortcut | What it does | Discoverable? |
|---|---|---|
| ⌘= / ⌘+ | Grow the editor text | No |
| ⌘− | Shrink the editor text | No |
| ⌘⇧P | Toggle Show Source | No |

A fourth command has no keyboard shortcut *and* no menu item: switching the status bar between the
cursor position and the character/word counts, which is reachable only by clicking the bar and only
findable by discovering the tooltip.

Nothing tells a user any of this exists. There is also no way back to the default text size except
stepping one point at a time — up to twenty presses from either end of `FontSizing`'s 10–36 range.

## Solution

A new **View** menu, between Edit and Window:

```
Zoom In                        ⌘+
Zoom Out                       ⌘−
Actual Size                    ⌘0
──────────────────────────
Show Source                    ⌘⇧P    ✓ when showing source
──────────────────────────
Show Character & Word Count           ✓ when showing counts
```

Zoom In is drawn above as ⌘+, the equivalent Apple's own apps display. Which of ⌘= / ⌘+ the item
*displays* is settled by the spike below; both must keep working either way.

View, not Edit: Apple's convention puts zoom and display-state toggles under View (Safari, Preview,
Xcode), and Edit is for commands that change the document. Text size and which readout the status
bar shows change how the document *looks*, not what it contains.

`Show Character & Word Count` is a single checkable item, not a pair of radio items: checked shows
the counts, unchecked shows the cursor position. Clicking the status bar keeps working unchanged —
the menu item is an addition, not a replacement, and the two stay in sync because both mutate the
same state.

## Wiring

Menu items carry an `action:` and **no target**, so AppKit walks the responder chain and finds
`DocumentViewController`. This is the pattern the codebase already uses for `Export as PDF…` and
`Copy as HTML`, and it gets enabling right for free: with no document window focused, nothing in
the chain answers the selector and the items grey out by themselves.

Rejected: targeting `AppDelegate` and reaching for `NSApp.keyWindow?.contentViewController`. It
needs hand-written validation to achieve the same enabling, and it is the messier of the two
patterns already in that file (the ⌘1–⌘9 tab items work that way and need `validateMenuItem` to
compensate).

Checkmarks come from `validateMenuItem` on `DocumentViewController`, reading `isShowingSource` and
the status bar's current mode when the menu opens. Deriving them per-open is what lets the readout
stay **per-window and in-memory**, exactly as today: two windows in different modes each show their
own checkmark, and nothing new is persisted. Font size continues to persist app-wide under the
existing `editorFontPointSize` key; that is unchanged.

`StatusBarView.readout` is `private` today and must become readable and settable by the controller.

## Keyboard shortcuts: the one real risk

AppKit offers every key event to the main menu **before** the focused view's `keyDown`. So once
these keys are menu key equivalents, the hand-rolled interception in `MarkdownTextView.keyDown`
becomes unreachable — not wrong, but dead: code that looks live and can never run.

The hazard is that a menu item holds exactly **one** key equivalent while ⌘= and ⌘+ *both* zoom in
today. Whichever the menu claims, the other is at risk. Therefore:

1. **Spike first.** A throwaway AppKit app determines empirically which of ⌘=, ⌘+, ⌘− and ⌘⇧P a
   menu item actually matches, and specifically whether a second, hidden item can hold the ⌘=
   alternate (AppKit may skip hidden items during key-equivalent matching — this must be measured,
   not assumed).
2. **Delete only what the spike proves is unreachable.** Any combination the menu does not catch
   keeps its `keyDown` case, and the design note is updated to say so.
3. **Regression tests for all four** shortcuts, which fail if any stops working.

If every case is covered by the menu, `MarkdownTextViewShortcutDelegate` and its conformance are
deleted along with the `keyDown` block, since those three methods are its only members. If ⌘= needs
`keyDown`, the protocol shrinks to one method rather than disappearing.

**Success criterion: after this change every shortcut that worked before still works.**

## Testing

`AppDelegate.buildMainMenu` is `private static`, which is why the suite has no menu test at all. It
becomes internal so tests can assert structure.

| Test | Asserts |
|---|---|
| Menu structure | View exists, sits between Edit and Window, with the expected titles, key equivalents, actions and separators |
| Zoom actions | `zoomIn`/`zoomOut` move the size by `FontSizing.step` and honour the 10–36 clamp |
| Actual Size | Returns to 16 from both above and below, and persists |
| Validation | Checkmark state for Show Source and for both readout modes |
| Shortcut regression | ⌘=, ⌘+, ⌘− and ⌘⇧P each still perform their action |
| Status bar | Menu toggle and bar click reach the same state; the label text changes accordingly |

The existing `testCommandPlusIncreasesFontSizeSameAsCommandEquals` covers the delegate call and will
need rewriting against whichever path survives.

## Out of scope

Persisting the readout choice, a preferences UI for text size, per-window font sizes, and any
shortcut for the readout toggle. The Preferences window stays the stub it is.
