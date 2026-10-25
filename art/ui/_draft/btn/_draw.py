# -*- coding: utf-8 -*-
"""彩铅按钮贴图 v3：手绘方框（四角形态各异 + 边微起伏 + 收笔出头）+ 内衬细线 + 彩铅颗粒"""
import os, numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

BASE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(BASE, "_draw_log.txt")
lines = []
def P(*x):
    lines.append(" ".join(str(i) for i in x))

SS = 4
W, H = 512, 192
MARGIN = 14
PAPER = np.array([231, 217, 190], np.float32)
INK = np.array([89, 64, 34], np.float32)
INNER = np.array([146, 114, 74], np.float32)


def bez(p0, p1, p2, n):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2 = np.array(p0, float), np.array(p1, float), np.array(p2, float)
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


def arc(c, r, a0, a1, n):
    a = np.linspace(a0, a1, n)[:, None]
    return np.hstack([c[0] + r * np.cos(a), c[1] + r * np.sin(a)])


def hand_rect(x0, y0, x1, y1, corners, bul):
    """corners = ((kind,size) × 4) 顺序 TL,TR,BR,BL；kind 0=圆角 1=切角
       bul = (上,右,下,左) 向内凹的幅度"""
    (kTL, sTL), (kTR, sTR), (kBR, sBR), (kBL, sBL) = corners
    bT, bR, bB, bL = bul
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    segs = [bez((x0 + sTL, y0), (mx, y0 + 2 * bT), (x1 - sTR, y0), 46)]
    if kTR == 0:
        segs.append(arc((x1 - sTR, y0 + sTR), sTR, -np.pi / 2, 0, 16))
    else:
        segs.append(np.array([[x1 - sTR, y0], [x1, y0 + sTR]], float))
    segs.append(bez((x1, y0 + sTR), (x1 - 2 * bR, my), (x1, y1 - sBR), 46))
    if kBR == 0:
        segs.append(arc((x1 - sBR, y1 - sBR), sBR, 0, np.pi / 2, 16))
    else:
        segs.append(np.array([[x1, y1 - sBR], [x1 - sBR, y1]], float))
    segs.append(bez((x1 - sBR, y1), (mx, y1 - 2 * bB), (x0 + sBL, y1), 46))
    if kBL == 0:
        segs.append(arc((x0 + sBL, y1 - sBL), sBL, np.pi / 2, np.pi, 16))
    else:
        segs.append(np.array([[x0 + sBL, y1], [x0, y1 - sBL]], float))
    segs.append(bez((x0, y1 - sBL), (x0 + 2 * bL, my), (x0, y0 + sTL), 46))
    if kTL == 0:
        segs.append(arc((x0 + sTL, y0 + sTL), sTL, np.pi, np.pi * 1.5, 16))
    else:
        segs.append(np.array([[x0, y0 + sTL], [x0 + sTL, y0]], float))
    return np.vstack(segs)


def jitter(pts, amp, seed):
    rng = np.random.default_rng(seed)
    n = len(pts)
    s = np.linspace(0, 2 * np.pi, n)
    dx = amp * (0.6 * np.sin(3.1 * s + rng.uniform(0, 6)) + 0.4 * np.sin(7.9 * s + rng.uniform(0, 6)))
    dy = amp * (0.6 * np.sin(2.7 * s + rng.uniform(0, 6)) + 0.4 * np.sin(6.3 * s + rng.uniform(0, 6)))
    return pts + np.stack([dx, dy], 1)


def draw_hand_line(d, pts, base_w, col, seed, w_amp=0.42, dark=0.20):
    rng = np.random.default_rng(seed)
    n = len(pts)
    s = np.linspace(0, 2 * np.pi, n)
    press = 0.5 + 0.35 * np.sin(2.6 * s + rng.uniform(0, 6)) + 0.15 * np.sin(9.4 * s + rng.uniform(0, 6))
    press = np.clip(press, 0.0, 1.0)
    for i in range(n - 1):
        w = base_w * (1 - w_amp) + base_w * w_amp * 2 * press[i]
        c = tuple(int(v * (1 - dark * (1 - press[i]))) for v in col)
        a = (float(pts[i][0] * SS), float(pts[i][1] * SS))
        b = (float(pts[i + 1][0] * SS), float(pts[i + 1][1] * SS))
        d.line([a, b], fill=c, width=max(1, int(round(w * SS))))
        r = max(1.0, w * SS / 2)
        for p in (a, b):
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=c)


def build():
    rng = np.random.default_rng(7)
    ox, oy = 4.0, 4.0
    x0, y0, x1, y1 = ox, oy, W - ox, H - oy
    corners = ((0, 9.0), (0, 4.0), (1, 9.0), (0, 6.0))
    bul = (2.2, 1.8, 1.9, 1.6)

    base = hand_rect(x0, y0, x1, y1, corners, bul)
    outer = jitter(base, 0.7, 11)

    k = 7.0
    ic = ((0, 6.0), (0, 2.0), (1, 6.0), (0, 3.0))
    ibase = hand_rect(x0 + k, y0 + k, x1 - k, y1 - k, ic, bul)
    inner = jitter(ibase, 0.75, 23)

    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    v = base - np.array([cx, cy])
    v = v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-6) * 2.0
    fill_pts = base + v

    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d0 = ImageDraw.Draw(img)
    d0.polygon([tuple(p * SS) for p in fill_pts], fill=(int(PAPER[0]), int(PAPER[1]), int(PAPER[2]), 255))

    d = ImageDraw.Draw(img)
    draw_hand_line(d, inner, 0.78, INNER, 31)
    draw_hand_line(d, outer, 1.7, INK, 47)

    arr = np.asarray(img).astype(np.float32)

    alpha = arr[:, :, 3] / 255.0
    halo = np.clip(ndimage.gaussian_filter(alpha, 4.0) - alpha, 0, 1) * 0.30
    arr[:, :, 3] = np.clip(arr[:, :, 3] + halo * 255, 0, 255)

    paper_m = arr[:, :, 3] > 0
    nz = rng.normal(0.0, 1.6, (H * SS, W * SS, 1))
    arr[:, :, :3] = np.clip(arr[:, :, :3] + nz * paper_m[:, :, None], 0, 255)

    ink_m = (arr[:, :, :3].mean(2) < 168) & (arr[:, :, 3] > 120)
    grit = ink_m & (rng.random(ink_m.shape) < 0.26)
    for ch, v in enumerate(PAPER):
        arr[grit, ch] = v
    arr[grit, 3] = 255
    P("颗粒像素占线条 = %.1f%%" % (100.0 * grit.sum() / max(1, ink_m.sum())))

    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    tex = img.resize((W, H), Image.LANCZOS)
    tex.save(os.path.join(BASE, "btn_pencil_v4.png"))
    P("已存 btn_pencil_v4.png")

    ta = np.asarray(tex)
    P("不透明占比 = %.2f%%" % (100.0 * (ta[:, :, 3] > 0).mean()))
    c = ta[MARGIN + 4:H - MARGIN - 4, MARGIN + 4:W - MARGIN - 4, :3].astype(np.float32)
    L = 0.299 * c[:, :, 0] + 0.587 * c[:, :, 1] + 0.114 * c[:, :, 2]
    P("中心区 亮度均值 %.2f 标准差 %.2f" % (L.mean(), L.std()))
    return tex


def nine_slice(src, w, h, m):
    tw, th = src.size
    if w < 2 * m or h < 2 * m:
        return None, "溢出: 角块%d×2=%d > 短边%d" % (m, 2 * m, min(w, h))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, chh = w - 2 * m, h - 2 * m
    spec = [
        (0, 0, m, m, 0, 0), (m, 0, tw - m, m, m, 0), (tw - m, 0, tw, m, w - m, 0),
        (0, m, m, th - m, 0, m), (m, m, tw - m, th - m, m, m), (tw - m, m, tw, th - m, w - m, m),
        (0, th - m, m, th, 0, h - m), (m, th - m, tw - m, th, m, h - m), (tw - m, th - m, tw, th, w - m, h - m),
    ]
    for sx0, sy0, sx1, sy1, dx, dy in spec:
        dw = m if dx in (0, w - m) else cw
        dh = m if dy in (0, h - m) else chh
        c = src.crop((sx0, sy0, sx1, sy1)).resize((max(1, dw), max(1, dh)), Image.LANCZOS)
        out.paste(c, (dx, dy))
    return out, "OK"


tex = build()
FONT = r"C:\Windows\Fonts\msyh.ttc"
f13 = ImageFont.truetype(FONT, 13)
f15 = ImageFont.truetype(FONT, 15)
f22 = ImageFont.truetype(FONT, 22)
BG = (216, 210, 196, 255)

PW, PH = 1180, 1000
prev = Image.new("RGBA", (PW, PH), BG)
d = ImageDraw.Draw(prev)
d.text((30, 16), "彩铅按钮 v4 · 纸片铺满贴图(角块能切到角) + 四角形态各异 + 彩铅颗粒   margin=%d" % MARGIN,
       font=f22, fill=(40, 34, 26, 255))

d.text((30, 56), "① 贴图 512x192（2x 放大；黄线 = 九宫格切分线）", font=f15, fill=(70, 60, 48, 255))
big = tex.resize((W * 2, H * 2), Image.LANCZOS)
prev.paste(big, (30, 78), big)
for gx in (MARGIN, W - MARGIN):
    d.line([30 + gx * 2, 78, 30 + gx * 2, 78 + H * 2], fill=(200, 150, 40, 200), width=1)
for gy in (MARGIN, H - MARGIN):
    d.line([30, 78 + gy * 2, 30 + W * 2, 78 + gy * 2], fill=(200, 150, 40, 200), width=1)

d.text((30, 486), "② 三档真实尺寸 1:1", font=f15, fill=(70, 60, 48, 255))
CASES = [("继续游戏", 393, 99, 40), ("下一天", 176, 84, 22), ("人物", 84, 28, 14)]
y = 514
for name, w, h, fs in CASES:
    img, st = nine_slice(tex, w, h, MARGIN)
    if img is None:
        img, st = nine_slice(tex, w, h, 6)
    prev.paste(img, (30, y), img)
    d.rectangle([29, y - 1, 30 + w, y + h], outline=(180, 60, 60, 255))
    d.text((30 + w + 14, y + h // 2 - 16), "%s  %dx%d" % (name, w, h), font=f13, fill=(40, 34, 26, 255))
    d.text((30 + w + 14, y + h // 2 + 4), st, font=f13,
           fill=(50, 110, 60, 255) if st == "OK" else (150, 40, 40, 255))
    y += h + 26

d.text((640, 486), "③ 现状 vs 新设计（装真文字）", font=f15, fill=(70, 60, 48, 255))
Y0 = 514
for name, w, h, fs in CASES:
    flat = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flat)
    fd.rounded_rectangle([0, 0, w - 1, h - 1], radius=3, fill=(219, 219, 219, 255),
                         outline=(150, 150, 150, 255), width=1)
    prev.paste(flat, (640, Y0), flat)
    fnt = ImageFont.truetype(FONT, min(fs, 22))
    d.text((640 + w / 2, Y0 + h / 2), name, font=fnt, fill=(30, 28, 26, 255), anchor="mm")
    nb, _ = nine_slice(tex, w, h, MARGIN)
    if nb is not None:
        prev.paste(nb, (640, Y0 + h + 8), nb)
        d.text((640 + w / 2, Y0 + h + 8 + h / 2), name, font=fnt, fill=(38, 29, 18, 255), anchor="mm")
    Y0 += h * 2 + 34

prev.convert("RGB").save(os.path.join(BASE, "_preview_v4.png"))
P("已存 _preview_v4.png")
open(LOG, "w", encoding="utf-8").write("\n".join(lines))
