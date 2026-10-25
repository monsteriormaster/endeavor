# -*- coding: utf-8 -*-
"""旧 card.png 的透明像素分布在哪（决定新卡是否要带透明）。"""
import os
from PIL import Image

R = r"C:\Users\26464\IdeaProjects\endeavor"
im = Image.open(os.path.join(R, "art", "card.png")).convert("RGBA")
W, H = im.size
a = im.getchannel("A").load()
px = im.load()

# 逐行 / 逐列的透明计数
rows = [sum(1 for x in range(W) if a[x, y] == 0) for y in range(H)]
cols = [sum(1 for y in range(H) if a[x, y] == 0) for x in range(W)]

print("尺寸", im.size)
print("\n--- 有透明像素的行 (y : 数量) ---")
for y in range(H):
    if rows[y]:
        print("  y=%3d  %3d / %d" % (y, rows[y], W))
print("\n--- 有透明像素的列 (x : 数量) ---")
for x in range(W):
    if cols[x]:
        print("  x=%3d  %3d / %d" % (x, cols[x], H))

# alpha 非零 bbox
xs = [x for x in range(W) if cols[x] < H]
ys = [y for y in range(H) if rows[y] < W]
print("\n不透明区域 bbox: x %d..%d  y %d..%d" % (xs[0], xs[-1], ys[0], ys[-1]) if xs and ys else "全透明?")

# 四角 alpha
print("\n四角 alpha:", a[0, 0], a[W-1, 0], a[0, H-1], a[W-1, H-1])
# 几个关键点
for (x, y, lab) in ((3, 3, "左上3,3"), (W//2, 3, "上中"), (W//2, H//2, "正中"), (W//2, H-5, "上中近底"), (5, H//2, "左中")):
    print("  %-10s alpha=%3d  rgb=%s" % (lab, a[x, y], px[x, y][:3]))
