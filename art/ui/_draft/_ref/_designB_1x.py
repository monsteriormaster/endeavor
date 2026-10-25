# -*- coding: utf-8 -*-
"""1x 真实像素下的可读性条：6 个候选各 1 张，放在真纸底上，就是游戏里看到的大小。"""
import os, importlib.util
from PIL import Image, ImageDraw, ImageFont
spec = importlib.util.spec_from_file_location("db", os.path.join(os.path.dirname(os.path.abspath(__file__)), "_designB.py"))

import sys
sys.argv = ["_designB.py"]
# 直接复用 _designB 的 render（它跑完会存图，这里接受重复写一次）
import runpy
ns = runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_designB.py"))

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
render, KEYS, LAB = ns["render"], ns["KEYS"], ns["LAB"]
paper = Image.open(os.path.join(R, "art", "ui", "paper_tile.png")).convert("RGB")
HERO = os.path.join(R, "art", "hero.png")

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

# 一排 6 张，就是货架上相邻 6 个卡位的样子（间隔 18）
N = len(KEYS)
SW = 120 + N * 108 + 60
SH = 250
band = Image.new("RGB", (SW, SH))
pw, ph = paper.size
for y in range(0, SH, ph):
    for x in range(0, SW, pw):
        band.paste(paper, (x, y))
d = ImageDraw.Draw(band)
for i, k in enumerate(KEYS):
    band.paste(render(k, HERO, "朱利安", 1), (120 + i * 108, 39))
band.save(os.path.join(BASE, "卡面B_小设计_1x真实像素.png"))
print("SAVED 卡面B_小设计_1x真实像素.png", band.size, "(这一排就是游戏里相邻 6 个卡位的实际大小)")

# 再给一张：把上面那排 1x 用 NEAREST 放大 5 倍，看像素级细节有没有崩
big = band.resize((SW * 5, SH * 5), Image.NEAREST)
big.save(os.path.join(BASE, "卡面B_小设计_1x像素放大5x.png"))
print("SAVED 卡面B_小设计_1x像素放大5x.png", big.size)
