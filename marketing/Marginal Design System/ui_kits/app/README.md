# UI kit — Marginal for macOS

A recreation of the app's single window: traffic-light chrome, native tab strip, the
rendered-markdown canvas, and the status rule at the bottom.

**Files**
- `index.html` — the interactive window (open it directly)
- `EditorApp.jsx` — composes WindowChrome + TabBar + MarkdownDoc from the design system
- `documents.js` — three sample documents (release notes, essay draft, README)

**What is interactive**
- Switch tabs; close a tab; `+` reopens all three
- Toggle light / dark from the toolbar
- Click any block in the document — its markdown markers fade in, everything else stays clean

**What is deliberately not built** — file open panel, find & replace, preferences: no source
material describes them, so they are omitted rather than invented.
