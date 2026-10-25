# -*- coding: utf-8 -*-
import os
import numpy as np
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
im = Image.open(os.path.join(REF,'sudan','sudan_ss04.jpg')).convert('L')
g = np.asarray(im).astype(np.float32)
print("size", im.size)
# 手牌行 = 底部明亮、且横向方差大的带
for y in range(700, 1080, 10):
    row = g[y, 120:990]
    print("y%4d mean=%6.1f std=%6.1f" % (y, row.mean(), row.std()))
