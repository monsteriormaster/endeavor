# -*- coding: utf-8 -*-
"""把苏丹地图上的「事件小徽章」放大 10x 看轮廓/描边/内部图案。"""
import os
from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sudan")
OUT = os.path.dirname(os.path.abspath(__file__))

JOBS = [
    ("sudan_ss01.jpg", 135, 566, 52, 52, 10.0, "badge_ss01_A.png"),
    ("sudan_ss01.jpg", 270, 560, 56, 56, 10.0, "badge_ss01_B.png"),
    ("sudan_ss02.jpg", 1078, 618, 60, 60, 10.0, "badge_ss02.png"),
    ("sudan_ss03.jpg", 1290, 168, 60, 60, 10.0, "badge_ss03.png"),
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
    log.append("%-18s box=%s -> %dx%d" % (out, str(box), crop.width, crop.height))

with open(os.path.join(OUT, "_sudan_badge.log"), "w", encoding="utf-8") as f:
    f.write("\n".join(log) + "\n")
print("\n".join(log))
