# -*- coding: utf-8 -*-
"""处理新卡框（A 暗匣 / B 同族）+ 剖面测量 + 装真内容出"一屏真图"。"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
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
    cx, cy = (x0+x1)/2.0, (y0+y1)/2.0
    if cw/ch < TARGET: nw, nh = int(round(ch*TARGET)), ch
    else:              nw, nh = cw, int(round(cw/TARGET))
    nx0 = max(0, min(int(round(cx-nw/2.0)), clean.size[0]-nw))
    ny0 = max(0, min(int(round(cy-nh/2.0)), clean.size[1]-nh))
    card = clean.crop((nx0, ny0, nx0+nw, ny0+nh))
    card.save(out)
    print("%s src=%dx%d bg=%s card=%dx%d ar=%.3f -> norm %dx%d ar=%.4f"
          % (tag, W, H, bg, cw, ch, cw/ch, card.size[0], card.size[1], card.size[0]/card.size[1]))
    return card

def profile(card, tag):
    """逐行均值，找分带（窗 / 分隔线 / 铭牌）"""
    px = card.load(); w, h = card.size
    print("  [%s] 行均值剖面（每 5%%）:" % tag)
    for i in range(0, 21):
        p = min(100, i*5)
        y = min(h-1, int(h*p/100))
        r = g = b = 0
        for x in range(0, w, 2):
            c = px[x, y]; r += c[0]; g += c[1]; b += c[2]
        n = len(range(0, w, 2))
        print("    y=%3d%%  RGB=(%3d,%3d,%3d)  L=%3d" % (p, r//n, g//n, b//n, int(0.299*(r//n)+0.587*(g//n)+0.114*(b//n))))

A = process(os.path.join(DRAW, "A_single_vertical_collectible__2026-09-27T13-18-34.png"),
            os.path.join(BASE, "卡框_A_暗匣_v1.png"), "A_暗匣")
B = process(os.path.join(DRAW, "A_single_vertical_collectible__2026-09-27T13-18-59.png"),
            os.path.join(BASE, "卡框_B_同族_v1.png"), "B_同族")
profile(A, "A"); profile(B, "B")
