# -*- coding: utf-8 -*-
"""彩铅按钮 v5：叠加表 + 排线 + 出锋（彩铅的三样签名动作）
   技法：每一笔单独渲染成「覆盖度图」，累加后再一次性映射成颜色 —— 重叠处自然加深（叠色）。"""
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
INK = np.array([84, 60, 32], np.float32)
INNER = np.array([146, 114, 74], np.float32)


def bez(p0, p1, p2, n):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2 = np.array(p0, float), np.array(p1, float), np.array(p2, float)
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


def arc(c, r, a0, a1, n):
    a = np.linspace(a0, a1, n)[:, None]
    return np.hstack([c[0] + r * np.cos(a), c[1] + r * np.sin(a)])


def hand_rect(x0, y0, x1, y1, corners, bul):
    (kTL, sTL), (kTR, sTR), (kBR, sBR), (kBL, sBL) = corners
    bT, bR, bB, bL = bul
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2
    segs = [bez((x0 + sTL, y0), (mx, y0 + 2 * bT), (x1 - sTR, y0), 46)]
    segs.append(arc((x1 - sTR, y0 + sTR), sTR, -np.pi / 2, 0, 16) if kTR == 0
                else np.array([[x1 - sTR, y0], [x1, y0 + sTR]], float))
    segs.append(bez((x1, y0 + sTR), (x1 - 2 * bR, my), (x1, y1 - sBR), 46))
    segs.append(arc((x1 - sBR, y1 - sBR), sBR, 0, np.pi / 2, 16) if kBR == 0
                else np.array([[x1, y1 - sBR], [x1 - sBR, y1]], float))
    segs.append(bez((x1 - sBR, y1), (mx, y1 - 2 * bB), (x0 + sBL, y1), 46))
    segs.append(arc((x0 + sBL, y1 - sBL), sBL, np.pi / 2, np.pi, 16) if kBL == 0
                else np.array([[x0 + sBL, y1], [x0, y1 - sBL]], float))
    segs.append(bez((x0, y1 - sBL), (x0 + 2 * bL, my), (x0, y0 + sTL), 46))
    segs.append(arc((x0 + sTL, y0 + sTL), sTL, np.pi, np.pi * 1.5, 16) if kTL == 0
                else np.array([[x0, y0 + sTL], [x0 + sTL, y0]], float))
    return np.vstack(segs)


def jitter(pts, amp, seed):
    rng = np.random.default_rng(seed)
    n = len(pts)
    s = np.linspace(0, 2 * np.pi, n)
    dx = amp * (0.6 * np.sin(3.1 * s + rng.uniform(0, 6)) + 0.4 * np.sin(7.9 * s + rng.uniform(0, 6)))
    dy = amp * (0.6 * np.sin(2.7 * s + rng.uniform(0, 6)) + 0.4 * np.sin(6.3 * s + rng.uniform(0, 6)))
    return pts + np.stack([dx, dy], 1)


def stroke(pts, base_w, seed, size, w_amp=0.42, taper=0.0):
    """把一笔渲染成覆盖度图（0..1）。taper>0 时末尾该比例的点线宽渐细（出锋）"""
    rng = np.random.default_rng(seed)
    n = len(pts)
    s = np.linspace(0, 2 * np.pi, n)
    press = 0.5 + 0.35 * np.sin(2.6 * s + rng.uniform(0, 6)) + 0.15 * np.sin(9.4 * s + rng.uniform(0, 6))
    press = np.clip(press, 0.0, 1.0)
    if taper > 0:
        m = max(2, int(n * taper))
        press[n - m:] *= np.linspace(1.0, 0.10, m)
    layer = Image.new("L", size, 0)
    d = ImageDraw.Draw(layer)
    for i in range(n - 1):
        w = base_w * (1 - w_amp) + base_w * w_amp * 2 * press[i]
        a = (float(pts[i][0] * SS), float(pts[i][1] * SS))
        b = (float(pts[i + 1][0] * SS), float(pts[i + 1][1] * SS))
        d.line([a, b], fill=255, width=max(1, int(round(w * SS))))
        r = max(1.0, w * SS / 2)
        for p in (a, b):
            d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=255)
    return np.asarray(layer).astype(np.float32) / 255.0


def hatch_marks(size, corners_xy, n=3, length=7.0):
    """四角内部的斜向排线（特征④）。角块不缩放，所以这里的排线不会被拉伸"""
    layer = Image.new("L", size, 0)
    d = ImageDraw.Draw(layer)
    for (cx, cy, sx, sy) in corners_xy:
        for i in range(n):
            o = 2.0 + i * 2.6
            x0 = cx + sx * o
            y0 = cy + sy * (o + length)
            x1 = cx + sx * (o + length)
            y1 = cy + sy * o
            val = int(210 - i * 45)
            d.line([(x0 * SS, y0 * SS), (x1 * SS, y1 * SS)], fill=val, width=max(1, int(1.0 * SS)))
    return np.asarray(layer).astype(np.float32) / 255.0


def build():
    rng = np.random.default_rng(7)
    size = (W * SS, H * SS)
    ox, oy = 4.0, 4.0
    x0, y0, x1, y1 = ox, oy, W - ox, H - oy
    corners = ((0, 9.0), (0, 4.0), (1, 9.0), (0, 6.0))
    bul = (2.2, 1.8, 1.9, 1.6)

    base = hand_rect(x0, y0, x1, y1, corners, bul)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    v = base - np.array([cx, cy])
    v = v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-6) * 2.0
    fill_pts = base + v

    k = 7.0
    ic = ((0, 6.0), (0, 2.0), (1, 6.0), (0, 3.0))
    ibase = hand_rect(x0 + k, y0 + k, x1 - k, y1 - k, ic, bul)

    outer = jitter(base, 0.7, 11)
    outer = outer[:-9]
    outer2 = jitter(base, 0.7, 11)[:-9] + np.array([0.95, 0.75])
    inner = jitter(ibase, 0.75, 23)

    paper = Image.new("L", size, 0)
    ImageDraw.Draw(paper).polygon([tuple(p * SS) for p in fill_pts], fill=255)
    paper_mask = np.asarray(paper).astype(np.float32) / 255.0

    cov_ink = stroke(outer, 1.45, 47, size, taper=0.13)
    cov_ink += 0.42 * stroke(outer2, 0.92, 71, size, taper=0.13)
    cov_ink += 0.9 * hatch_marks(size, [
        (x0 + 1, y0 + 1, 1, 1),
        (x1 - 1, y0 + 1, -1, 1),
        (x1 - 1, y1 - 1, -1, -1),
        (x0 + 1, y1 - 1, 1, -1),
    ])
    cov_inner = stroke(inner, 0.72, 31, size)

    n = ndimage.gaussian_filter(rng.normal(0, 1, (size[1], size[0])), 1.6)
    n = (n - n.min()) / max(1e-6, (n.max() - n.min()))
    cov_ink *= (0.68 + 0.32 * n)
    cov_inner *= (0.80 + 0.20 * n)
    cov_ink = np.clip(cov_ink, 0, 1)
    cov_inner = np.clip(cov_inner, 0, 1)

    rgb = np.ones((size[1], size[0], 3), np.float32) * PAPER[None, None, :]
    rgb = rgb * (1 - cov_inner[:, :, None]) + INNER[None, None, :] * cov_inner[:, :, None]
    rgb = rgb * (1 - cov_ink[:, :, None]) + INK[None, None, :] * cov_ink[:, :, None]

    alpha = np.clip(np.maximum(paper_mask, cov_ink) * 255, 0, 255)
    base_m = alpha > 0
    nz = rng.normal(0.0, 1.7, (size[1], size[0], 1))
    rgb = np.clip(rgb + nz * base_m[:, :, None], 0, 255)

    tex = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA").resize((W, H), Image.LANCZOS)
    tex.save(os.path.join(BASE, "btn_pencil_v5.png"))
    P("已存 btn_pencil_v5.png")

    ta = np.asarray(tex)
    P("不透明占比 = %.2f%%" % (100.0 * (ta[:, :, 3] > 0).mean()))
    c = ta[MARGIN + 4:H - MARGIN - 4, MARGIN + 4:W - MARGIN - 4, :3].astype(np.float32)
    L = 0.299 * c[:, :, 0] + 0.587 * c[:, :, 1] + 0.114 * c[:, :, 2]
    P("中心区 亮度均值 %.2f 标准差 %.2f" % (L.mean(), L.std()))
    b = ta[:MARGIN, 0:MARGIN, :3].astype(np.float32)
    P("左上角块 均值 %.2f 标准差 %.2f" % (b.mean(), b.std()))
    return tex


def nine_slice(src, w, h, m):
    tw, th = src.size
    if w < 2 * m or h < 2 * m:
        return None, "溢出"
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, chh = max(1, w - 2 * m), max(1, h - 2 * m)
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


tex5 = build()
v4_path = os.path.join(BASE, "btn_pencil_v4.png")
tex4 = Image.open(v4_path).convert("RGBA") if os.path.exists(v4_path) else tex5

FONT = r"C:\Windows\Fonts\msyh.ttc"
f13 = ImageFont.truetype(FONT, 13)
f15 = ImageFont.truetype(FONT, 15)
f22 = ImageFont.truetype(FONT, 22)
BG = (216, 210, 196, 255)

PW, PH = 1180, 1060
prev = Image.new("RGBA", (PW, PH), BG)
d = ImageDraw.Draw(prev)
d.text((30, 16), "彩铅按钮 v5 · 加进「叠色 + 排线 + 出锋」三样签名动作   margin=%d" % MARGIN,
       font=f22, fill=(40, 34, 26, 255))

d.text((30, 56), "① v5 贴图 512x192（2x）", font=f15, fill=(70, 60, 48, 255))
big = tex5.resize((W * 2, H * 2), Image.LANCZOS)
prev.paste(big, (30, 78), big)
for gx in (MARGIN, W - MARGIN):
    d.line([30 + gx * 2, 78, 30 + gx * 2, 78 + H * 2], fill=(200, 150, 40, 200), width=1)
for gy in (MARGIN, H - MARGIN):
    d.line([30, 78 + gy * 2, 30 + W * 2, 78 + gy * 2], fill=(200, 150, 40, 200), width=1)

d.text((520, 486), "② 左上角 10x 放大（看叠色双笔 + 排线 + 出锋）", font=f15, fill=(70, 60, 48, 255))
c4 = tex4.crop((0, 0, 22, 22)).resize((220, 220), Image.NEAREST)
c5 = tex5.crop((0, 0, 22, 22)).resize((220, 220), Image.NEAREST)
prev.paste(c4, (520, 514), c4)
prev.paste(c5, (760, 514), c5)
d.text((520, 742), "v4 · 单笔", font=f13, fill=(70, 60, 48, 255))
d.text((760, 742), "v5 · 双笔叠色 + 三记排线 + 收笔出锋", font=f13, fill=(70, 60, 48, 255))

d.text((30, 486), "③ 三档真实尺寸 1:1", font=f15, fill=(70, 60, 48, 255))
y = 514
for name, w, h, fs in [("继续游戏", 393, 99, 40), ("下一天", 176, 84, 22), ("人物", 84, 28, 14)]:
    for tex, tag in ((tex4, "v4"), (tex5, "v5")):
        img, _ = nine_slice(tex, w, h, MARGIN)
        if img is None:
            img, _ = nine_slice(tex, w, h, 6)
        prev.paste(img, (30, y), img)
        d.text((30 + w + 12, y + h // 2 - 8), "%s %dx%d" % (tag, w, h), font=f13, fill=(70, 60, 48, 255))
        y += h + 10
    y += 16

prev.convert("RGB").save(os.path.join(BASE, "_preview_v5.png"))
P("已存 _preview_v5.png")
open(LOG, "w", encoding="utf-8").write("\n".join(lines))
