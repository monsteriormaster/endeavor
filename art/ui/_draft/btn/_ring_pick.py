# -*- coding: utf-8 -*-
"""选「圈」的形状指数：按钮是 4:1 的宽矩形，纯椭圆(盒形指数 2)会切进按钮内部，
   和按钮自己的铅笔框交叉成一团。这里把各档指数渲出来直接看。"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(BASE, "btn_pencil_v5.png")
MARGIN = 14
W, H = 393, 99
PAD = 9.0
SEG = 96
GRAPHITE = (92, 69, 52)


def nine_slice(src, w, h, m):
    tw, th = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, ch = max(1, w - 2 * m), max(1, h - 2 * m)
    spec = [
        (0, 0, m, m, 0, 0), (m, 0, tw - m, m, m, 0), (tw - m, 0, tw, m, w - m, 0),
        (0, m, m, th - m, 0, m), (m, m, tw - m, th - m, m, m), (tw - m, m, tw, th - m, w - m, m),
        (0, th - m, m, th, 0, h - m), (m, th - m, tw - m, th, m, h - m), (tw - m, th - m, tw, th, w - m, h - m),
    ]
    for sx0, sy0, sx1, sy1, dx, dy in spec:
        dw = m if dx in (0, w - m) else cw
        dh = m if dy in (0, h - m) else ch
        c = src.crop((sx0, sy0, sx1, sy1)).resize((max(1, dw), max(1, dh)), Image.LANCZOS)
        out.paste(c, (dx, dy))
    return out


def ring_pts(p, rx, ry):
    """超椭圆参数化：|x/rx|^p + |y/ry|^p = 1 → (rx|cos|^(2/p), ry|sin|^(2/p))"""
    pts = []
    start = -math.pi * 0.66
    span = math.tau * 1.09
    a0 = 2.0 / p
    for i in range(SEG + 1):
        u = i / SEG
        t = start + span * u
        c, s = math.cos(t), math.sin(t)
        wx = 1.0 + 0.030 * math.sin(t * 3.0 + 0.7) + 0.018 * math.sin(t * 5.0 - 1.9)
        wy = 1.0 + 0.050 * math.sin(t * 2.7 + 2.3) + 0.030 * math.sin(t * 6.3 - 0.4)
        flick = 1.0 + 0.07 * max(0.0, (u - 0.88) / 0.12) ** 2
        x = math.copysign(abs(c) ** a0, c) * rx * wx * flick
        y = math.copysign(abs(s) ** a0, s) * ry * wy * flick
        pts.append((x, y))
    return pts


def draw_ring(img, pts, cx, cy):
    d = ImageDraw.Draw(img, "RGBA")
    n = len(pts)
    for i in range(n - 1):
        u = i / (n - 1)
        # 笔压：起笔轻 → 中段实 → 收笔细
        press = 0.22 if u < 0.05 else (1.0 if u < 0.86 else (0.92 - 3.0 * (u - 0.86)))
        w = 3.0 * max(0.10, press)
        ax, ay = cx + pts[i][0], cy + pts[i][1]
        bx, by = cx + pts[i + 1][0], cy + pts[i + 1][1]
        d.line([ax, ay, bx, by], fill=GRAPHITE + (255,), width=max(1, int(round(w))))
        r = w / 2
        for (px, py) in ((ax, ay), (bx, by)):
            d.ellipse([px - r, py - r, px + r, py + r], fill=GRAPHITE + (255,))


def outside_ratio(pts, rx0, ry0):
    """折线里落在按钮矩形**内部**的比例（0 = 全程在外面，越干净）"""
    inside = 0
    for x, y in pts:
        if abs(x) < rx0 and abs(y) < ry0:
            inside += 1
    return inside / len(pts)


src = Image.open(TEX).convert("RGBA")
btn = nine_slice(src, W, H, MARGIN)

BG = (214, 208, 194)
BG4 = (214, 208, 194, 255)
FONT = r"C:\Windows\Fonts\msyh.ttc"
f14 = ImageFont.truetype(FONT, 14)
f16 = ImageFont.truetype(FONT, 16)
f20 = ImageFont.truetype(FONT, 20)

XPS = [2.0, 3.0, 4.0, 6.0, 8.0, 12.0]
CELL_W, CELL_H = 900, 150
PW, PH = CELL_W + 40, 60 + len(XPS) * CELL_H + 20
prev = Image.new("RGB", (PW, PH), BG)
d = ImageDraw.Draw(prev)
d.text((20, 16), "圈形状指数 p 选择（p=2 是正椭圆，越大越贴矩形）   pad=%.0f  按钮 %dx%d  1:1" % (PAD, W, H),
       font=f20, fill=(38, 32, 24))

rx = W / 2 + PAD
ry = H / 2 + PAD
log = []
for k, p in enumerate(XPS):
    y = 60 + k * CELL_H
    canvas = Image.new("RGBA", (CELL_W, 120), BG4)
    cx, cy = W / 2 + 20, 60
    canvas.paste(btn, (20, 60 - H // 2), btn)
    pts = ring_pts(p, rx, ry)
    draw_ring(canvas, pts, cx, cy)
    prev.paste(canvas.convert("RGB"), (0, y))
    orat = outside_ratio(pts, W / 2, H / 2)
    tag = "← 干净" if orat == 0.0 else "切进按钮 %.0f%% 的点" % (orat * 100)
    log.append("p=%-5s 落在按钮内的点数占比 %5.1f%%  外接 %s" % (
        p, orat * 100,
        "(%.1f,%.1f)" % (max(abs(q[0]) for q in pts), max(abs(q[1]) for q in pts))))
    d.text((20 + W + 40, y + 50), "p=%g  %s" % (p, tag), font=f14, fill=(60, 50, 40))
    d.text((20 + W + 40, y + 70), "外扩 横%.1f / 纵%.1f px" % (
        max(abs(q[0]) for q in pts) - W / 2, max(abs(q[1]) for q in pts) - H / 2),
        font=f14, fill=(60, 50, 40))

out = os.path.join(BASE, "_ring_shape_pick.png")
prev.save(out)
open(os.path.join(BASE, "_ring_shape_pick.txt"), "w", encoding="utf-8").write(
    "已存 " + out + "\n" + "\n".join(log) + "\n")
