# -*- coding: utf-8 -*-
"""把 wiki 的 9 枚装备槽图标拼成一张放大对照板（含像素尺寸标注）。"""
import os
from PIL import Image, ImageDraw, ImageFont
W = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref/sudan_wiki'
REF = r'C:/Users/26464/IdeaProjects/endeavor/art/ui/_draft/_ref'
FONT = r'C:/Windows/Fonts/SIMYOU.TTF'
ORDER = ["Equip_slot","Weapon_equip","Weapon_unequip","Attire_equip","Attire_unequip",
         "Accessory_equip","Accessory_unequip","Animal_equip","Animal_unequip"]
Z = 6
CELL = 160
cols = 5
rows = (len(ORDER)+cols-1)//cols
sheet = Image.new('RGB', (cols*CELL+20, rows*(CELL+30)+20), (238,233,222))
d = ImageDraw.Draw(sheet)
f = ImageFont.truetype(FONT, 15)
for i,n in enumerate(ORDER):
    p = os.path.join(W, n+'.png')
    im = Image.open(p).convert('RGBA')
    print("%-20s %s" % (n, im.size))
    bg = Image.new('RGBA', im.size, (255,255,255,255))
    im = Image.alpha_composite(bg, im).convert('RGB')
    z = im.resize((im.width*Z, im.height*Z), Image.NEAREST)
    if z.width > CELL-16: z = z.resize((CELL-16, int(z.height*(CELL-16)/z.width)), Image.LANCZOS)
    if z.height > CELL-16: z = z.resize((int(z.width*(CELL-16)/z.height), CELL-16), Image.LANCZOS)
    x = 10+(i%cols)*CELL; y = 10+(i//cols)*(CELL+30)
    sheet.paste(z, (x+(CELL-16-z.width)//2, y+(CELL-16-z.height)//2))
    d.rectangle([x-2,y-2,x+CELL-18,y+CELL-18], outline=(190,170,140))
    d.text((x, y+CELL-14), "%s  %dx%d" % (n, Image.open(p).size[0], Image.open(p).size[1]), font=f, fill=(60,45,30))
sheet.save(os.path.join(REF, 'sudan_wiki_装备槽图标对照_6x.png'))
print("→", sheet.size)
