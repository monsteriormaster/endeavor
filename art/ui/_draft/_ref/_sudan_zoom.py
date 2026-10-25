# -*- coding: utf-8 -*-
# 放大官方截图：底部卡带 + 场景内卡牌，看清「装备/武器是怎么挂上去的」
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan"
OUT = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_放大_卡带.png"

def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    return ImageFont.load_default()

# ss00..ss06 底部卡带区域
crops = []
for i in range(7):
    p = os.path.join(SRC, "sudan_ss%02d.jpg" % i)
    if not os.path.exists(p):
        continue
    im = Image.open(p).convert("RGB")
    W, H = im.size
    # 底部卡带：y 从 0.78H 到 H
    box = (0, int(H * 0.76), W, H)
    c = im.crop(box)
    c = c.resize((c.size[0] * 2, c.size[1] * 2), Image.LANCZOS)
    crops.append(("ss%02d 底部卡带 2x" % i, c))

# ss02 / ss03 / ss06 场景中部（可能有卡牌在场上）
for i in (2, 3, 6):
    p = os.path.join(SRC, "sudan_ss%02d.jpg" % i)
    im = Image.open(p).convert("RGB")
    W, H = im.size
    box = (0, int(H * 0.10), int(W * 0.55), int(H * 0.78))
    c = im.crop(box)
    c = c.resize((int(c.size[0] * 1.5), int(c.size[1] * 1.5)), Image.LANCZOS)
    crops.append(("ss%02d 场中 1.5x" % i, c))

PAD = 10
LABEL = 30
W = max(c.size[0] for _, c in crops) + PAD * 2
H = sum(c.size[1] + LABEL + PAD for _, c in crops) + PAD
sheet = Image.new("RGB", (W, H), (30, 28, 26))
d = ImageDraw.Draw(sheet)
f = font(20)
y = PAD
for name, c in crops:
    d.text((PAD, y + 3), name, font=f, fill=(255, 220, 140))
    y += LABEL
    sheet.paste(c, (PAD, y))
    y += c.size[1] + PAD

sheet.save(OUT)
print("saved", OUT, sheet.size)
