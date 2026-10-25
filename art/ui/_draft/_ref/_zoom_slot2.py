# -*- coding: utf-8 -*-
import os
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
im = Image.open(os.path.join(REF,'sudan','sudan_ss04.jpg')).convert('RGB')
SEGS = [(120,400),(400,680),(680,960)]
for i,(a,b) in enumerate(SEGS):
    seg = im.crop((a, 852, b, 945))
    z = seg.resize((seg.width*5, seg.height*5), Image.LANCZOS)
    p = os.path.join(REF, 'sudan_卡顶右上角_5x_%d.png'%(i+1))
    z.save(p); print(p, z.size)
