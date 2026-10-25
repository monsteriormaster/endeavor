# -*- coding: utf-8 -*-
"""补裁：地图上的小标签 / 卡组旁的小方块串 / 建筑上的小物件。"""
import os
from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sudan")
OUT = os.path.dirname(os.path.abspath(__file__))

JOBS = [
    ("sudan_ss01.jpg", 110, 545, 420, 120, 3.0, "ic2_ss01_地图小标签.png"),
    ("sudan_ss02.jpg", 1050, 480, 200, 330, 3.0, "ic2_ss02_方块串.png"),
    ("sudan_ss03.jpg", 640, 300, 640, 480, 2.0, "ic2_ss03_建筑上物件.png"),
    ("sudan_ss01.jpg", 620, 900, 480, 180, 2.5, "ic2_ss01_卡组顶.png"),
]

log = []
for fn, x, y, w, h, k, out in JOBS:
    p = os.path.join(SRC, fn)
    im = Image.open(p).convert("RGB")
    W, H = im.size
    box = (max(0, x), max(0, y), min(W, x + w), min(H, y + h))
    crop = im.crop(box)
    crop = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
    dst = os.path.join(OUT, out)
    crop.save(dst)
    log.append("%-26s box=%s -> %dx%d" % (out, str(box), crop.width, crop.height))

with open(os.path.join(OUT, "_sudan_icons2.log"), "w", encoding="utf-8") as f:
    f.write("\n".join(log) + "\n")
print("\n".join(log))
