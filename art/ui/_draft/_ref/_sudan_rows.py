# -*- coding: utf-8 -*-
"""苏丹面板左栏（x 430..1300，避开左侧「银」等级章）逐行亮像素计数表。

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_sudan_rows.py
"""
import os

from PIL import Image

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
px = Image.open(os.path.join(REF, "sudan", "sudan_ss06.jpg")).convert("L").load()

X0, X1 = 430, 1300
print("x %d..%d  —— 逐行「亮度>130 的像素数」，>=8 才打印（字符 = 每 8 个像素一个 █）" % (X0, X1))
for y in range(200, 900):
    n = sum(1 for x in range(X0, X1) if px[x, y] > 130)
    if n >= 8:
        print("  y=%3d  n=%3d  %s" % (y, n, "█" * min(60, n // 8)))

# 竖向：找属性行里各元素的 x（在属性行的 y 带里扫列）
print("\n--- 属性行的横向元素（y 570..620，亮度>130 的列分布）---")
prev = False
start = 0
for x in range(430, 1300):
    n = sum(1 for y in range(565, 625) if px[x, y] > 130)
    has = n >= 2
    if has and not prev:
        start = x
    if prev and not has:
        print("  块 x=%4d..%4d  宽 %3d" % (start, x - 1, x - start))
    prev = has
if prev:
    print("  块 x=%4d..%4d  宽 %3d" % (start, 1299, 1300 - start))
