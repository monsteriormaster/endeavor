# -*- coding: utf-8 -*-
"""苏丹参考图 —— 第二版读图器：针对「暗底 + 少量亮 UI」的图。
三视图：
  STAT  = 亮度分位（先看这幅图到底是暗底还是亮底）
  MASK  = 亮度阈值掩码（# = 亮 → 直接看 UI 结构轮廓，这是暗底图最有效的一招）
  PROJ  = 行/列亮像素计数剖面（定位框线、分区边界、槽位列）
用法：_v2_read2.py <相对路径> [MASK列数] [阈值...]
"""
import sys, os, io
from PIL import Image, ImageFilter
import numpy as np

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"

def render_mask(a, cols, thrs):
    H, W = a.shape
    rows = max(1, int(round(cols * (H / float(W)) * 0.55)))
    ys = np.linspace(0, H, rows + 1).astype(int)
    xs = np.linspace(0, W, cols + 1).astype(int)
    lines = {t: [] for t in thrs}
    for r in range(rows):
        acc = {t: [] for t in thrs}
        for c in range(cols):
            blk = a[ys[r]:ys[r + 1], xs[c]:xs[c + 1]]
            m = float(blk.mean()) if blk.size else 0.0
            for t in thrs:
                acc[t].append("#" if m >= t else ".")
        for t in thrs:
            lines[t].append("".join(acc[t]))
    return lines

def ruler(cols, W):
    per = W / float(cols)
    s = [" "] * cols
    for c in range(cols):
        if c % 10 == 0:
            t = str(int(c * per))
            for k, ch in enumerate(t):
                if c + k < cols: s[c + k] = ch
    return "".join(s)

buf = []
def P(*a): buf.append(" ".join(str(x) for x in a))

rel = sys.argv[1] if len(sys.argv) > 1 else "sudan_panel/ev_925g.png"
COLS = int(sys.argv[2]) if len(sys.argv) > 2 else 150
THRS = [int(x) for x in sys.argv[3:]] or None

f = os.path.join(REF, rel.replace("/", os.sep))
im = Image.open(f).convert("RGB")
W, H = im.size
g = im.convert("L").filter(ImageFilter.GaussianBlur(0.5))
a = np.asarray(g, dtype=np.float32)

qs = [0.1, 1, 5, 10, 25, 50, 75, 90, 95, 99, 99.9]
P("### %s  %dx%d  cell=%.2fpx/char" % (rel, W, H, W / float(COLS)))
P("### 亮度分位: " + "  ".join("p%s=%.0f" % (q, np.percentile(a, q)) for q in qs) + "  max=%.0f" % a.max())
P("### 亮像素占比: >40 %.1f%%  >60 %.1f%%  >80 %.1f%%  >100 %.1f%%  >130 %.1f%%" % tuple(
    (a > t).mean() * 100 for t in (40, 60, 80, 100, 130)))

if THRS is None:
    m = float(np.percentile(a, 50)); sd = float(a.std())
    THRS = [int(m + sd * 0.6), int(m + sd * 1.4)]

lines = render_mask(a, COLS, THRS)
for t in THRS:
    P("### MASK lum>=%d" % t)
    P("    " + ruler(COLS, W))
    for i, l in enumerate(lines[t]):
        P("%4d %s" % (int(i * (H / float(len(lines[t])))), l))

P("### 行亮像素计数（每行 lum>thr1 的像素数，找横线/横带）")
thr1 = THRS[0]
rows_cnt = (a >= thr1).sum(axis=1)
step = max(1, H // 108)
for y in range(0, H, step):
    seg = rows_cnt[y:y + step]
    v = int(seg.max())
    P("  y=%-5d %5d %s" % (y, v, "#" * min(120, v // 4)))

P("### 列亮像素计数（每列 lum>thr1 的像素数，找竖线/竖带）")
cols_cnt = (a >= thr1).sum(axis=0)
stepc = max(1, W // 150)
for x in range(0, W, stepc):
    v = int(cols_cnt[x:x + stepc].max())
    P("  x=%-5d %5d %s" % (x, v, "#" * min(120, v // 3)))

io.open(os.path.join(REF, "_v2_read2_%s.log" % os.path.splitext(os.path.basename(rel))[0]),
        "w", encoding="utf-8").write("\n".join(buf))
print("\n".join(buf[:120]))
