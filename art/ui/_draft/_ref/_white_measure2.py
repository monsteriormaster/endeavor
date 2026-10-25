# -*- coding: utf-8 -*-
"""深扫白版描边区（x0..x0+46 / y0..y0+46），并给出归一化到 90px 卡宽后的厚度。"""
import os
from PIL import Image

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SRC = os.path.join(BASE, "draw", "A_single_vertical_collectible__2026-09-27T14-21-13.png")
im = Image.open(SRC).convert("RGB")
px = im.load()
x0, y0, cw = 148, 208, 727

print("=== 横扫 y=768  x0..x0+46 ===")
for x in range(x0 - 1, x0 + 47):
    c = px[x, 768]
    m = sum(c) / 3
    print("x+%2d  %s  L=%3d  %s" % (x - x0, c, m, "#" * int(m / 8)))

print("\n=== 竖扫 x=511  y0..y0+46 ===")
for y in range(y0 - 1, y0 + 47):
    c = px[511, y]
    m = sum(c) / 3
    print("y+%2d  %s  L=%3d  %s" % (y - y0, c, m, "#" * int(m / 8)))

# 找出真正的金线：扫描线上的"黄色度" = R+G-2B 高的点
print("\n=== 金线定位（黄色度 = R+G-2B）横扫 y=768 ===")
for x in range(x0, x0 + 60):
    r, g, b = px[x, 768]
    yell = r + g - 2 * b
    if yell > 30:
        print("x+%2d  %s  yellowness=%d  (卡宽占比 %.4f)" % (x - x0, px[x, 768], yell, (x - x0) / cw))

print("\n=== 金线定位 竖扫 x=511 ===")
for y in range(y0, y0 + 60):
    r, g, b = px[511, y]
    yell = r + g - 2 * b
    if yell > 30:
        print("y+%2d  %s  yellowness=%d  (卡宽占比 %.4f)" % (y - y0, px[511, y], yell, (y - y0) / cw))

# 下边 & 右边：看厚度阴影
print("\n=== 下边 y1=1329 往上 30px ===")
for y in range(1329 + 12, 1329 - 34, -1):
    c = px[511, y]
    print("y-1329=%+3d  %s  L=%3d" % (y - 1329, c, sum(c) // 3))

print("\n=== 右边 x1=874 往左 30px ===")
for x in range(874 + 12, 874 - 34, -1):
    c = px[x, 768]
    print("x-874=%+3d  %s  L=%3d" % (x - 874, c, sum(c) // 3))
