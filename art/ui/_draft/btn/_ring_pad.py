# -*- coding: utf-8 -*-
"""椭圆圈的三档 padding：pad 越大圈越圆（角上切得越少），但会挤到相邻按钮的间距。"""
import os, math
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(BASE, "btn_pencil_v5.png")
MARGIN = 14
W, H = 393, 99
SEG = 96
GRAPHITE = (92, 69, 52)
# 真机屏幕：按钮上下间距 57px（scene/loading.tscn 实测）
GAP = 57.0


def nine_slice(src, w, h, m):
    tw, th = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, ch = max(1, w - 2 * m), max(1, h - 2 * m)
    spec = [(0, 0, m, m, 0, 0), (m, 0, tw - m, m, m, 0), (tw - m, 0, tw, m, w - m, 0),
            (0, m, m, th - m, 0, m), (m, m, tw - m, th - m, m, m), (tw - m, m, tw, th - m, w - m, m),
            (0, th - m, m, th, 0, h - m), (m, th - m, tw - m, th, m, h - m),
            (tw - m, th - m, tw, th, w - m, h - m)]
    for sx0, sy0, sx1, sy1, dx, dy in spec:
        dw = m if dx in (0, w - m) else cw
        dh = m if dy in (0, h - m) else ch
        c = src.crop((sx0, sy0, sx1, sy1)).resize((max(1, dw), max(1, dh)), Image.LANCZOS)
        out.paste(c, (dx, dy))
    return out


def ring_pts(pad_x, pad_y):
    rx, ry = W / 2 + pad_x, H / 2 + pad_y
    pts = []
    start = -math.pi * 0.66
    span = math.tau * 1.09
    for i in range(SEG + 1):
        u = i / SEG
        t = start + span * u
        wx = 1.0 + 0.030 * math.sin(t * 3.0 + 0.7) + 0.018 * math.sin(t * 5.0 - 1.9)
        wy = 1.0 + 0.050 * math.sin(t * 2.7 + 2.3) + 0.030 * math.sin(t * 6.3 - 0.4)
        flick = 1.0 + 0.07 * max(0.0, (u - 0.88) / 0.12) ** 2
        pts.append((math.cos(t) * rx * wx * flick, math.sin(t) * ry * wy * flick))
    return pts


def draw_ring(img, pts, cx, cy):
    d = ImageDraw.Draw(img, "RGBA")
    n = len(pts)
    for i in range(n - 1):
        u = i / (n - 1)
        press = 0.22 if u < 0.05 else (1.0 if u < 0.86 else (0.92 - 3.0 * (u - 0.86)))
        w = 3.0 * max(0.10, press)
        ax, ay = cx + pts[i][0], cy + pts[i][1]
        bx, by = cx + pts[i + 1][0], cy + pts[i + 1][1]
        d.line([ax, ay, bx, by], fill=GRAPHITE + (255,), width=max(1, int(round(w))))
        r = w / 2
        for px, py in ((ax, ay), (bx, by)):
            d.ellipse([px - r, py - r, px + r, py + r], fill=GRAPHITE + (255,))


src = Image.open(TEX).convert("RGBA")
btn = nine_slice(src, W, H, MARGIN)
BG = (214, 208, 194)
FONT = r"C:\Windows\Fonts\msyh.ttc"
f14 = ImageFont.truetype(FONT, 14)
f20 = ImageFont.truetype(FONT, 20)

VARIANTS = [(9.0, 9.0), (10.0, 16.0), (12.0, 26.0)]
CELL_H = 170
PW, PH = 1000, 60 + len(VARIANTS) * CELL_H + 10
prev = Image.new("RGB", (PW, PH), BG)
d = ImageDraw.Draw(prev)
d.text((20, 16), "椭圆圈 padding 三档（按钮 393x99 1:1，上下真机间距 57px）", font=f20, fill=(38, 32, 24))

log = []
for k, (px_, py_) in enumerate(VARIANTS):
    y = 60 + k * CELL_H
    canvas = Image.new("RGBA", (1000, 160), (214, 208, 194, 255))
    # 画三个按钮，展示「圈会不会挤到邻居」
    for j, yy in enumerate((10, 10 + H + int(GAP), 10 + 2 * (H + int(GAP)))):
        canvas.paste(btn, (20, int(yy)), btn)
    cx, cy = 20 + W / 2, 10 + H / 2
    pts = ring_pts(px_, py_)
    draw_ring(canvas, pts, cx, cy)
    prev.paste(canvas.convert("RGB"), (0, y))
    inside = sum(1 for x, yv in pts if abs(x) < W / 2 and abs(yv) < H / 2) / len(pts)
    over_y = max(abs(q[1]) for q in pts) - H / 2
    clear = GAP - over_y
    log.append("pad=(%.0f,%.0f)  圈高 %.0fpx  上下各溢出 %.1fpx  与邻居净空 %.1fpx  切进按钮 %.0f%% 的点"
               % (px_, py_, 2 * max(abs(q[1]) for q in pts), over_y, clear, inside * 100))
    d.text((20 + W + 50, y + 20), "pad = (%.0f, %.0f)" % (px_, py_), font=f20, fill=(45, 38, 28))
    d.text((20 + W + 50, y + 52),
           "圈 %.0fx%.0fpx（按钮 %.0fx%.0f）" % (2 * max(abs(q[0]) for q in pts), 2 * max(abs(q[1]) for q in pts), W, H),
           font=f14, fill=(70, 60, 46))
    d.text((20 + W + 50, y + 72), "与邻居净空 %.1fpx" % clear, font=f14, fill=(70, 60, 46))
    d.text((20 + W + 50, y + 92), "切进按钮 %.0f%% 的点" % (inside * 100), font=f14, fill=(70, 60, 46))

out = os.path.join(BASE, "_ring_pad_pick.png")
prev.save(out)
open(os.path.join(BASE, "_ring_pad_pick.txt"), "w", encoding="utf-8").write(
    "已存 " + out + "\n" + "\n".join(log) + "\n")
