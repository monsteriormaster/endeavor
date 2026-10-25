# -*- coding: utf-8 -*-
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_panel\ali_0402.png"
OUT = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_放大_装备形态.png"

def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    return ImageFont.load_default()

im = Image.open(SRC).convert("RGB")
print("src", im.size)

items = [
    ("手牌行 3x", (250, 815, 880, 1000), 3),
    ("手牌行 5x 左半", (270, 820, 590, 990), 5),
    ("手牌行 5x 右半", (560, 820, 880, 990), 5),
    ("左侧资源条 5x", (100, 820, 250, 1000), 5),
    ("右侧转盘 2.5x", (880, 430, 1080, 1080), 2.5),
]
blocks = []
for name, box, sc in items:
    c = im.crop(box)
    r = c.resize((int(c.size[0] * sc), int(c.size[1] * sc)), Image.LANCZOS)
    blocks.append((name, r))

PAD = 12
LABEL = 32
W = max(b.size[0] for _, b in blocks) + PAD * 2
H = sum(b.size[1] + LABEL + PAD for _, b in blocks) + PAD
sheet = Image.new("RGB", (W, H), (24, 22, 20))
d = ImageDraw.Draw(sheet)
f = font(22)
y = PAD
for name, b in blocks:
    d.text((PAD, y + 4), name, font=f, fill=(255, 226, 150))
    y += LABEL
    sheet.paste(b, (PAD, y))
    y += b.size[1] + PAD
sheet.save(OUT)
print("saved", OUT, sheet.size)
