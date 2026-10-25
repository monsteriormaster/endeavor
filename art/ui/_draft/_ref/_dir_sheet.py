# -*- coding: utf-8 -*-
"""目录联络表：把一目录的图缩到同高排成网格，便于快速"看到"参考原图。
用法: python _dir_sheet.py <dir> <out.png> [cols] [cell_h] [name_filter_regex]
"""
import os, sys, re, glob
from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1]
OUT = sys.argv[2]
COLS = int(sys.argv[3]) if len(sys.argv) > 3 else 4
CH = int(sys.argv[4]) if len(sys.argv) > 4 else 380
RX = re.compile(sys.argv[5], re.I) if len(sys.argv) > 5 else None

def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

files = []
for ext in ("png", "jpg", "jpeg", "webp"):
    files += glob.glob(os.path.join(SRC, "*." + ext))
files = sorted(f for f in files if "sheet" not in os.path.basename(f).lower())
if RX:
    files = [f for f in files if RX.search(os.path.basename(f))]

items = []
for f in files:
    try:
        im = Image.open(f)
        if im.mode in ("RGBA", "LA", "P"):
            im = im.convert("RGBA")
            bg = Image.new("RGB", im.size, (232, 230, 227))
            bg.paste(im, mask=im.split()[-1])
            im = bg
        else:
            im = im.convert("RGB")
    except Exception as e:
        print("ERR", f, e); continue
    w, h = im.size
    items.append((os.path.basename(f), im, (w, h)))
    print("%-46s %dx%d  ar=%.3f" % (os.path.basename(f), w, h, w / max(1, h)))

if not items:
    print("no images"); raise SystemExit

rows = (len(items) + COLS - 1) // COLS
cell_w = int(CH * 2.2)
GAP, PAD, LAB = 26, 30, 34
sheet = Image.new("RGB", (PAD * 2 + COLS * cell_w + (COLS - 1) * GAP,
                          PAD * 2 + rows * (LAB + CH) + (rows - 1) * GAP), (240, 238, 234))
d = ImageDraw.Draw(sheet)
f = font(20)
for i, (name, im, sz) in enumerate(items):
    r, c = divmod(i, COLS)
    x = PAD + c * (cell_w + GAP)
    y = PAD + r * (LAB + CH + GAP)
    sc = CH / im.size[1]
    if im.size[0] * sc > cell_w:
        sc = cell_w / im.size[0]
    th = im.resize((max(1, int(im.size[0] * sc)), max(1, int(im.size[1] * sc))), Image.LANCZOS)
    d.text((x, y), "%s  %dx%d" % (name, sz[0], sz[1]), fill=(35, 32, 30), font=f)
    sheet.paste(th, (x + (cell_w - th.size[0]) // 2, y + LAB))
sheet.save(OUT)
print("SAVED", OUT, sheet.size, len(items), "imgs")
