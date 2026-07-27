# Notion design tokens (measured)

Measured 2026-07-25 from the live Notion renderer (published page `markdown-editor-feature-test`,
light theme, computed CSS via DevTools protocol). These are the source-of-truth values for
Marginal's Notion-parity rendering. All px values are at Notion's 16px body size — Marginal
implements them as ratios of `baseFont.pointSize` so they scale with the editor's type size.
The raw exported page lives at `test/markdown-editor-feature-test *.html` (note: the export
ships a simplified stylesheet; the values below come from the live app renderer).

## Typography

| Token | Notion (16px base) | Ratio | Marginal status |
|---|---|---|---|
| Body | 16px / 24px line height (1.5), weight 400, `rgb(44,44,43)` | 1.0 | ✅ |
| H1 | 30px / 1.3, weight 600 | 1.875 | ✅ semibold |
| H2 | 24px / 1.3, weight 600 | 1.5 | ✅ semibold |
| H3 | 20px / 1.3, weight 600 | 1.25 | ✅ semibold |
| H4 | 18px / 1.3, weight 600 | 1.125 | ✅ semibold |
| Bold | weight 600 (not 700) | — | ⚠️ uses system bold (700); switching breaks `.bold`-trait detection, deferred |
| Link | underline, text-colored | — | uses linkColor blue (arguably better affordance), deferred |

## Block rhythm (vertical spacing)

Notion blocks are flush (gap 0) — spacing lives inside each block as padding:

| Block | Padding (top/bottom at 16px) | Marginal status |
|---|---|---|
| Text | 6 / 6 (+2 inner) | N/A — markdown blank lines already render as spacer lines |
| H1 | 30 / 6 | deferred (blank lines in source double up; needs a coherent "collapse blank lines" pass) |
| H2 | 26 / 6 | deferred (same) |
| H3 | 22 / 6 | deferred (same) |
| List item | 6 / 1 (≈7px between items) | ✅ paragraphSpacing 0.4375× |
| Quote | 8 / 8 | deferred (blank-line model) |

## Blocks

| Token | Notion value | Ratio | Marginal status |
|---|---|---|---|
| Content column width | 720px | — | n/a (window-sized) |
| Quote bar | 3px solid, text color (solid, not translucent) | — | ✅ |
| Quote text | regular weight, normal text color (NOT italic, NOT gray), padding-left 14px | 0.875 | ✅ |
| Divider block | 13px tall block, 1px line | — | ✅ close enough |
| Code block card | bg `rgba(66,35,3,0.03)` warm, radius **10px**, padding 24px v / 22px h | inset 1.375 | ✅ |
| Code text | 13.6px (= 85% of body) / 20.4px line height (1.5), SFMono/Menlo | 0.85 | ✅ |
| Inline code | 85% mono, `rgb(235,87,87)` on `rgba(135,131,120,0.15)`, radius 4px, padding 0.17em/0.34em | — | ✅ color/size; rounded chip + padding needs custom drawing, deferred |
| Table grid line | `rgb(230,229,227)` 1px | — | ✅ separatorColor (close) |
| Table header row | bg `rgb(247,246,243)`, weight **500** (medium, not semibold) | — | ✅ medium |
| Table row | min-height 32px, rendered 35px at 16px | 2.2 | ✅ |
| Table cell padding | ~9px horizontal | 0.5625 | ✅ |
| List marker box | 24px-wide box per level (1.5em), grows for wide markers | — | ours: width-of-widest-marker + gap (visually equivalent) |
| To-do checkbox | 14×14px svg | 0.875 | ours: xHeight×1.35 ≈ close |
| Bulleted list dot | • at 24px font (≈8.4px dot) | — | ours: xHeight×0.85 ≈ close |

## Colors (light theme)

- Text: `rgb(44,44,43)`
- Table border: `rgb(230,229,227)`
- Table header bg: `rgb(247,246,243)`
- Code card bg: `rgba(66,35,3,0.03)`
- Inline code red: `rgb(235,87,87)`
- Inline code chip bg: `rgba(135,131,120,0.15)`

Marginal uses semantic system colors (labelColor, separatorColor, blends of
textBackgroundColor→labelColor) so dark mode works for free; the light-mode results are
within a few RGB points of the Notion values above.
