# App icon generation prompt (for Gemini / ChatGPT image models)

Paste the prompt below verbatim. Ask for 4 variations, pick the strongest, then iterate on
that one. Request 1024×1024 PNG. The macOS squircle mask is applied by Xcode later, so the
artwork itself should be a full-bleed rounded square.

---

## Prompt

Design a macOS app icon for **"Marginal"**, a native Mac markdown editor known for beautifully
clean, Notion-quality document rendering. The name refers to the *margin* of a page —
marginalia, careful typography, white space.

**Concept:** A single sheet of warm paper-white, seen straight on, filling a rounded square
(modern macOS Big Sur / Sequoia icon shape). On the sheet: a thin vertical margin rule offset
to the left, and next to it a large, confident lowercase serif "m" (or an elegant pilcrow ¶)
drawn in near-black ink. One small accent element — a short underline or margin tick — in
soft coral red. The composition should feel like the first page of a beautifully typeset book,
reduced to its absolute essentials.

**Style rules:**
- Flat and minimal with very subtle depth: a faint top-to-bottom gradient on the background
  and a soft inner edge highlight, exactly like Apple's own modern system icons (Notes,
  TextEdit) — no skeuomorphism, no 3D, no paper curl, no pencil.
- Palette: paper white `#FFFEFC` background, ink `#2C2C2B` for the glyph and margin rule,
  coral red `#EB5757` for the single accent. Nothing else.
- The glyph must be optically centered and legible at 16×16 px.
- Generous negative space — at least 20% padding around the glyph.
- No words, no letters other than the single "m" (or ¶), no markdown symbols like # or *,
  no borders, no drop shadow outside the icon shape.

**Output:** 1024×1024, rounded-square canvas, transparent outside the rounded square.

---

## Variation asks (one at a time, after picking a base)

- "Same icon, but with the pilcrow ¶ instead of the m."
- "Same icon, dark variant: ink `#191918` background, paper-white glyph, same red accent."
- "Same icon, tinted variant: monochrome white glyph on transparent, for macOS tinted icon mode."
- "Reduce the accent to a single 2px underline under the m."

## Post-processing checklist

1. Downscale-test at 16/32/128 px — the glyph must stay readable.
2. Run through an .icns generator (or Xcode asset catalog with all slots).
3. Keep the 1024 master PNG in `marketing/` alongside this file.
