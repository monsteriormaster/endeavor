# -*- coding: utf-8 -*-
"""苏丹面板「左栏」单独裁出来 2x + 50px 网格（读分区 y 坐标用）。

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_sudan_left.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
im = Image.open(os.path.join(REF, "sudan", "sudan_ss06.jpg")).convert("RGB")


def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


for tag, BOX, SC in (("左栏", (376, 186, 1336, 886), 2), ("顶部", (376, 186, 1680, 470), 2)):
    c = im.crop(BOX).resize(((BOX[2] - BOX[0]) * SC, (BOX[3] - BOX[1]) * SC), Image.LANCZOS)
    d = ImageDraw.Draw(c)
    f = font(20)
    for xs in range(BOX[0] // 50 * 50, BOX[2] + 1, 50):
        X = (xs - BOX[0]) * SC
        if X < 0:
            continue
        maj = xs % 100 == 0
        d.line([X, 0, X, c.size[1]], fill=(255, 70, 70) if maj else (255, 165, 165), width=2 if maj else 1)
        if maj:
            d.text((X + 4, 6), str(xs), font=f, fill=(255, 245, 130))
    for ys in range(BOX[1] // 50 * 50, BOX[3] + 1, 50):
        Y = (ys - BOX[1]) * SC
        if Y < 0:
            continue
        maj = ys % 100 == 0
        d.line([0, Y, c.size[0], Y], fill=(70, 190, 255) if maj else (170, 215, 255), width=2 if maj else 1)
        d.text((4, Y + 4), str(ys), font=f, fill=(255, 245, 130))
    out = os.path.join(REF, "sudan_网格_%s.png" % tag)
    c.save(out)
    print("写出", out, c.size)
