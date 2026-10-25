# -*- coding: utf-8 -*-
"""ss04 手牌行：逐卡放大右上角，找装备槽簇。"""
import os
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
im = Image.open(os.path.join(REF,'sudan','sudan_ss04.jpg')).convert('RGB')
# 手牌行上半（含卡顶与右上角）
REG = (120, 405, 990, 500)
c = im.crop(REG)
# 分两段，各放大 4x
mid = (REG[0]+REG[2])//2
for i,(a,b) in enumerate([(REG[0],mid),(mid,REG[2])]):
    seg = im.crop((a, REG[1], b, REG[3]))
    z = seg.resize((seg.width*4, seg.height*4), Image.LANCZOS)
    p = os.path.join(REF, 'sudan_手牌顶行_放大4x_%d.png'%(i+1))
    z.save(p); print(p, z.size, '源 x', a, b)
