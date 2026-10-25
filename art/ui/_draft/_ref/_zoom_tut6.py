# -*- coding: utf-8 -*-
import os
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
W = os.path.join(REF,'sudan_wiki')
im = Image.open(os.path.join(W,'1300px-Tutorial1-6.jpg')).convert('RGB')
# 右上角：名字 + 特性 + ✕ + 右侧金带
for i,(box,z) in enumerate([((990,110,1300,340),3),((1150,110,1300,360),5)]):
    seg = im.crop(box)
    zz = seg.resize((seg.width*z, seg.height*z), Image.LANCZOS)
    p = os.path.join(REF,'sudan_tut6_右上_%dx_%d.png'%(z,i+1))
    zz.save(p); print(p, zz.size, 'src', box)
