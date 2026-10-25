# -*- coding: utf-8 -*-
import os
import numpy as np
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
im = Image.open(os.path.join(REF,'sudan','sudan_ss03.jpg')).convert('L')
g = np.asarray(im).astype(np.float32)
band = g[856:885, :]
cols = (band > 70).sum(axis=0)
runs=[]; s=None
for x,v in enumerate(cols):
    if v>=6 and s is None: s=x
    elif v<6 and s is not None:
        if x-s>18: runs.append((s,x-1))
        s=None
print("卡列区间(x 首..末, 宽):")
for a,b in runs: print("   %4d..%4d  w=%d" % (a,b,b-a+1))
