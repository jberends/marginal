# Marginal — Design System

**Marginal** is a native macOS WYSIWYG markdown editor by Jochem Berends (open source,
Apache 2.0). You write plain `.md` files; the document renders live with Notion-quality
typography — no split preview pane, no raw-syntax soup. Markdown markers hide themselves
except around the cursor.

**Audience** — Mac-first writers, developers and note-takers who love Notion's look but want
local plain-text files.

**Surfaces covered here**
1. *Marginal for macOS* — the app window: tab strip, rendered document canvas, toolbar.
2. *marginal.app* — the marketing site: hero, feature grid, shortcuts, download.

## Sources

Everything in this system derives from two files the user supplied (copied into `assets/`):

| Source | Copied to | What it gave us |
|---|---|---|
| `marginal-icon.png` (1024×1024 app icon) | `assets/marginal-icon.png` | The only brand mark |
| `marginal-icon-design-system.png` (icon spec sheet) | `assets/marginal-icon-spec.png` | Base palette, icon geometry, macOS HIG compliance notes |

Plus a written product brief (feature facts, tone, colour and type direction) pasted in chat.

**No codebase, Figma file or repository was provided**, and no public source for Marginal was
found. Component behaviour is therefore modelled on the brief and on macOS/AppKit convention,
not read from app source. If a repo exists, attach it — several numbers here (exact toolbar
height, tab metrics, real syntax-highlight theme) should be replaced with measured values.

---

## Content fundamentals

The voice is **quietly confident, typography-nerd, zero marketing fluff**. It sounds like a
careful engineer explaining a decision, not a landing page selling one.

- **Casing** — sentence case everywhere: headings, buttons, nav, table headers. The only
  uppercase is the 11px eyebrow label, tracked +0.04em. No Title Case Buttons.
- **Person** — mostly impersonal or second person, used sparingly: "Files stay plain markdown",
  "Your notes are still markdown." Never "we"; the product doesn't have a marketing department.
- **Sentence shape** — short declaratives. State the fact, stop. A period is stronger than an
  exclamation mark; there are no exclamation marks in this system.
- **Punctuation** — em dashes for asides, en dashes for ranges (⌘1–⌘9), typographic quotes.
- **Emoji** — none. (The app *supports* emoji `:shortcodes:` in documents; the brand never uses
  them in its own copy.)
- **Numbers and claims** — only claims from the brief: Apache 2.0, native AppKit, ⌘1–⌘9 tabs,
  copy as Markdown or HTML, light and dark mode. Never invent benchmarks, user counts or awards.
- **Technical words are allowed** — "git", "AppKit", "plain text", ".md" appear in headlines.
  The audience knows them; softening the language would be condescending.

Tagline: **"Markdown that reads the way it renders."**

Examples

| Do | Don't |
|---|---|
| "Marks hide themselves." | "Revolutionary syntax-hiding technology!" |
| "Files stay plain markdown. Works with git." | "Future-proof your content in the cloud." |
| "macOS 13 or later · Universal · Apache 2.0" | "Blazingly fast ✨" |
| "Download for macOS" | "Get Started Free →" |

---

## Visual foundations

**Colour.** Paper, not white. Surfaces are `#FFFEFC` (page) and `#F7F6F3` (panels, code
blocks); text is warm near-black `#2C2C2B` with `#232323` for headings. Rules are hairline
`#E6E5E3`. There is exactly **one accent — violet `#8E1FCB`**, high-chroma and slightly magenta-leaning
so it pops off the cream paper rather than sinking into it, and never a cool blue-purple;
it appears on the single primary button, inline code, and checked task boxes, and nowhere else.
Semantic green/amber exist only for syntax highlighting. Every token has a dark counterpart
under `prefers-color-scheme: dark` (page `#1E1E1D`, violet lifts to `#CB7DF7`); `[data-theme]`
scopes let a single frame be forced light or dark.

**Type.** The system UI face (SF Pro via `system-ui`) for everything, SF Mono/Menlo for code,
filenames and markdown markers. **Weights 400/500/600 only — 600 is the heaviest weight in the
product, 700 never appears.** Body is 16px/1.5; headings follow the app's own multipliers
30 / 24 / 20px with `-0.02em` tracking; marketing display sizes are 40 and 56px at `-0.03em`.
Document measure is 720px (~68 characters). Small UI runs 14/13/12/11px.

**Spacing.** 8px base grid with a 4px half-step for chrome. Marketing sections breathe at 96px;
card padding is 24px; the toolbar is 52px and the tab strip 34px. White space is the main
compositional device — there are no dividers where space will do, and no boxes around text.

**Backgrounds.** Flat paper colour. No gradients, no photography, no illustration, no texture,
no pattern, no blobs. The one translucency in the system is the sticky nav: 88% paper with a
20px backdrop blur and 180% saturation, exactly like a native macOS toolbar. Nothing else is
transparent.

**Borders & cards.** A card is a paper rectangle with a 1px hairline border and a 10px radius —
flat by default. Shadow arrives only when something is genuinely raised: `--shadow-raised` for
interactive cards, `--shadow-popover` for menus, `--shadow-frame` (one large soft warm shadow)
for screenshot frames. No coloured left borders, no double borders, no glow.

**Radii.** 4px chips and inline code · 6px buttons · 10px cards and code blocks (the app's
code-card radius) · 20px screenshot frames · the icon's own squircle. Never fully rounded
except a rare pill.

**Motion.** Mac motion: 80–280ms, `cubic-bezier(.32,.72,0,1)`, no bounce, no spring, no
parallax, nothing scroll-triggered. The signature transition is the 120ms opacity fade of
syntax markers at the cursor — it fades, never slides, and never reflows the line.

**States.** Hover darkens rather than lightens (primary → `#7617A9`; secondary → sunk paper;
ghost → panel fill). Press scales to 0.985 for 80ms — a small settle, not a squash. Focus is a
3px violet ring at 28% alpha, never a browser outline. Disabled is 40% opacity with no colour
change. Links are violet and underline on hover only.

**Imagery.** There is no photography and no illustration in this brand. Product shots are the
only images: real app windows, straight-on, never tilted, never in perspective, never with fake
browser chrome. Frame them at 20px radius with `--shadow-frame`. Colour temperature is warm
neutral; no filters, no grain.

**Layout.** 1080px content maximum, 24px gutters, centred. The site nav is sticky; nothing else
is fixed. Feature grids are 3-up desktop, and content is always allowed to end — no filler rows.

---

## Iconography

**There is no icon library in this brand, and none was provided.** Rather than import one and
imply a system that doesn't exist, Marginal uses three things:

1. **The app icon** (`assets/marginal-icon.png`) — a long-tail serif "m" beside four grey text
   lines on a document with a dark `#232323` header band. Squircle, front-facing, subtle depth
   only, no wordmark. It is the only brand mark; **there is no logotype** — set the word
   "Marginal" in the UI face at weight 600 wherever a wordmark would go (this is what `NavBar`
   and `Footer` do). Do not draw, redraw or "modernise" the mark.
2. **Markdown glyphs as icons** — feature cards are labelled with monospace fragments of
   markdown itself: `##`, `**`, `.md`, `- [ ]`, `>`. They are set in `--font-mono` at
   `--text-subtle`. This is the brand's iconography.
3. **Mac system glyphs** — ⌘ ⇧ ⌥ ⌃ ↩ ⌫ in key caps, and the traffic-light dots
   (`#FF5F57 / #FEBC2E / #28C840`) in window chrome. Unicode, never redrawn as SVG.

Emoji are rendered *inside documents* (the app supports `:shortcodes:`) but never used in UI
or marketing copy. No CDN icon set is linked; if a future screen truly needs pictograms, ask
for the app's SF Symbols usage rather than substituting a web icon library.

---

## Index

**Root**
- `styles.css` — the single entry point consumers link (imports only)
- `thumbnail.html` — homepage tile
- `SKILL.md` — Agent Skills wrapper
- `tokens/` — `colors.css`, `typography.css`, `spacing.css`, `radii.css`, `elevation.css`,
  `motion.css`, `base.css`
- `assets/` — `marginal-icon.png`, `marginal-icon-spec.png`
- `guidelines/` — 17 foundation specimen cards (Colors, Type, Spacing, Brand)

**Components** (`components/<group>/<Name>.jsx` + `.d.ts` + `.prompt.md`)

| Component | Group | What it is |
|---|---|---|
| `Button` | core | The only button — primary / secondary / ghost, three sizes |
| `KeyCap` | core | A single macOS key cap |
| `Shortcut` | core | A run of key caps (⌘1) |
| `Chip` | core | 4px metadata label — neutral / accent / code |
| `NavBar` | navigation | Sticky translucent site header |
| `Footer` | navigation | Warm-gray footer with link columns |
| `FeatureCard` | content | Marketing feature tile |
| `CodeCard` | content | The app's rounded code block, with syntax tokens |
| `ScreenshotFrame` | content | 20px product-shot frame |
| `WindowChrome` | app | macOS window: traffic lights, title, toolbar |
| `TabBar` | app | Document tab strip with ⌘1–⌘9 |
| `MarkdownDoc` | app | The rendered-document canvas |

The brief named seven components (nav bar, primary/secondary button, feature card, key cap,
code-block card, screenshot frame, footer); all seven exist.

**Intentional additions** — `Chip` (the brief specifies a 4px chip radius but no component),
and the three `app/` components (`WindowChrome`, `TabBar`, `MarkdownDoc`), without which the
product itself — a tabbed editor showing rendered markdown — cannot be recreated.

**UI kits**
- `ui_kits/app/` — the macOS editor window (tabs, light/dark, click-to-move-caret)
- `ui_kits/site/` — the marginal.app homepage

**Known gaps / to verify against real source**
- Exact toolbar, tab and inspector metrics (estimated from macOS convention)
- The app's real syntax-highlight theme (ours is a plausible warm set on the `--syn-*` tokens)
- Preferences, find-and-replace, file-open panels — omitted, not invented
