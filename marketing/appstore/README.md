# App Store screenshots

Six marketing screenshots for the Mac App Store listing, in upload order. All are
**2880 × 1800 px, PNG, RGB, no alpha** — App Store Connect's highest accepted size
(it also accepts 1280×800, 1440×900, 2560×1600).

| File | Headline | Shows |
|---|---|---|
| `01-hero.png` | Markdown that reads the way it renders. | Icon + wordmark, rendered document |
| `02-reveal.png` | The syntax hides itself. | Cursor on a bold word, markers revealed |
| `03-tasks.png` | Tasks you can click. | Task list, violet checkboxes, strikethrough |
| `04-beautiful.png` | Beautiful by default. | Table grid + highlighted code card |
| `05-dark.png` | Paper by day, ink by night. | Dark appearance |
| `06-chrome.png` | Always know where you are. | Line-number gutter + status bar |

The first three matter most — they show on the product page without scrolling.

## Regenerating

The compositions are built from real app renders (the offscreen text-engine harness
used for the site screenshots) composed on design-system tokens by `generate.py`,
then rasterized at exact pixel size:

```bash
python3 generate.py   # writes shot-0N.html next to the app renders
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --force-device-scale-factor=1 --window-size=2880,1800 \
  --screenshot=01-hero.png shot-01.html
```

The `as-*.png` app renders referenced by the HTML are produced by a temporary test
in the repo (see the render harness pattern in `Tests/MarginalTests`) — re-render
them after visual changes to the app so the shots never drift from reality.
