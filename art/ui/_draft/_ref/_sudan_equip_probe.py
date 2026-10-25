# -*- coding: utf-8 -*-
"""苏丹角色面板「道具/装备是怎么放的」—— 高倍取证。

背景：文件 `sudan_放大_装备形态.png` 其实是手牌行（`_sudan_zoom3.py` 裁的是 ali_0402 的
手牌区），名字误导。这里重新裁**角色面板右栏**（名字条正下方），那才是道具出现的地方。

另外扫 ss00..ss06 出联络表，找有没有别的角色面板可交叉验证。

输出：art/ui/_draft/_ref/sudan_面板右栏道具区_5x.png
      art/ui/_draft/_ref/sudan_七张官截_联络表.png
"""
import os

from PIL import Image, ImageDraw, ImageFont

REF = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'
SU = os.path.join(REF, 'sudan')
FONT = r'C:\Windows\Fonts\SIMYOU.TTF'

im = Image.open(os.path.join(SU, 'sudan_ss06.jpg')).convert('RGB')
print('ss06', im.size)

# 名字条 + 其下方的道具/特性行（源坐标，由 sudan_面板_1x.png 反推：crop 偏移 (396,292)）
REG = (1240, 288, 1620, 500)
c = im.crop(REG)
c5 = c.resize((c.width * 5, c.height * 5), Image.LANCZOS)
c5.save(os.path.join(REF, 'sudan_面板右栏道具区_5x.png'))
print('道具区 5x →', c5.size, '源框', REG)

# 顺带把「名字条 + 道具行」单独量一遍：逐行亮像素（窄 x 带 = 名字条那一列）
import numpy as np
g = np.asarray(im.convert('L')).astype(np.float32)
band = g[REG[1]:REG[3], REG[0] + 60:REG[0] + 240]
br = (band > 120).sum(axis=1)
print('--- 右栏窄带逐行亮像素（阈值>120，只列 >3 的行）---')
for i, v in enumerate(br):
    if v > 3:
        print('   y_src %4d  n=%3d' % (REG[1] + i, v))

# ---- 七张官截联络表 ----
files = ['sudan_ss%02d.jpg' % i for i in range(7)]
CW, CH, TH = 300, 200, (288, 162)
cols = 4
rows = (len(files) + cols - 1) // cols
sheet = Image.new('RGB', (cols * CW + 16, rows * (CH + 34) + 16), (30, 28, 26))
d = ImageDraw.Draw(sheet)
f = ImageFont.truetype(FONT, 16)
for i, fn in enumerate(files):
    p = os.path.join(SU, fn)
    t = Image.open(p).convert('RGB')
    t = t.resize(TH, Image.LANCZOS)
    x = 8 + (i % cols) * CW
    y = 8 + (i // cols) * (CH + 34)
    sheet.paste(t, (x, y))
    d.text((x, y + TH[1] + 6), '%s  %dx%d' % (fn, Image.open(p).size[0], Image.open(p).size[1]),
           font=f, fill=(226, 214, 192))
sheet.save(os.path.join(REF, 'sudan_七张官截_联络表.png'))
print('联络表 →', sheet.size)
