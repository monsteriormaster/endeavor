# -*- coding: utf-8 -*-
"""量化苏丹《Sultan's Game》人物面板的版面几何（不靠目测）。

产出：
  ① 控制台日志（写进 _sudan_geo.log）：
     · 面板的暗区 bbox
     · 逐行「亮金像素数」剖面 → 所有横向分区线的 y
     · 逐列剖面 → 竖向线的 x
     · 属性行的行高、数值列右缘
  ② sudan_量版面_网格.png —— 面板裁图放大 1.5x + 源坐标网格，用来读坐标核对
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_sudan_geo.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SRC = os.path.join(REF, "sudan", "sudan_ss06.jpg")

im = Image.open(SRC).convert("RGB")
W, H = im.size
print("src", W, H)

g = im.convert("L")
px = g.load()


def rowprofile(x0, x1, y0, y1, thr=118):
    """逐行统计 [x0,x1) 内亮度 > thr 的像素数（横向金线会形成尖峰）。"""
    out = []
    for y in range(y0, y1):
        c = 0
        for x in range(x0, x1, 2):
            if px[x, y] > thr:
                c += 1
        out.append((y, c))
    return out


def colprofile(x0, x1, y0, y1, thr=118):
    out = []
    for x in range(x0, x1):
        c = 0
        for y in range(y0, y1, 2):
            if px[x, y] > thr:
                c += 1
        out.append((x, c))
    return out


# ---- ① 面板暗区 bbox：面板内部是深色皮革，背景是石头墙（更亮）----
print("\n--- 列剖面（y 300..780 上的暗像素占比），找面板左右界 ---")
for x in range(300, 1800, 4):
    c = 0
    n = 0
    for y in range(300, 780, 4):
        n += 1
        if px[x, y] < 70:
            c += 1
    if x % 40 == 0:
        print("  x=%4d  暗占比 %.2f" % (x, c / max(1, n)))

print("\n--- 行剖面（x 420..1600 上的暗像素占比），找面板上下界 ---")
for y in range(120, 900, 4):
    c = 0
    n = 0
    for x in range(420, 1600, 4):
        n += 1
        if px[x, y] < 70:
            c += 1
    if y % 20 == 0:
        print("  y=%4d  暗占比 %.2f" % (y, c / max(1, n)))

# ---- ② 横向分区线：面板内部 x 420..1600 的亮金像素尖峰 ----
print("\n--- 横向亮线（x 430..1590，亮度>118 的像素数；>60 视为一条线）---")
rp = rowprofile(430, 1590, 180, 860)
for y, c in rp:
    if c > 60:
        print("  y=%4d  count=%3d" % (y, c))

# ---- ③ 竖向线 ----
print("\n--- 竖向亮线（y 300..700，亮度>118；>40 视为一条线）---")
cp = colprofile(340, 1720, 300, 700)
for x, c in cp:
    if c > 40:
        print("  x=%4d  count=%3d" % (x, c))


# ---- ④ 带源坐标网格的放大图（读坐标核对用）----
def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


BOX = (330, 150, 1730, 830)
SC = 1.5
c = im.crop(BOX)
c = c.resize((int(c.size[0] * SC), int(c.size[1] * SC)), Image.LANCZOS)
d = ImageDraw.Draw(c)
f = font(18)
x0s, y0s = BOX[0], BOX[1]
for xs in range(350, 1750, 50):
    X = int((xs - x0s) * SC)
    major = (xs % 100 == 0)
    d.line([X, 0, X, c.size[1]], fill=(255, 90, 90) if major else (255, 160, 160), width=2 if major else 1)
    if major:
        d.text((X + 3, 4), str(xs), font=f, fill=(255, 240, 120))
for ys in range(200, 850, 50):
    Y = int((ys - y0s) * SC)
    major = (ys % 100 == 0)
    d.line([0, Y, c.size[0], Y], fill=(90, 200, 255) if major else (170, 215, 255), width=2 if major else 1)
    if major:
        d.text((4, Y + 3), str(ys), font=f, fill=(255, 240, 120))
out = os.path.join(REF, "sudan_量版面_网格.png")
c.save(out)
print("\n写出", out, c.size)
