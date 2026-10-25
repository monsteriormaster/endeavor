# -*- coding: utf-8 -*-
"""把 ss06 角色面板「名字牌 + 下方道具 chip」放到 8x，量出 chip 的真实形态与尺寸。"""
import os

from PIL import Image, ImageDraw, ImageFont

REF = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'
FONT = r'C:\Windows\Fonts\SIMYOU.TTF'
im = Image.open(os.path.join(REF, 'sudan', 'sudan_ss06.jpg')).convert('RGB')

# 名字牌 + 道具 chip（源坐标由 5x 探针反推：名字带 y320..345，chip 带 y357..397）
box = (1265, 300, 1450, 410)
c = im.crop(box)
c8 = c.resize((c.width * 8, c.height * 8), Image.LANCZOS)
c8.save(os.path.join(REF, 'sudan_名字牌与道具chip_8x.png'))
print('8x →', c8.size, '源框', box)

# 沿 chip 那一行扫列，量出 [图标] 与 [文字] 各自的 x 跨度
import numpy as np
g = np.asarray(im.convert('L')).astype(np.float32)
row = g[352:400, 1265:1450]
col = (row > 130).sum(axis=0)
on = [x for x in range(col.shape[0]) if col[x] > 0]
if on:
    runs, s0, prev = [], on[0], on[0]
    for x in on[1:]:
        if x - prev > 4:
            runs.append((s0, prev))
            s0 = x
        prev = x
    runs.append((s0, prev))
    print('--- chip 行内元素列跨度（源坐标）---')
    for a, b in runs:
        print('   x %4d..%4d  宽 %3d' % (1265 + a, 1265 + b, b - a + 1))

# 竖直方向量 chip 的高度
vr = (g[300:430, 1290:1310] > 130).sum(axis=1)
print('--- 图标列 x1290..1310 逐行亮像素 ---')
seg = [(300 + i, int(v)) for i, v in enumerate(vr) if v > 0]
if seg:
    print('   y %d..%d（高 %d）' % (seg[0][0], seg[-1][0], seg[-1][0] - seg[0][0] + 1))
