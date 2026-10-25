# -*- coding: utf-8 -*-
import os
from PIL import Image, ImageDraw, ImageFont

REF = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"

def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\msyhbd.ttc"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

blocks = []
for tag, box in (("A", (36, 248, 366, 348)), ("B", (36, 248, 366, 348))):
    p = os.path.join(REF, "面板R1改_装备槽_状态%s_1x.png" % tag)
    im = Image.open(p).convert("RGB")
    c = im.crop(box)
    c = c.resize((c.size[0] * 3, c.size[1] * 3), Image.LANCZOS)
    blocks.append(("状态%s 装备行 3x" % tag, c))

# 单独看四个图标原始样子
D = r"c:\Users\26464\IdeaProjects\endeavor\art\items"
ic = []
for n in ("多功能军刀", "骑士盔甲", "章鱼尾人身塑像", "越狱工具"):
    i = Image.open(os.path.join(D, n + ".png")).convert("RGBA")
    i.thumbnail((150, 150), Image.LANCZOS)
    bg = Image.new("RGB", i.size, (231, 222, 202))
    bg.paste(i.convert("RGB"), (0, 0), i.split()[-1])
    ic.append((n, bg))

PAD, LAB = 10, 26
W = max([b.size[0] for _, b in blocks] + [sum(i.size[0] + 8 for _, i in ic) + 8]) + PAD * 2
H = PAD + sum(b.size[1] + LAB + PAD for _, b in blocks) + 150 + LAB + PAD * 2
sh = Image.new("RGB", (W, H), (28, 26, 24))
d = ImageDraw.Draw(sh)
f = font(20)
y = PAD
for nm, b in blocks:
    d.text((PAD, y + 2), nm, font=f, fill=(255, 226, 150))
    y += LAB
    sh.paste(b, (PAD, y))
    y += b.size[1] + PAD
d.text((PAD, y + 2), "四个图标原始形态（贴在同色底上，150px 内）", font=f, fill=(255, 226, 150))
y += LAB
x = PAD
for nm, i in ic:
    sh.paste(i, (x, y))
    d.text((x, y + i.size[1] + 2), nm, font=font(14), fill=(220, 210, 190))
    x += i.size[0] + 8
sh.save(os.path.join(REF, "面板R1改_装备行_放大.png"))
print("saved", sh.size)
