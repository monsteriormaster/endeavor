# -*- coding: utf-8 -*-
import os
import numpy as np
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
im = Image.open(os.path.join(REF,'sudan','sudan_ss03.jpg')).convert('L')
g = np.asarray(im).astype(np.float32)
sub = g[650:1080, 150:1000]
rows = (sub > 95).sum(axis=1)
print("--- 逐行(源y) 亮像素数 >80 ---")
ys=[y for y,v in enumerate(rows) if v>80]
print("首行", 650+ys[0] if ys else None, "末行", 650+ys[-1] if ys else None)
for y in range(0, sub.shape[0], 4):
    if rows[y]>80: print("  y%4d n=%4d" % (650+y, rows[y]))
cols = (g[820:1060, :] > 95).sum(axis=0)
print("--- 逐列(源x) 亮像素数 >60 ---")
cs=[x for x,v in enumerate(cols) if v>60]
print("首列", cs[0] if cs else None, "末列", cs[-1] if cs else None)
