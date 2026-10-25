# -*- coding: utf-8 -*-
"""ss05 角色列表面板 + ss06 面板底部条：找「装备/道具是怎么挂到角色上的」。"""
import os

from PIL import Image, ImageDraw, ImageFont

REF = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'
SU = os.path.join(REF, 'sudan')
FONT = r'C:\Windows\Fonts\SIMYOU.TTF'

blocks = []
for tag, fn, box, sc in (
    ('ss05 角色面板 全幅', 'sudan_ss05.jpg', (150, 80, 1080, 700), 1.6),
    ('ss05 行右图标簇 4x', 'sudan_ss05.jpg', (600, 110, 900, 300), 4.0),
    ('ss06 面板底部条 3x', 'sudan_ss06.jpg', (380, 760, 1560, 890), 3.0),
    ('ss06 手牌左段 3x', 'sudan_ss06.jpg', (380, 880, 1000, 1030), 3.0),
):
    im = Image.open(os.path.join(SU, fn)).convert('RGB')
    c = im.crop(box)
    r = c.resize((int(c.width * sc), int(c.height * sc)), Image.LANCZOS)
    blocks.append((tag, r))

PAD, LAB = 14, 30
W = max(b.size[0] for _, b in blocks) + PAD * 2
H = sum(b.size[1] + LAB + PAD for _, b in blocks) + PAD
sheet = Image.new('RGB', (W, H), (26, 24, 22))
d = ImageDraw.Draw(sheet)
f = ImageFont.truetype(FONT, 20)
y = PAD
for nm, b in blocks:
    d.text((PAD, y), nm, font=f, fill=(255, 226, 150))
    y += LAB
    sheet.paste(b, (PAD, y))
    y += b.size[1] + PAD
sheet.save(os.path.join(REF, 'sudan_ss05道具取证.png'))
print('saved', sheet.size)
