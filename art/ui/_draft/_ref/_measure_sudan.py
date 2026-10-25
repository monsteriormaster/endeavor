# -*- coding: utf-8 -*-
"""对着一张真实卡做剖面测量：找外框线、拱窗、分带的像素位置。"""
import os
from PIL import Image

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
src = os.path.join(BASE, "sudan", "sudan_ss00.jpg")
im = Image.open(src).convert("RGB")
print("src", im.size)

# 手牌行：先扫 y 找卡片的上下边界（用金色像素密度）
px = im.load()
W, H = im.size
def gold_ratio_row(y, x0=40, x1=300):
    n = g = 0
    for x in range(x0, x1):
        r, gg, b = px[x, y]
        n += 1
        if r > 120 and gg > 95 and b < 110 and (r - b) > 55:
            g += 1
    return g / n

print("--- 行金像素比 (y: ratio) ---")
prev = 0
for y in range(760, H, 2):
    v = gold_ratio_row(y)
    if abs(v - prev) > 0.12:
        print("  y=%4d  %.3f  <== 跳变" % (y, v))
    prev = v

def gold_ratio_col(x, y0=790, y1=980):
    n = g = 0
    for y in range(y0, y1):
        r, gg, b = px[x, y]
        n += 1
        if r > 120 and gg > 95 and b < 110 and (r - b) > 55:
            g += 1
    return g / n

print("--- 列金像素比 (x: ratio) 找左右边界 ---")
prev = 0
for x in range(30, 340, 1):
    v = gold_ratio_col(x)
    if abs(v - prev) > 0.15:
        print("  x=%4d  %.3f  <== 跳变" % (x, v))
    prev = v
