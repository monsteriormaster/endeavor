# -*- coding: utf-8 -*-
"""裁苏丹官方截图里所有「小图标」聚集区并放大 4x，找出用户说的「触发器图标」。
坐标 = 1080 宽预览目测 x1.7778 换算到 1920x1080 原图。
"""
import os
from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sudan")
OUT = os.path.dirname(os.path.abspath(__file__))

JOBS = [
    ("sudan_ss01.jpg", 40, 800, 240, 250, 4.0, "ic_ss01_左下角.png"),
    ("sudan_ss01.jpg", 1800, 0, 120, 110, 4.0, "ic_ss01_右上角.png"),
    ("sudan_ss01.jpg", 1800, 370, 120, 170, 4.0, "ic_ss01_右侧小圆.png"),
    ("sudan_ss01.jpg", 590, 920, 150, 160, 4.0, "ic_ss01_卡带左端.png"),
    ("sudan_ss03.jpg", 1640, 360, 190, 180, 4.0, "ic_ss03_面板右小圆.png"),
    ("sudan_ss02.jpg", 40, 800, 240, 250, 4.0, "ic_ss02_左下角.png"),
    ("sudan_ss04.jpg", 0, 0, 480, 300, 2.5, "ic_ss04_左上.png"),
]

log = []
for fn, x, y, w, h, k, out in JOBS:
    p = os.path.join(SRC, fn)
    if not os.path.exists(p):
        log.append("MISS %s" % fn)
        continue
    im = Image.open(p).convert("RGB")
    W, H = im.size
    box = (max(0, x), max(0, y), min(W, x + w), min(H, y + h))
    crop = im.crop(box)
    crop = crop.resize((int(crop.width * k), int(crop.height * k)), Image.LANCZOS)
    dst = os.path.join(OUT, out)
    crop.save(dst)
    log.append("%-26s box=%s -> %dx%d" % (out, str(box), crop.width, crop.height))

with open(os.path.join(OUT, "_sudan_icons.log"), "w", encoding="utf-8") as f:
    f.write("\n".join(log) + "\n")
print("\n".join(log))
