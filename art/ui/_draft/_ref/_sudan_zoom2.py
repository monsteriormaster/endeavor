# -*- coding: utf-8 -*-
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan"
OUT = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_放大_人物面板.png"

def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    return ImageFont.load_default()

items = []
# ss06：人物信息面板（左半）+ 底部卡带
im6 = Image.open(os.path.join(SRC, "sudan_ss06.jpg")).convert("RGB")
items.append(("ss06 面板区 3x", im6.crop((340, 90, 980, 420)), 3))
items.append(("ss06 卡带 4x", im6.crop((140, 840, 900, 990)), 4))
# ss02：场上卡牌（可能带装备）
im2 = Image.open(os.path.join(SRC, "sudan_ss02.jpg")).convert("RGB")
items.append(("ss02 场上卡 3x", im2.crop((420, 240, 800, 640)), 3))
# ss03：场上卡
im3 = Image.open(os.path.join(SRC, "sudan_ss03.jpg")).convert("RGB")
items.append(("ss03 场上卡 3x", im3.crop((240, 190, 560, 560)), 3))

PAD = 12
LABEL = 34
blocks = []
for name, c, sc in items:
    r = c.resize((int(c.size[0] * sc), int(c.size[1] * sc)), Image.LANCZOS)
    blocks.append((name, r))

W = max(b.size[0] for _, b in blocks) + PAD * 2
H = sum(b.size[1] + LABEL + PAD for _, b in blocks) + PAD
sheet = Image.new("RGB", (W, H), (26, 24, 22))
d = ImageDraw.Draw(sheet)
f = font(24)
y = PAD
for name, b in blocks:
    d.text((PAD, y + 4), name, font=f, fill=(255, 226, 150))
    y += LABEL
    sheet.paste(b, (PAD, y))
    y += b.size[1] + PAD
sheet.save(OUT)
print("saved", OUT, sheet.size)
