# -*- coding: utf-8 -*-
"""局部放大：从游戏截图里裁出真实卡面区域并放大。
用法: python _zoom.py <img> <out> <x0> <y0> <x1> <y1> [scale]
"""
import os, sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = (int(v) for v in sys.argv[3:7])
sc = float(sys.argv[7]) if len(sys.argv) > 7 else 4.0

im = Image.open(src).convert("RGB")
W, H = im.size
x0 = max(0, min(x0, W - 1)); x1 = max(x0 + 1, min(x1, W))
y0 = max(0, min(y0, H - 1)); y1 = max(y0 + 1, min(y1, H))
c = im.crop((x0, y0, x1, y1))
c = c.resize((int(c.size[0] * sc), int(c.size[1] * sc)), Image.LANCZOS)
c.save(out)
print("SRC %dx%d  crop=(%d,%d)-(%d,%d) %dx%d  ->  %dx%d  %s"
      % (W, H, x0, y0, x1, y1, x1 - x0, y1 - y0, c.size[0], c.size[1], out))
