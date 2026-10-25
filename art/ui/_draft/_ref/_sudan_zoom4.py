# -*- coding: utf-8 -*-
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan\sudan_ss06.jpg"
OUT = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_放大_人物面板2.png"

def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    return ImageFont.load_default()

im = Image.open(SRC).convert("RGB")
items = [
    ("ss06 面板全区 3x", (620, 140, 1100, 460), 3),
    ("ss06 面板右半 5x", (860, 140, 1100, 460), 5),
]
blocks = []
for name, box, sc in items:
    c = im.crop(box)
    blocks.append((name, c.resize((int(c.size[0] * sc), int(c.size[1] * sc)), Image.LANCZOS)))

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
