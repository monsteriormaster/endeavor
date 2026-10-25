# -*- coding: utf-8 -*-
"""单卡特写 + 关键色采样。对着原图量数据，不靠印象。"""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
OUTD = os.path.join(BASE, "closeups")
os.makedirs(OUTD, exist_ok=True)

JOBS = [
    ("wangzhe/wxq_17.png", (2, 2, 200, 255), 5.0, "万象棋 单卡"),
    ("sudan/sudan_ss00.jpg", (52, 795, 148, 968), 6.0, "苏丹 单卡"),
    ("yueyuan/yueyuan_ss01.jpg", (760, 660, 900, 1080), 4.0, "月圆 单卡"),
    ("morimens/morimens_ss03.jpg", (415, 858, 495, 1080), 7.0, "忘却 单卡"),
]

def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

made = []
for i, (rel, box, sc, label) in enumerate(JOBS):
    p = os.path.join(BASE, rel)
    im = Image.open(p).convert("RGB")
    W, H = im.size
    x0, y0, x1, y1 = box
    c = im.crop((max(0,x0), max(0,y0), min(x1,W), min(y1,H)))
    w0, h0 = c.size
    c = c.resize((max(1,int(w0*sc)), max(1,int(h0*sc))), Image.LANCZOS)
    dst = os.path.join(OUTD, "single%02d.png" % i)
    c.save(dst)
    made.append((label, dst, (w0, h0)))
    print("%-14s 原裁 %dx%d  ar=%.3f  (放大 x%s)" % (label, w0, h0, w0/h0, sc))

CH, GAP, PAD, LAB, COLS = 460, 22, 26, 30, 4
CW = 220
sheet = Image.new("RGB", (PAD*2 + COLS*CW + (COLS-1)*GAP, PAD*2 + LAB + CH), (238,236,232))
d = ImageDraw.Draw(sheet); f = font(18)
for i, (label, path, sz) in enumerate(made):
    x = PAD + i*(CW+GAP); y = PAD
    th = Image.open(path)
    s = min(CH/th.size[1], CW/th.size[0])
    th = th.resize((max(1,int(th.size[0]*s)), max(1,int(th.size[1]*s))), Image.LANCZOS)
    d.text((x, y), "%s %dx%d" % (label, sz[0], sz[1]), fill=(30,28,26), font=f)
    sheet.paste(th, (x + (CW-th.size[0])//2, y + LAB))
sheet.save(os.path.join(BASE, "sheet_single_cards.png"))
print("SAVED sheet_single_cards.png", sheet.size)
