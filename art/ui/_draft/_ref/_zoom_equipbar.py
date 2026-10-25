# -*- coding: utf-8 -*-
import os
from PIL import Image
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
W = os.path.join(REF,'sudan_wiki')
jobs = [('1300px-Tutorial1-1.jpg', (900, 45, 1075, 135), 7, 'tut1_1_装备栏'),
        ('d985uqbcdi15y4o3qlvj6ophbpvkktf.jpg', (520, 0, 760, 45), 7, 'falaJie_装备栏'),
        ('1300px-Tutorial1-1.jpg', (895, 40, 1300, 200), 3, 'tut1_1_右上全景')]
for fn, box, z, tag in jobs:
    im = Image.open(os.path.join(W, fn)).convert('RGB')
    seg = im.crop(box)
    zz = seg.resize((seg.width*z, seg.height*z), Image.LANCZOS)
    p = os.path.join(REF, 'sudan_%s_%dx.png' % (tag, z))
    zz.save(p); print(p, zz.size, 'src', box)
