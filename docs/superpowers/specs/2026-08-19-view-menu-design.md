# View menu — design

**Date:** 2026-08-19
**Ships in:** 0.11.0 (on the existing `tables-0.11.0` branch and PR)

## Problem

Three commands exist only as keyboard shortcuts, with nothing in the menu bar to announce them:

| Shortcut | What it does | Discoverable? |
|---|---|---|
| ⌘= / ⌘+ | Grow the editor text | No |
| ⌘- | Shrink the editor text | No |
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
Zoom Out                       ⌘-
Actual Size                    ⌘0
──────────────────────────
Show Source                    ⌘⇧P    ✓ when showing source
──────────────────────────
Show Character & Word Count           ✓ when showing counts
```

Zoom In is drawn above as ⌘+, the equivalent Apple's own apps display. Which of ⌘= / ⌘+ the item
*displays* is settled by the spike below; both must keep working either way. Zoom Out is ⌘- and
only ⌘-.

**Every key equivalent in this document is ASCII.** Zoom Out is the hyphen-minus `-` (U+002D), the
character `MarkdownTextView.keyDown` matches today — *not* the typographic minus `−` (U+2212).
`keyEquivalent: "−"` compiles and then never matches a keypress, which is exactly the silent
regression this design is trying to avoid.

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

### The physical keys that must keep working

A menu item matches on the **character** the key produces, not on the key you pressed. On a
combined `=`/`+` key, ⌘+ *is* ⌘⇧= — one gesture, not two bindings — because
`charactersIgnoringModifiers` strips Command and Option but **honours Shift**. So the four gestures
below reduce to two characters, and `case "=", "+":` in `keyDown` already covers all of them:

| Gesture | Character seen | Extra modifier flags | Zooms |
|---|---|---|---|
| ⌘= (unshifted `=` key) | `=` | — | in |
| ⌘⇧= (same key, shifted) — displayed as ⌘+ | `+` | `.shift` | in |
| ⌘ + **numpad** `+` | `+` | `.numericPad` (and possibly `.function`) | in |
| ⌘- | `-` | — | out |

### Why a menu item alone is not enough

AppKit offers every key event to the main menu **before** the focused view's `keyDown`, and a menu
item holds exactly **one** key equivalent. Two consequences:

1. A single Zoom In item can display only one of ⌘= / ⌘+, leaving the other unmatched.
2. Menu matching compares the event's device-independent modifier flags against
   `keyEquivalentModifierMask`. The numpad carries `.numericPad` in those flags, which a plain
   `[.command]` mask does not include — so **⌘ + numpad `+` is the most likely thing to break**,
   and it is the author's habitual way of zooming. Today's `keyDown` catches it for free because
   `modifierFlags.contains(.command)` is indifferent to any other flag being set.

### Therefore: menu for discovery, `keyDown` retained as the fallback

`MarkdownTextView.keyDown` **stays**, unchanged in behaviour. The two paths are mutually exclusive
by AppKit's dispatch order, so nothing can fire twice: whatever the menu matches never reaches
`keyDown`; whatever the menu misses — plain ⌘=, numpad ⌘+ — falls through and behaves exactly as it
does now. The menu earns its place as discoverability and as the home for the new Actual Size
command, not by becoming the only route.

This reverses an earlier draft of this design, which had the menu items making `keyDown` dead code
and deleted it. That reasoning held only for a US keyboard's main row and ignored the numpad
entirely. `MarkdownTextViewShortcutDelegate` therefore survives as well.

The spike still runs, but now to confirm rather than to decide:

1. Which of the four gestures a menu item actually matches (especially numpad `+`, and whether a
   hidden duplicate item can hold the ⌘= alternate — AppKit may skip hidden items during
   key-equivalent matching, which must be measured, not assumed).
2. That no gesture triggers the action **twice** through both paths.

**Success criterion: after this change, all four gestures in the table above still zoom, and none
zooms by two steps.**

## Testing

`AppDelegate.buildMainMenu` is `private static`, which is why the suite has no menu test at all. It
becomes internal so tests can assert structure.

| Test | Asserts |
|---|---|
| Menu structure | View exists, sits between Edit and Window, with the expected titles, key equivalents, actions and separators |
| Zoom actions | `zoomIn`/`zoomOut` move the size by `FontSizing.step` and honour the 10–36 clamp |
| Actual Size | Returns to 16 from both above and below, and persists |
| Validation | Checkmark state for Show Source and for both readout modes |
| Shortcut regression | Each of the four gestures still zooms: `=`, `+` with `.shift`, `+` with `.numericPad`, and `-`; plus ⌘⇧P |
| No double-fire | A synthesised event that the menu matches does not also reach `keyDown` |
| Status bar | Menu toggle and bar click reach the same state; the label text changes accordingly |

The existing `testCommandPlusIncreasesFontSizeSameAsCommandEquals` stands as-is: `keyDown` keeps its
current behaviour, so the test that guards it keeps its current meaning. It is extended with the
numpad case rather than rewritten.

## Out of scope

Persisting the readout choice, a preferences UI for text size, per-window font sizes, and any
shortcut for the readout toggle. The Preferences window stays the stub it is.
