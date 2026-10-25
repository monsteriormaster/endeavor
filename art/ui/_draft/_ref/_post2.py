# -*- coding: utf-8 -*-
"""处理 v2 + 生成 三联对比：原图 | v1 | v2"""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
DRAW = os.path.join(BASE, "draw")
WM_H = 82
TARGET = 90 / 159.0

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

def bg_of(im):
    px = im.load(); w, _ = im.size
    r = g = b = n = 0
    for y in range(0, 8):
        for x in range(0, w, 4):
            c = px[x, y]; r += c[0]; g += c[1]; b += c[2]; n += 1
    return (r//n, g//n, b//n)

def bbox(im, thr=20):
    w, h = im.size; bg = bg_of(im); px = im.load()
    x0, y0, x1, y1 = w, h, -1, -1
    wx, wy = int(w*0.82), int(h*0.85)
    for y in range(0, h):
        for x in range(0, w):
            if x > wx and y > wy: continue
            c = px[x, y]
            if abs(c[0]-bg[0]) + abs(c[1]-bg[1]) + abs(c[2]-bg[2]) > thr*3:
                if x < x0: x0 = x
                if y < y0: y0 = y
                if x > x1: x1 = x
                if y > y1: y1 = y
    return (x0, y0, x1, y1), bg

def process(src, out, tag):
    im = Image.open(src).convert("RGB")
    W, H = im.size
    clean = im.crop((0, 0, W, H - WM_H))
    (x0, y0, x1, y1), bg = bbox(clean)
    cw, ch = x1-x0+1, y1-y0+1
    print("%s src=%dx%d bg=%s card=%dx%d ar=%.3f" % (tag, W, H, bg, cw, ch, cw/ch))
    cx, cy = (x0+x1)/2.0, (y0+y1)/2.0
    if cw/ch < TARGET:
        nw, nh = int(round(ch*TARGET)), ch
    else:
        nw, nh = cw, int(round(cw/TARGET))
    nx0 = max(0, min(int(round(cx-nw/2.0)), clean.size[0]-nw))
    ny0 = max(0, min(int(round(cy-nh/2.0)), clean.size[1]-nh))
    card = clean.crop((nx0, ny0, nx0+nw, ny0+nh))
    hh = 954
    card = card.resize((int(round(hh*TARGET)), hh), Image.LANCZOS)
    card.save(out)
    print("   -> %s %dx%d" % (out, card.size[0], card.size[1]))
    return card

v1 = process(os.path.join(DRAW, "A_single_vertical_collectible__2026-09-26T17-34-30.png"),
             os.path.join(BASE, "卡面_月圆之夜_v1.png"), "v1")
v2 = process(os.path.join(DRAW, "A_single_vertical_collectible__2026-09-26T17-35-28.png"),
             os.path.join(BASE, "卡面_月圆之夜_v2.png"), "v2")

# 原图三张参照
ref = Image.open(os.path.join(BASE, "yueyuan", "yueyuan_ss04.jpg")).convert("RGB")
refc = ref.crop((706, 806, 936, 1080))
CH = 954
refc = refc.resize((int(round(refc.size[0]*CH/refc.size[1])), CH), Image.LANCZOS)

GAP, PAD, LAB = 40, 36, 76
panels = [("真实原图 · Steam 实机截图", "月圆之夜 手牌（底边被屏幕裁切）", refc),
          ("v1 · 对着原图", "偏差：边框画成奶白底、卡身偏墨绿", v1),
          ("v2 · 修正后", "黑底 + 奶白细内线 + 四角卷草", v2)]
wsum = sum(p[2].size[0] for p in panels) + GAP*(len(panels)-1)
sheet = Image.new("RGB", (PAD*2 + wsum, PAD*2 + LAB + CH), (242, 240, 236))
d = ImageDraw.Draw(sheet)
ft, fs = font(24, True), font(17)
x = PAD
for title, sub, img in panels:
    d.text((x, PAD), title, fill=(28,26,24), font=ft)
    d.text((x, PAD+34), sub, fill=(95,90,84), font=fs)
    sheet.paste(img, (x, PAD+LAB))
    x += img.size[0] + GAP
sheet.save(os.path.join(BASE, "对比_月圆之夜_三版.png"))
print("SAVED 对比_月圆之夜_三版.png", sheet.size)
