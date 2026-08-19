# App Store copy — Marginal 0.11.0

Everything App Store Connect needs for the 0.11.0 submission. Three blocks below: the
promotional text, the "What's New in This Version" notes, and the App Review notes.

---

## Promotional text

App Store Connect ▸ your 0.11.0 version ▸ **Promotional Text** (170-character limit; can be
changed at any time without submitting a new build).

Marginal - Markdown editor that renders as you type. Now with tables that wrap and stay
aligned on screen, export to PDF as real grids, and a View menu for text size.

> 166 characters.

---

## What's New in This Version

App Store Connect ▸ your 0.11.0 version ▸ **What's New in This Version**. 1,357 characters,
inside the 4,000-character limit. No version number in the opening line, no bare "bug fixes and
performance improvements", no mention of other platforms or of pricing — the three things App
Review most often sends notes back for.

---

Tables are the heart of this release. They now hold their shape wherever they go: on the page,
across a resize, and in an exported PDF.

TABLES
• A table too wide for the page now wraps inside each cell, under its own column, instead of
  spilling its overflow back to the left margin. Columns are sized to fit the page, and a
  column of prose gives up room before a narrow one does.
• Grid lines and the header tint enclose the whole of a wrapped row, however tall it grows.
• Resize the window and tables re-flow to the new width.
• Tables export to PDF as real grids — with the formatting inside cells and your column
  alignment preserved. A long table repeats its header on each new page and never splits a row
  across a page break. Copy as HTML carries the table too.
• The seam that appeared between a table's header and its first row is gone.

VIEW MENU
• Zoom In, Zoom Out and Show Source now appear in a View menu, so the shortcuts that always
  existed are finally somewhere you can find them.
• Actual Size returns the text to its default in one step.
• Show Character & Word Count switches the status bar between the cursor's position and the
  document's counts — previously only possible by discovering the bar was clickable.

FIXES
• A quoted line shown as example code inside a code block no longer gets a quotation bar drawn
  beside it.

---

## Review notes (App Store Connect ▸ App Review Information)

Nothing in this release changes data handling, entitlements, sandboxing, or network use.
Marginal reads and writes only the documents the user opens, stays sandboxed, and makes no
network requests apart from the existing manual "Check for Updates" action, which is omitted
entirely on App Store installs.

This release is presentation only: table layout on screen, table markup in the PDF/HTML export
path, and new menu items for commands that already existed as keyboard shortcuts. No new
frameworks, no new entitlements, no new file access, and no change to the document format —
files are saved as plain Markdown exactly as before.

To see the main change, open any document containing a Markdown table wider than the window:
the cells wrap within their own columns, and File ▸ Export as PDF renders it as a grid.

## Version metadata

- Marketing version: 0.11.0
- Build: 11
- Minimum macOS: 14.0
- App icon: `AppIcon` (production)
