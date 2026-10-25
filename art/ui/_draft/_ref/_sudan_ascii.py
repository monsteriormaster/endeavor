# -*- coding: utf-8 -*-
"""把苏丹人物面板的左半区打成 ASCII 密度图（带坐标标尺），用来精确读版面分区位置。

为什么不用亮度剖面：面板本身是带纹理的深色皮革，逐行亮度是噪声。
ASCII 图把「亮 = 文字/线」直接可视化成字符，配合标尺能一眼读出每个分区的 y/x。

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_sudan_ascii.py
"""
import os

from PIL import Image

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SRC = os.path.join(REF, "sudan", "sudan_ss06.jpg")

im = Image.open(SRC).convert("L")
px = im.load()

CELL = 8
X0, X1 = 336, 1680      # 面板整幅（含左右边框）
Y0, Y1 = 176, 888
THR = 104               # 「亮」= 文字 / 金线 / 插画高光


def ink_run(x0, x1, y0, y1, thr):
    n = 0
    t = 0
    for x in range(x0, x1):
        for y in range(y0, y1):
            t += 1
            if px[x, y] > thr:
                n += 1
    return n / max(1, t)


print("cell=%dpx  x %d..%d  y %d..%d  thr=%d" % (CELL, X0, X1, Y0, Y1, THR))

# 顶部 x 标尺（每 10 格 = 80px 打一个百位标）
cols = list(range(X0, X1, CELL))
hdr1 = [" "] * len(cols)
hdr2 = [" "] * len(cols)
for i, x in enumerate(cols):
    if (x - X0) % 80 == 0:
        lab = str(x)
        for k, ch in enumerate(lab):
            if i + k < len(cols):
                hdr1[i + k] = ch
print("      " + "".join(hdr1))
print("      " + "".join(hdr2))

for y in range(Y0, Y1, CELL):
    row = []
    for x in cols:
        v = ink_run(x, min(x + CELL, X1), y, min(y + CELL, Y1), THR)
        row.append("██" if v > 0.5 else ("▓▓" if v > 0.25 else ("░░" if v > 0.10 else "  ")))
    print("%4d |%s|" % (y, "".join(row)))
