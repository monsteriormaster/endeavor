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
for tag in ("A", "B"):
    im = Image.open(os.path.join(REF, "面板R1改v2_状态%s_1x.png" % tag)).convert("RGB")
    c = im.crop((172, 4, 610, 100))
    blocks.append(("状态%s 槽行 4x" % tag, c.resize((c.size[0] * 4, c.size[1] * 4), Image.LANCZOS)))

# 量一下「章鱼尾人身塑像」在 10px 下的实际宽度（1x 单位）
f10 = font(10)
print("10px「章鱼尾人身塑像」宽度 =", f10.getlength("章鱼尾人身塑像"))
print("10px「多功能军刀」宽度   =", f10.getlength("多功能军刀"))
print("槽内可用宽 w-8 =", 78 - 8)

PAD, LAB = 10, 26
W = max(b.size[0] for _, b in blocks) + PAD * 2
H = sum(b.size[1] + LAB + PAD for _, b in blocks) + PAD
sh = Image.new("RGB", (W, H), (28, 26, 24))
d = ImageDraw.Draw(sh)
y = PAD
for nm, b in blocks:
    d.text((PAD, y + 2), nm, font=font(20), fill=(255, 226, 150))
    y += LAB
    sh.paste(b, (PAD, y))
    y += b.size[1] + PAD
sh.save(os.path.join(REF, "面板R1改v2_槽行_放大.png"))
print("saved", sh.size)
