# -*- coding: utf-8 -*-
# 给 sudan/ 下所有图做一张「带文件名」的清单图，避免编号错位（上次 sudan_ly_26 是二维码）
import os
from PIL import Image, ImageDraw, ImageFont

SRC = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan"
OUT = r"c:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref\sudan_清单.png"

def font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf", r"C:\Windows\Fonts\arial.ttf"]:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
    return ImageFont.load_default()

files = sorted([f for f in os.listdir(SRC) if f.lower().endswith((".png", ".jpg", ".jpeg"))])
print("count", len(files))

CELL_W, CELL_H = 300, 230
THUMB_W, THUMB_H = 288, 180
COLS = 6
rows = (len(files) + COLS - 1) // COLS
PAD = 8
LABEL_H = 34
sheet = Image.new("RGB", (COLS * (CELL_W + PAD) + PAD, rows * (CELL_H + PAD) + PAD), (32, 30, 28))
d = ImageDraw.Draw(sheet)
f = font(15)

for i, name in enumerate(files):
    cx = PAD + (i % COLS) * (CELL_W + PAD)
    cy = PAD + (i // COLS) * (CELL_H + PAD)
    p = os.path.join(SRC, name)
    try:
        im = Image.open(p).convert("RGB")
    except Exception as e:
        print("ERR", name, e)
        continue
    w, h = im.size
    im.thumbnail((THUMB_W, THUMB_H))
    sheet.paste(im, (cx + (CELL_W - im.size[0]) // 2, cy + (THUMB_H - im.size[1]) // 2))
    d.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1], outline=(90, 84, 76))
    d.text((cx + 4, cy + THUMB_H + 10), "%s  (%dx%d)" % (name, w, h), font=f, fill=(240, 232, 214))

sheet.save(OUT)
print("saved", OUT, sheet.size)
