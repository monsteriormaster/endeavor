# -*- coding: utf-8 -*-
import os
from PIL import Image, ImageDraw, ImageFont
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
FONT = r'C:/Windows/Fonts/SIMYOU.TTF'
im = Image.open(os.path.join(REF,'sudan','sudan_ss03.jpg')).convert('RGB')
CARDS=[('娜依拉',264,350),('热娜',366,451),('贝姬夫人',468,555),('哈桑',570,657),('2P',672,759)]
Y0,Y1 = 838, 940
Z=5; CW,CH=430,520
sheet = Image.new('RGB',(len(CARDS)*(CW+10)+10, CH+32),(28,26,24))
d=ImageDraw.Draw(sheet); f=ImageFont.truetype(FONT,15)
for i,(n,a,b) in enumerate(CARDS):
    seg=im.crop((a-3,Y0,b+3,Y1))
    z=seg.resize((seg.width*Z, seg.height*Z), Image.LANCZOS)
    if z.width>CW: z=z.resize((CW,int(z.height*CW/z.width)),Image.LANCZOS)
    X=10+i*(CW+10)
    sheet.paste(z,(X,10+(CH-z.height)//2))
    d.text((X,10+CH+2),'%s x%d..%d'%(n,a,b),font=f,fill=(226,214,192))
sheet.save(os.path.join(REF,'sudan_单卡卡顶带_5x_对照.png'))
print(sheet.size)
