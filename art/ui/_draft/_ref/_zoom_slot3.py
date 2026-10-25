# -*- coding: utf-8 -*-
import os
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
im = Image.open(os.path.join(REF,'sudan','sudan_ss03.jpg')).convert('RGB')
# 手牌行：卡顶 + 名字 + 两角小图标
SEGS = [(225,530),(530,840),(840,1150)]
for i,(a,b) in enumerate(SEGS):
    seg = im.crop((a, 790, b, 870))
    z = seg.resize((seg.width*5, seg.height*5), Image.LANCZOS)
    p = os.path.join(REF, 'sudan_ss03_卡顶_5x_%d.png'%(i+1))
    z.save(p); print(p, z.size)
