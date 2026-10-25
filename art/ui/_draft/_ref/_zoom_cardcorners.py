# -*- coding: utf-8 -*-
import os
from PIL import Image, ImageDraw, ImageFont
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
FONT = r'C:/Windows/Fonts/SIMYOU.TTF'
im = Image.open(os.path.join(REF,'sudan','sudan_ss03.jpg')).convert('RGB')
# 单卡整体 + 卡顶两个角
CARDS = [('娜依拉', 246, 284), ('热娜', 289, 327), ('贝姬夫人', 332, 370), ('哈桑', 375, 413), ('2P', 418, 456)]
Z = 8
CW, CH = 240, 560
sheet = Image.new('RGB', (len(CARDS)*(CW+12)+12, CH+34), (28,26,24))
d = ImageDraw.Draw(sheet); f = ImageFont.truetype(FONT, 15)
for i,(name,x0,x1) in enumerate(CARDS):
    seg = im.crop((x0-4, 796, x1+4, 796+68))
    z = seg.resize((seg.width*Z, seg.height*Z), Image.LANCZOS)
    if z.width > CW: z = z.resize((CW, int(z.height*CW/z.width)), Image.LANCZOS)
    X = 12+i*(CW+12)
    sheet.paste(z, (X, 12+ (CH-z.height)//2 ))
    d.text((X, 12+CH+4), '%s  源x%d..%d'%(name,x0,x1), font=f, fill=(226,214,192))
sheet.save(os.path.join(REF, 'sudan_单卡卡顶_8x_对照.png'))
print(sheet.size)
