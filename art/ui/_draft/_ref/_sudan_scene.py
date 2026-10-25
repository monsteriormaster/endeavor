# -*- coding: utf-8 -*-
"""裁出苏丹游戏中「场景里的卡」并放大，量它们的尺寸 / 边框 / 选中态。
按 reference-game-ui-sourcing skill 第 5 步：先裁再放大 2-3x 再读。
原图 1920x1080；下列坐标是我按 1080 宽压缩图目测 x1.777 换算来的，先大范围裁，再看着收窄。
"""
import os
from PIL import Image

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sudan")
OUT = os.path.dirname(os.path.abspath(__file__))

JOBS = [
    # (源文件, 左上x, 左上y, 宽, 高, 放大倍数, 输出名)
    ("sudan_ss03.jpg", 480, 360, 400, 320, 3.0, "zoom_scene_ss03_卡片组.png"),
    ("sudan_ss03.jpg", 690, 50, 260, 200, 3.0, "zoom_scene_ss03_屋顶金卡.png"),
    ("sudan_ss01.jpg", 680, 420, 400, 340, 3.0, "zoom_scene_ss01_卡片组.png"),
    ("sudan_ss01.jpg", 900, 200, 260, 260, 3.0, "zoom_scene_ss01_选中卡.png"),
    ("sudan_ss02.jpg", 480, 480, 440, 340, 3.0, "zoom_scene_ss02_卡片组.png"),
    ("sudan_ss02.jpg", 880, 280, 260, 300, 3.0, "zoom_scene_ss02_选中卡.png"),
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
    log.append("%-34s src=%s box=%s -> %dx%d  %d KB"
               % (out, fn, str(box), crop.width, crop.height,
                  os.path.getsize(dst) // 1024))

with open(os.path.join(OUT, "_sudan_scene.log"), "w", encoding="utf-8") as f:
    f.write("\n".join(log) + "\n")
print("\n".join(log))
