# -*- coding: utf-8 -*-
"""用「高亮像素的 x 跨度」找苏丹面板的分区线（线 = 跨度极长，文字 = 跨度短且断续）。

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_sudan_geo3.py
"""
import os

from PIL import Image

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SRC = os.path.join(REF, "sudan", "sudan_ss06.jpg")

im = Image.open(SRC).convert("L")
px = im.load()

THR = 150


def row_span(y, x0, x1, thr=THR):
    xs = [x for x in range(x0, x1) if px[x, y] > thr]
    if not xs:
        return 0, 0, 0
    return len(xs), xs[0], xs[-1]


def col_span(x, y0, y1, thr=THR):
    ys = [y for y in range(y0, y1) if px[x, y] > thr]
    if not ys:
        return 0, 0, 0
    return len(ys), ys[0], ys[-1]


print("=== 横线候选：左栏区 x 400..1320，亮度>%d，count>140 视为一条线 ===" % THR)
run = []
for y in range(180, 892):
    n, a, b = row_span(y, 400, 1320)
    if n > 140:
        run.append((y, n, a, b))
# 合并相邻行成一条带
if run:
    band = [run[0]]
    for r in run[1:]:
        if r[0] - band[-1][0] <= 3:
            band.append(r)
        else:
            ys = [b[0] for b in band]
            print("  线 y=%3d..%3d (中心 %3d)  count=%3d  x %d..%d"
                  % (ys[0], ys[-1], (ys[0] + ys[-1]) // 2,
                     max(b[1] for b in band), min(b[2] for b in band), max(b[3] for b in band)))
            band = [r]
    ys = [b[0] for b in band]
    print("  线 y=%3d..%3d (中心 %3d)  count=%3d  x %d..%d"
          % (ys[0], ys[-1], (ys[0] + ys[-1]) // 2,
             max(b[1] for b in band), min(b[2] for b in band), max(b[3] for b in band)))

print("\n=== 竖线候选：y 220..860，count>260 视为一条线 ===")
run = []
for x in range(336, 1700):
    n, a, b = col_span(x, 220, 860)
    if n > 260:
        run.append((x, n, a, b))
if run:
    band = [run[0]]
    for r in run[1:]:
        if r[0] - band[-1][0] <= 3:
            band.append(r)
        else:
            xs = [b[0] for b in band]
            print("  线 x=%4d..%4d (中心 %4d)  count=%3d  y %d..%d"
                  % (xs[0], xs[-1], (xs[0] + xs[-1]) // 2,
                     max(b[1] for b in band), min(b[2] for b in band), max(b[3] for b in band)))
            band = [r]
    xs = [b[0] for b in band]
    print("  线 x=%4d..%4d (中心 %4d)  count=%3d  y %d..%d"
          % (xs[0], xs[-1], (xs[0] + xs[-1]) // 2,
             max(b[1] for b in band), min(b[2] for b in band), max(b[3] for b in band)))

print("\n=== 左栏内「成片内容」的 y 带（每行 x400..1300 的亮像素数 > 25 即算有内容）===")
prev = False
start = 0
for y in range(190, 880):
    n, a, b = row_span(y, 400, 1300)
    has = n > 25
    if has and not prev:
        start = y
    if prev and not has:
        print("  内容带 y=%3d..%3d  高 %d" % (start, y - 1, y - start))
    prev = has
if prev:
    print("  内容带 y=%3d..%3d  高 %d" % (start, 879, 880 - start))
