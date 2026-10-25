# -*- coding: utf-8 -*-
"""把一张真实卡裁出来 + 叠百分比标尺，用于读分带比例。"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
OUTD = os.path.join(BASE, "ruler")
os.makedirs(OUTD, exist_ok=True)

def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

def ruler(rel, box, out, sc=3.0):
    im = Image.open(os.path.join(BASE, rel)).convert("RGB")
    c = im.crop(box)
    w, h = c.size
    c = c.resize((int(w*sc), int(h*sc)), Image.LANCZOS)
    C = c.size
    pad = 78
    canvas = Image.new("RGB", (C[0]+pad, C[1]+pad), (245,243,240))
    canvas.paste(c, (pad, 0))
    d = ImageDraw.Draw(canvas)
    f = font(17)
    for p in range(0, 101, 5):
        y = int(C[1]*p/100)
        d.line([(pad-8, y), (pad, y)], fill=(200,60,50), width=2)
        if p % 10 == 0:
            d.text((4, min(max(0, y-9), C[1]-16)), "%d%%" % p, fill=(180,50,40), font=f)
    for p in range(0, 101, 10):
        x = pad + int(C[0]*p/100)
        d.line([(x, 0), (x, 6)], fill=(40,90,190), width=2)
        d.text((x-12, C[1]+6), "%d" % p, fill=(40,90,190), font=f)
    canvas.save(os.path.join(OUTD, out))
    print("%-28s crop=(%d,%d)-(%d,%d) %dx%d ar=%.3f -> %dx%d" %
          (out, box[0], box[1], box[2], box[3], w, h, w/h, canvas.size[0], canvas.size[1]))

ruler("sudan/sudan_ss06.jpg", (60, 700, 200, 900), "r_sudan.png", 3.4)
ruler("yueyuan/yueyuan_ss01.jpg", (755, 655, 900, 1080), "r_yueyuan.png", 2.6)
ruler("wangzhe/wxq_17.png", (2, 2, 200, 255), "r_wangzhe.png", 3.4)
ruler("morimens/morimens_ss03.jpg", (413, 855, 495, 1080), "r_morimens.png", 5.0)
