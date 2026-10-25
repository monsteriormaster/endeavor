# -*- coding: utf-8 -*-
"""物品详情面板底图 —— `art/ui/item_panel.png`（680×600）。

画风基线（不是"我觉得像"，是从已实装素材上量下来的）：
  · 纸色        = check_panel.png 中线取样的 (239, 234, 223)
  · 墨线        = check_panel.png 边框取样的 (108, 80, 30)
  · 纸纹        = `art/ui/paper_tile.png` 1:1 裁切（不做假噪点）
  · 框型        = 手绘抖动双层框（外粗内细 + 顶中铜扣），与 check_panel / confirm_panel 同款
  · 金色细线    = 与 character_panel 的 gold_rule 同色系（154,112,46），两端菱形

版面（= `components/card_detail_popup.gd` 里那套坐标的来源，改版面先改这里再改 gd）：

     680 × 600
     ┌──────────────────────────────────────────────┐
     │                        x2        ◇ 顶中铜扣   │
     │   ┌──────────┐   ┌───────────────────────┐   │
     │   │          │   │ 名称  30px             │   │
     │   │  图位    │   │ 稀有度 · 类别  15px     │   │
     │   │ 200×280  │   ├───◇───────────────◇───┤   │
     │   │          │   │ 加成  17px             │   │
     │   │          │   │ 标签 chips             │   │
     │   └──────────┘   │ id 12px                │   │
     │  ────────◇──────────────────────────────     │
     │  │ 描述                                       │
     │  正文 16px                                    │
     └──────────────────────────────────────────────┘

跑法：
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/make_item_panel_bg.py
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

R = r"C:\Users\26464\IdeaProjects\endeavor"
OUT = os.path.join(R, "art", "ui", "item_panel.png")
PAPER = os.path.join(R, "art", "ui", "paper_tile.png")

W, H = 680, 540
SS = 3                      # 线条层超采样倍数（纸底层不做超采样，纹理要 1:1）

# ---- 取样常量 ----------------------------------------------------------
PAPER_RGB = (242, 237, 227)
INK = (108, 80, 30)
INK_LINE = (150, 118, 68)     # 线条专用：比纯 INK 提亮一档（check_panel 的线是暖褐，不是墨黑）
BRASS = (154, 112, 46)
BRASS_LT = (232, 222, 196)
TEXT = (46, 33, 23)

MARGIN = 13                 # 外框线中心距画布边
RADIUS = 9                  # 外框圆角
INNER_INSET = 15            # 内细线相对外框内缩

# ---- 版面锚点（gd 里同名常量要对齐这里）----------------------------------
BOX_X0, BOX_Y0, BOX_X1, BOX_Y1 = 52, 72, 222, 308      # 图位框 170×236（= 物品竖图 0.72）
COL_X0, COL_X1 = 258, 636                              # 右栏左右缘
NAME_Y = 62                                            # 名称行顶
SUB_Y = 112                                            # 品质 · 类别 行顶
GOLD_Y = 150                                           # 名称区下的金线
RULE_Y = 318                                           # 通栏细线
DESC_X, DESC_Y = 52, 328                               # 描述标题竖笔
BODY_Y = 354                                           # 描述正文顶
CLOSE_C = (632, 56)                                    # 右上 X 中心
KNOB_C = (340, MARGIN)                                 # 顶中铜扣


# ============================================================
#  纸底
# ============================================================
def _paper_layer() -> Image.Image:
    """1:1 裁 paper_tile，归一色值 → 加低频斑与边缘压暗。"""
    src = Image.open(PAPER).convert("L")
    # 取一块不用重复拼的 1:1 区域（纸纹无方向性，取任意偏移都成立）
    ox = (src.width - W) // 2
    oy = (src.height - H) // 2
    g = np.asarray(src.crop((ox, oy, ox + W, oy + H))).astype(np.float32)

    # 高频细节：z-score 后限幅，保证均值不动（不准把纸色带偏）
    d = (g - g.mean()) / (g.std() + 1e-6)
    d = np.clip(d, -2.5, 2.5)
    amps = (1.9, 1.9, 1.7)
    out = np.zeros((H, W, 3), np.float32)
    for c, a in enumerate(amps):
        out[:, :, c] = PAPER_RGB[c] + d * a

    # 低频斑：缩小→模糊→放大，只取偏差（±2.6），模拟纸张吸墨不匀
    small = src.crop((ox, oy, ox + W, oy + H)).resize((W // 32, H // 32), Image.BILINEAR)
    small = small.filter(ImageFilter.GaussianBlur(2.0))
    blot = np.asarray(small.resize((W, H), Image.BICUBIC)).astype(np.float32)
    blot = (blot - blot.mean()) / (blot.std() + 1e-6)
    out += np.clip(blot, -2.0, 2.0)[:, :, None] * 1.0

    # 边缘压暗（vignette）：中心 1.0 → 四角 0.955，克制
    yy, xx = np.mgrid[0:H, 0:W]
    nx = (xx - W / 2.0) / (W / 2.0)
    ny = (yy - H / 2.0) / (H / 2.0)
    r2 = np.clip((nx * nx + ny * ny) / 2.0, 0.0, 1.0)
    out *= (1.0 - 0.045 * r2)[:, :, None]
    # 归一：叠层会带来 ±4 的均值漂移，这里直接扣回去（纸色必须锁死 PAPER_RGB）
    out += (np.array(PAPER_RGB, np.float32) - out.mean(axis=(0, 1)))

    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def _paper_mask() -> Image.Image:
    """纸面形状：外框内的圆角矩形，框外全透明（与 check_panel 一致）。"""
    m = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([MARGIN, MARGIN, W - 1 - MARGIN, H - 1 - MARGIN],
                        radius=RADIUS, fill=255)
    return m.filter(ImageFilter.GaussianBlur(0.6))


# ============================================================
#  抖动线
# ============================================================
def _path_rounded(x0, y0, x1, y1, r, step=2.0):
    pts = []

    def seg(ax, ay, bx, by):
        n = max(2, int(math.hypot(bx - ax, by - ay) / step))
        for i in range(n + 1):
            pts.append((ax + (bx - ax) * i / n, ay + (by - ay) * i / n))

    def arc(cx, cy, a0, a1):
        n = max(2, int(abs(a1 - a0) * r / step))
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))

    seg(x0 + r, y0, x1 - r, y0)
    arc(x1 - r, y0 + r, -90, 0)
    seg(x1, y0 + r, x1, y1 - r)
    arc(x1 - r, y1 - r, 0, 90)
    seg(x1 - r, y1, x0 + r, y1)
    arc(x0 + r, y1 - r, 90, 180)
    seg(x0, y1 - r, x0, y0 + r)
    arc(x0 + r, y0 + r, 180, 270)
    return pts


def _wobble(pts, amp, freq, seed):
    """沿法线做低频正弦 + 微随机的偏移 —— 手抖的观感来自「频率低、幅度小」。"""
    random.seed(seed)
    p1, p2 = random.random() * 6.283, random.random() * 6.283
    n = len(pts)
    out = []
    for i, (x, y) in enumerate(pts):
        t = i / float(n)
        dv = (math.sin(t * freq * 6.283 + p1) * 0.65
              + math.sin(t * freq * 2.3 * 6.283 + p2) * 0.35)
        dv += random.uniform(-0.12, 0.12)
        x1, y1 = pts[i - 1]
        x2, y2 = pts[(i + 1) % n]
        tx, ty = x2 - x1, y2 - y1
        ln = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / ln, tx / ln
        out.append((x + nx * dv * amp, y + ny * dv * amp))
    return out


def _stroke(d, pts, width, color, alpha=255, press=0.0, seed=0):
    """画一条沿路径的线。

    press>0 时按段抖 alpha（笔压起伏）—— check_panel 的框线深浅是断续的，
    一条 alpha 恒定的线不管抖不抖都会显出"矢量感"。
    """
    s = [(x * SS, y * SS) for x, y in pts]
    w = max(1, int(round(width * SS)))
    if press <= 0.0:
        d.line(s, fill=color + (alpha,), width=w, joint="curve")
    else:
        random.seed(seed)
        seg_n = 26
        step = max(1, len(s) // seg_n)
        for i in range(0, len(s) - 1, step):
            j = min(len(s) - 1, i + step)
            a = alpha * (1.0 + random.uniform(-press, press))
            d.line(s[i:j + 1], fill=color + (int(max(0, min(255, a))),), width=w, joint="curve")


def _twinkle(d, cx, cy, r, fill=None, outline=None, ow=1.2):
    pts = [(cx * SS, (cy - r) * SS), ((cx + r) * SS, cy * SS),
           (cx * SS, (cy + r) * SS), ((cx - r) * SS, cy * SS)]
    if fill is not None:
        d.polygon(pts, fill=fill + (255,))
    if outline is not None:
        d.line(pts + [pts[0]], fill=outline + (255,), width=max(1, int(ow * SS)), joint="curve")


def _line(d, x0, y0, x1, y1, w, color, alpha=255):
    d.line([(x0 * SS, y0 * SS), (x1 * SS, y1 * SS)], fill=color + (alpha,),
           width=max(1, int(round(w * SS))))


# ============================================================
#  线层
# ============================================================
def _ink_layer() -> Image.Image:
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # 外框：check_panel 剖面（x14..20 = 75,81,70,123,181,146,179,243）说明它是
    # **双线描边** —— 一条 2px 主线 + 贴内 4px 处一条 1px 伴线，不是一根粗线。
    # 先用同一抖动路径铺模糊柔光（笔压外渗），再画两条实线。
    outer = _path_rounded(MARGIN, MARGIN, W - 1 - MARGIN, H - 1 - MARGIN, RADIUS)
    wob = _wobble(outer, 2.6, 10.0, 11)
    _stroke(d, wob, 1.9, INK_LINE, 244, press=0.13, seed=21)
    comp = _path_rounded(MARGIN + 4, MARGIN + 4, W - 1 - MARGIN - 4, H - 1 - MARGIN - 4, RADIUS - 1)
    _stroke(d, _wobble(comp, 2.2, 10.0, 11), 0.9, INK_LINE, 190, press=0.18, seed=22)

    # 内细线：内缩 15，很淡，抖幅略小（像同一条手画第二遍）
    i0 = MARGIN + INNER_INSET
    inner = _path_rounded(i0, i0, W - 1 - i0, H - 1 - i0, RADIUS - 2)
    _stroke(d, _wobble(inner, 1.15, 6.5, 12), 0.9, INK_LINE, 150, press=0.2, seed=23)

    # 顶中铜扣（压在线上，克制）
    _twinkle(d, KNOB_C[0], KNOB_C[1], 5.2, fill=BRASS_LT, outline=INK, ow=1.1)
    _twinkle(d, KNOB_C[0], KNOB_C[1], 2.1, outline=BRASS, ow=0.9)

    # 右上 X（该位置放 flat Button，见 gd 的 CLOSE_XY）
    cx, cy = CLOSE_C
    d.ellipse([(cx - 8.5) * SS, (cy - 8.5) * SS, (cx + 8.5) * SS, (cy + 8.5) * SS],
              outline=INK + (165,), width=max(1, int(1.1 * SS)))
    _line(d, cx - 4.2, cy - 4.2, cx + 4.2, cy + 4.2, 1.7, INK, 220)
    _line(d, cx - 4.2, cy + 4.2, cx + 4.2, cy - 4.2, 1.7, INK, 220)

    # 图位框：细线 + 四角 L 角标（"这里放图"的暗示，比实心框轻）
    box = _path_rounded(BOX_X0, BOX_Y0, BOX_X1, BOX_Y1, 3)
    _stroke(d, _wobble(box, 0.55, 3.5, 13), 0.9, INK, 105)
    L = 15
    for (bx, by, sx, sy) in ((BOX_X0, BOX_Y0, 1, 1), (BOX_X1, BOX_Y0, -1, 1),
                             (BOX_X0, BOX_Y1, 1, -1), (BOX_X1, BOX_Y1, -1, -1)):
        _line(d, bx, by, bx + sx * L, by, 1.7, INK, 205)
        _line(d, bx, by, bx, by + sy * L, 1.7, INK, 205)

    # 名称区下的金线（两端菱形）—— 与 character_panel 的 gold_rule 同款
    _line(d, COL_X0, GOLD_Y, COL_X1, GOLD_Y, 1.5, BRASS, 235)
    for cx2 in (COL_X0, COL_X1):
        _twinkle(d, cx2, GOLD_Y, 3.0, fill=BRASS)
    _twinkle(d, (COL_X0 + COL_X1) / 2.0, GOLD_Y, 1.8, fill=BRASS, outline=BRASS, ow=0.8)

    # 通栏细线（中点菱形，避免"表格感"）
    _line(d, BOX_X0, RULE_Y, COL_X1, RULE_Y, 1.0, INK, 110)
    _twinkle(d, (BOX_X0 + COL_X1) / 2.0, RULE_Y, 2.6, fill=BRASS, outline=INK, ow=0.8)

    # 「描述」前的竖笔（照 character_panel 的「| 描述」）
    _line(d, DESC_X, DESC_Y + 1, DESC_X, DESC_Y + 19, 2.0, BRASS, 235)

    return im


# ============================================================
#  合成
# ============================================================
def main():
    paper = _paper_layer().convert("RGBA")
    mask = _paper_mask()
    paper.putalpha(mask)

    ink = _ink_layer().resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.35))
    out = Image.alpha_composite(paper, ink)
    # 透明区 RGB 清干净：LANCZOS 会在 alpha≈0 处留 (127,63,0) 这类垃圾值，
    # 带上 alpha 看不出，但一旦被 convert("RGB") 或非线性混合露出来就是一片红点。
    arr = np.array(out)
    ghost = arr[:, :, 3] < 8
    arr[:, :, 3][ghost] = 0
    arr[:, :, 0][ghost] = PAPER_RGB[0]
    arr[:, :, 1][ghost] = PAPER_RGB[1]
    arr[:, :, 2][ghost] = PAPER_RGB[2]
    out = Image.fromarray(arr, "RGBA")
    out.save(OUT)
    print("saved", OUT, out.size)
    # 自检：纸色均值必须落在 PAPER_RGB 附近（±3），否则说明叠层带偏了色
    a = np.asarray(out).astype(np.float32)
    sel = a[:, :, 3] > 250
    core = a[200:500, 380:620]
    core = core[core[:, :, 3] > 250][:, :3]
    print("core mean rgb", core.mean(axis=0).round(1), "opaque px", int(sel.sum()))


if __name__ == "__main__":
    main()
