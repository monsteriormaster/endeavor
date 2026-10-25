# -*- coding: utf-8 -*-
import os
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
for ss, xs in (('ss04',(200,1000)),('ss03',(200,1000))):
    im = Image.open(os.path.join(REF,'sudan','sudan_%s.jpg'%ss)).convert('RGB')
    seg = im.crop((xs[0], 745, xs[1], 1075))
    z = seg.resize((int(seg.width*1.85), int(seg.height*1.85)), Image.LANCZOS)
    p = os.path.join(REF, 'sudan_%s_整卡行.png'%ss)
    z.save(p); print(p, z.size)
