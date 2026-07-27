# Landing page + design system prompt (for Claude Design 2.0)

Paste everything below the line as one prompt. Attach (or reference) the finished app icon
as `icon.png` and 2–3 real app screenshots before running it — the page should use real
renders, not mockups. The expected output is a design-token sheet plus a single
self-contained `index.html` you can host anywhere (GitHub Pages, Netlify, S3).

---

## Prompt

Create (1) a small design system and (2) a one-page marketing landing page built on it, for
a macOS app called **Marginal**.

### The product

Marginal is a native macOS WYSIWYG markdown editor. You write plain `.md` files, but the
document renders live with Notion-quality typography — no split preview pane, no raw-syntax
soup. Markdown syntax markers hide themselves except around the cursor.

Feature facts you may use (do not invent others):
- True WYSIWYG: marks like `**` and `#` hide while you type, reveal at the cursor.
- Notion-grade rendering, measured pixel-by-pixel from Notion itself: tables with real grids,
  rounded code-block cards with syntax highlighting, task-list checkboxes, auto-renumbered
  ordered lists, blockquotes, emoji `:shortcodes:`.
- Files stay plain markdown — no lock-in, no database, works with git.
- Native AppKit app: instant launch, low memory, feels like a Mac app because it is one.
- Tabs: multiple documents in one window, macOS-native tab bar, ⌘1–⌘9 switching.
- Copy as Markdown or as HTML. Light and dark mode.
- Open source, Apache 2.0, by Jochem Berends.

Audience: Mac-first writers, developers, and note-takers who love Notion's look but want
local plain-text files. Tone: quietly confident, typography-nerd, zero marketing fluff.
Tagline direction (improve on it): "Markdown that reads the way it renders."

### 1. Design system first

Derive a compact token sheet before designing the page, and use it consistently:
- **Color**: paper white `#FFFEFC` surfaces, ink `#2C2C2B` text, warm gray `#F7F6F3` panels,
  hairline `#E6E5E3`, single accent coral `#EB5757` (the app's inline-code red). Provide a
  dark-mode counterpart for every token (`prefers-color-scheme`).
- **Type**: system-ui stack for UI/headings (weights 400/500/600 only — the app uses 600, never
  700); SF Mono/Menlo stack for code snippets. A modular scale anchored at 16px body,
  1.5 line height; headings at 1.25/1.5/1.875× (the app's own heading scale).
- **Spacing**: 8px base grid; section rhythm generous (Notion-like white space).
- **Radii**: 4px chips, 10px cards (the app's code-card radius), 20px screenshot frames.
- **Components**: nav bar, primary/secondary button, feature card, keyboard-key cap (`⌘1`),
  code-block card mimicking the app's rendering, screenshot frame with subtle shadow, footer.
Document the tokens briefly in an HTML comment at the top of the file.

### 2. The page

Single `index.html`, fully self-contained (inline CSS, no frameworks, no external fonts or
scripts; the only external file references allowed are `icon.png` and the screenshot images).
Semantic HTML, responsive from 360px to wide desktop, dark mode via media query, and it must
score well on Lighthouse without any tricks.

Sections, top to bottom:
1. **Nav**: icon + wordmark "Marginal", links to Features / Download / GitHub.
2. **Hero**: icon large, headline, one-sentence subhead, primary CTA "Download for macOS"
   (links to GitHub releases), secondary "View on GitHub". Below: the main app screenshot in a
   window-chrome frame.
3. **The trick** (signature section): a side-by-side or animated-feel demonstration of raw
   markdown vs. what Marginal shows — this is the product's whole point; give it room.
4. **Feature grid**: 6 cards from the feature facts above, each with a small inline SVG glyph
   (draw them yourself, no icon fonts).
5. **Notion-parity strip**: one line explaining the rendering was measured from Notion
   pixel-for-pixel, with a table/code screenshot.
6. **Footer**: open source note (Apache 2.0), copyright © 2026 Jochem Berends, GitHub link.

Details that matter: real `<kbd>` caps for shortcuts, an actual styled code block showing a
few lines of markdown, buttons with visible focus states, `prefers-reduced-motion` respected
if you add any motion, and OpenGraph/meta tags with the tagline. No stock imagery, no emoji
in headings, no gradient text.
