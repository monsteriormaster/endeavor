# -*- coding: utf-8 -*-
"""苏丹参考图 —— 深挖：亮度密度图(LUM) + 边缘幅度图(EDGE)。
本模型读不了位图，所以用两级 ASCII 把结构「读」出来：
  LUM  = 每格亮度均值（看大色块 / 面板 / 留白）
  EDGE = 每格 Sobel 幅度最大值（看线、框、分割线、图标轮廓 —— 对平色差免疫）
用法：_v2_deep.py <相对路径> [宽字符数]
"""
import sys, os, io
from PIL import Image, ImageFilter
import numpy as np

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
RAMP = " .:-=+*#%@"

def to_ascii(a, cols, invert=False):
    H, W = a.shape
    rows = max(1, int(round(cols * (H / float(W)) * 0.5)))
    ys = np.linspace(0, H, rows + 1).astype(int)
    xs = np.linspace(0, W, cols + 1).astype(int)
    out = []
    for r in range(rows):
        line = []
        for c in range(cols):
            blk = a[ys[r]:ys[r + 1], xs[c]:xs[c + 1]]
            v = float(blk.mean()) if blk.size else 0.0
            v = max(0.0, min(1.0, v))
            i = int(round(v * (len(RAMP) - 1)))
            if invert:
                i = len(RAMP) - 1 - i
            line.append(RAMP[i])
        out.append("".join(line))
    return out

def edge_ascii(a, cols):
    H, W = a.shape
    rows = max(1, int(round(cols * (H / float(W)) * 0.5)))
    ys = np.linspace(0, H, rows + 1).astype(int)
    xs = np.linspace(0, W, cols + 1).astype(int)
    out = []
    for r in range(rows):
        line = []
        for c in range(cols):
            blk = a[ys[r]:ys[r + 1], xs[c]:xs[c + 1]]
            v = float(blk.max()) if blk.size else 0.0
            i = int(round(max(0.0, min(1.0, v)) * (len(RAMP) - 1)))
            line.append(RAMP[i])
        out.append("".join(line))
    return out

def ruler(cols, W):
    """顶部标尺：每 10 列给一个源像素刻度"""
    per = W / float(cols)
    s = [" "] * cols
    for c in range(cols):
        px = int(c * per)
        if c % 10 == 0:
            t = str(px)
            for k, ch in enumerate(t):
                if c + k < cols: s[c + k] = ch
    return "".join(s)

buf = []
def p(*a): buf.append(" ".join(str(x) for x in a))

args = [a for a in sys.argv[1:]]
paths = args if args else ["sudan_panel/ali_0402.png", "sudan/sudan_ss00.jpg",
                           "sudan/sudan_ss06.jpg", "sudan_panel/wywyx_slots.jpg"]
COLS = 120

for rel in paths:
    f = os.path.join(REF, rel.replace("/", os.sep))
    im = Image.open(f).convert("RGB")
    W, H = im.size
    g = im.convert("L")
    gb = g.filter(ImageFilter.GaussianBlur(0.6))
    a = np.asarray(gb, dtype=np.float32)
    lo, hi = np.percentile(a, 2), np.percentile(a, 98)
    norm = np.clip((a - lo) / max(1e-6, hi - lo), 0, 1)

    e = np.asarray(gb.filter(ImageFilter.FIND_EDGES), dtype=np.float32)
    ehi = np.percentile(e, 99.0)
    en = np.clip(e / max(1e-6, ehi), 0, 1)

    per = W / float(COLS)
    p("=" * 100)
    p("### %s   %dx%d   cell=%.1fpx/char   lum p2/p98=%.0f/%.0f  edge p99=%.0f"
      % (rel, W, H, per, lo, hi, ehi))
    p("### LUM  ( .:-=+*#%@  亮→@ )")
    p("    " + ruler(COLS, W))
    for i, l in enumerate(to_ascii(norm, COLS)):
        p("%3d %s" % (int(i * (H / float(len(to_ascii(norm, COLS))))), l))
    p("### EDGE (线 / 框 / 分割线)")
    p("    " + ruler(COLS, W))
    for i, l in enumerate(edge_ascii(en, COLS)):
        p("%3d %s" % (int(i * (H / float(len(edge_ascii(en, COLS))))), l))

io.open(os.path.join(REF, "_v2_deep.log"), "w", encoding="utf-8").write("\n".join(buf))
print("\n".join(buf))
