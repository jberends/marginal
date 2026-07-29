#!/usr/bin/env python3
"""Generates the App Store screenshot compositions (2880x1800) from the app renders."""

# Design-system tokens at @2x (the canvas is real pixels).
LIGHT = dict(page="#FFFEFC", panel="#F7F6F3", sunk="#F1F0EC", hairline="#E6E5E3",
             ink="#2C2C2B", header="#232323", muted="#6B6A67", subtle="#9A9895",
             violet="#8E1FCB", shadow="rgba(35,35,35,.16)")
DARK = dict(page="#1E1E1D", panel="#252524", sunk="#191918", hairline="#33332F",
            ink="#E8E7E3", header="#F2F1EE", muted="#A6A49F", subtle="#7C7A75",
            violet="#CB7DF7", shadow="rgba(0,0,0,.55)")

TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8"><style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  html,body {{ width:2880px; height:1800px; overflow:hidden; }}
  body {{
    background:{page}; color:{ink}; position:relative;
    font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
    -webkit-font-smoothing:antialiased;
  }}
  .caption {{ position:absolute; {caption_pos} }}
  .eyebrow {{
    font-family:"SF Mono",ui-monospace,Menlo,monospace;
    font-size:44px; color:{violet}; margin-bottom:40px; letter-spacing:.02em;
  }}
  h1 {{
    font-size:{headline_size}px; font-weight:600; letter-spacing:-.03em; line-height:1.05;
    color:{header}; max-width:{headline_max}px; text-wrap:balance; margin-bottom:48px;
  }}
  .sub {{ font-size:44px; line-height:1.4; color:{muted}; max-width:1400px; text-wrap:pretty; }}
  .brand {{ display:flex; align-items:center; gap:28px; justify-content:center; margin-bottom:56px; }}
  .brand img {{ width:112px; height:112px; }}
  .brand span {{ font-size:52px; font-weight:600; color:{header}; }}
  .window {{
    position:absolute; {window_pos}
    width:{window_width}px; border-radius:20px; overflow:hidden;
    background:{page};
    box-shadow:0 36px 96px {shadow}, 0 0 0 2px {hairline};
  }}
  .titlebar {{
    height:80px; background:{panel}; border-bottom:2px solid {hairline};
    display:flex; align-items:center; padding:0 32px; position:relative;
  }}
  .lights {{ display:flex; gap:16px; }}
  .lights i {{ width:24px; height:24px; border-radius:50%; display:block; }}
  .lights i:nth-child(1) {{ background:#FF5F57; }}
  .lights i:nth-child(2) {{ background:#FEBC2E; }}
  .lights i:nth-child(3) {{ background:#28C840; }}
  .title {{
    position:absolute; left:50%; transform:translateX(-50%);
    font-size:26px; font-weight:500; color:{muted};
  }}
  .window img {{ width:100%; display:block; }}
</style></head>
<body>
  <div class="caption">{brand}{eyebrow}<h1>{headline}</h1><p class="sub">{sub}</p></div>
  <div class="window">
    <div class="titlebar"><span class="lights"><i></i><i></i><i></i></span><span class="title">{doc_title}</span></div>
    <img src="{image}">
  </div>
</body></html>
"""

def shot(name, tokens, image, doc_title, headline, sub, eyebrow=None, brand=False,
         centered=False, window_width=2260):
    if centered:
        caption_pos = "top:140px; left:0; right:0; text-align:center;"
        window_pos = "left:50%; transform:translateX(-50%); top:700px;"
        headline_max, headline_size = 2200, 112
        sub_extra = "margin:0 auto;"
    else:
        caption_pos = "top:200px; left:200px;"
        window_pos = "right:-140px; bottom:-140px;"
        headline_max, headline_size = 1500, 104
        sub_extra = ""
    html = TEMPLATE.format(
        **tokens,
        caption_pos=caption_pos, window_pos=window_pos,
        headline=headline, sub=sub, image=image, doc_title=doc_title,
        headline_max=headline_max, headline_size=headline_size,
        window_width=window_width,
        eyebrow=f'<p class="eyebrow">{eyebrow}</p>' if eyebrow else "",
        brand='<div class="brand"><img src="icon.png"><span>Marginal</span></div>' if brand else "",
    )
    if centered:
        html = html.replace('class="sub"', f'class="sub" style="{sub_extra}"')
    with open(name, "w") as f:
        f.write(html)

shot("shot-01.html", LIGHT, "as-hero.png", "on-margins.md", brand=True, centered=True,
     headline="Markdown that reads the way it renders.",
     sub="A native macOS editor for plain .md files — no preview pane, no syntax soup.",
     window_width=2100)

shot("shot-02.html", LIGHT, "as-reveal.png", "on-margins.md", eyebrow="**",
     headline="The syntax hides itself.",
     sub="Markers reveal at your cursor and fade back into the typography when you leave.")

shot("shot-03.html", LIGHT, "as-tasks.png", "today.md", eyebrow="- [x]",
     headline="Tasks you can click.",
     sub="Click a checkbox to check it off. Done items strike themselves through. Return continues the list.")

shot("shot-04.html", LIGHT, "as-tables.png", "release-checklist.md", eyebrow="```",
     headline="Beautiful by default.",
     sub="Real table grids, rounded code cards with highlighting — carefully crafted for readability.")

shot("shot-05.html", DARK, "as-hero-dark.png", "on-margins.md", eyebrow="##",
     headline="Paper by day, ink by night.",
     sub="Marginal follows the system appearance — the same warm typography in both.")

shot("shot-06.html", LIGHT, "as-chrome.png", "chapter-two.md", eyebrow="L 3 · C 36",
     headline="Always know where you are.",
     sub="A quiet line number in the margin, and the markdown context at your cursor in the status bar.")

print("generated 6 shots")
