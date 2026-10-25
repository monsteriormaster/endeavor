# -*- coding: utf-8 -*-
"""量白版原图：卡身色 / 描边色 / 描边厚度（相对卡宽）。"""
import os
from PIL import Image

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SRC = os.path.join(BASE, "draw", "A_single_vertical_collectible__2026-09-27T14-21-13.png")
im = Image.open(SRC).convert("RGB")
W, H = im.size
px = im.load()
print("源尺寸", im.size, "比例 %.3f" % (W / H))

# 找卡 bbox：以背景灰为准（四角取样）
bg = px[3, 3]
print("背景", bg)


def isbg(c, t=14):
    return all(abs(c[i] - bg[i]) <= t for i in range(3))


x0 = next(x for x in range(W) if not isbg(px[x, H // 2]))
x1 = next(x for x in range(W - 1, -1, -1) if not isbg(px[x, H // 2]))
y0 = next(y for y in range(H) if not isbg(px[W // 2, y]))
y1 = next(y for y in range(H - 1, -1, -1) if not isbg(px[W // 2, y]))
cw, ch = x1 - x0 + 1, y1 - y0 + 1
print("卡 bbox x%d..%d y%d..%d  = %d x %d  比例 %.3f" % (x0, x1, y0, y1, cw, ch, cw / ch))

# 卡身色：取中心区域中位数
cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
vals = [px[cx + dx, cy + dy] for dx in range(-30, 31, 3) for dy in range(-30, 31, 3)]
body = tuple(sorted(v[i] for v in vals)[len(vals) // 2] for i in range(3))
print("卡身色(中位)", body)

# 上边界到中心的一条竖扫描：从 y0 往下 30px，打印变化
print("\n--- 竖扫描 x=%d, 从上边 y%d 往下 ---" % (cx, y0))
prev = None
for y in range(y0 - 2, y0 + 26):
    c = px[cx, y]
    tag = ""
    if prev is not None:
        d = max(abs(c[i] - prev[i]) for i in range(3))
        if d > 6:
            tag = "  <== 跳变 %d" % d
    print("y+%3d  %s%s" % (y - y0, c, tag))
    prev = c

# 左边界到中心的一条横扫描
print("\n--- 横扫描 y=%d, 从左边 x%d 往右 ---" % (cy, x0))
prev = None
for x in range(x0 - 2, x0 + 26):
    c = px[x, cy]
    tag = ""
    if prev is not None:
        d = max(abs(c[i] - prev[i]) for i in range(3))
        if d > 6:
            tag = "  <== 跳变 %d" % d
    print("x+%3d  %s%s" % (x - x0, c, tag))
    prev = c

# 卡宽归一化：描边厚度 / 卡宽
print("\n相对卡宽归一化：卡宽 %d px" % cw)
