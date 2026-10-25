# -*- coding: utf-8 -*-
"""苏丹人物面板：1:1 裁切 + 结构分区实测（为「模仿苏丹布局」取证）。

为什么要重做一遍
- 之前 `_panel_cmp_sudan2.py` 量过一遍，但结论只落在诊断板的小字里，且**被裁切**。
- 这次要拿到能直接翻译成我们坐标的东西：**各分区 y 带、主栏/立绘栏的 x 分界、留白比例**。

方法（沿用已验证有效的「窄 x 带 + 亮阈值 + 逐行亮像素计数」）
- 苏丹截图是**深色高纹理**，整幅剖面会被纹理淹掉；只扫「主栏」这一个窄 x 带，并**避开**
  左侧「银」等级章与右侧立绘。
- 先扫**行**得分区带；再在带内扫**列**得横向元素跨度。

输出：art/ui/_draft/_ref/sudan_面板_1x.png      整块 1:1
      art/ui/_draft/_ref/sudan_面板_主栏_2x.png  左侧信息栏 2x
      art/ui/_draft/_ref/sudan_面板_右栏_2x.png  名字+立绘栏 2x
"""
import os

import numpy as np
from PIL import Image

REF = r'C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref'
SRC = os.path.join(REF, 'sudan', 'sudan_ss06.jpg')

im = Image.open(SRC).convert('RGB')
W, H = im.size
g = np.asarray(im.convert('L')).astype(np.float32)
print('源 %dx%d' % (W, H))

# ---- 1) 粗定位面板：找「描述句」那条最亮的通栏横带 ----
band = g[:, 420:1200]                       # 主栏窄带，避开左章与右立绘
bright = (band > 150).sum(axis=1)           # 每行亮像素数（文字/细线会冒尖）
top = [(y, int(bright[y])) for y in range(H) if bright[y] > 60]
print('亮行数 = %d' % len(top))
if top:
    print('第一段亮行 y %d..%d' % (top[0][0], top[-1][0]))
    # 连续段
    segs, s0, prev = [], top[0][0], top[0][0]
    for y, _ in top[1:]:
        if y - prev > 4:
            segs.append((s0, prev))
            s0 = y
        prev = y
    segs.append((s0, prev))
    print('--- 分区带（主栏 x420..1200）---')
    for a, b in segs:
        peak = max(bright[a:b + 1])
        print('   y %4d..%4d  高 %3d  峰值亮像素 %d' % (a, b, b - a + 1, peak))

# ---- 2) 列剖面：在「属性行」带内找横向元素 ----
print('--- 属性行内列剖面 ---')
for name, y0, y1 in (('粗定位前先给全图候选', 0, 0),):
    break
rowband = (560, 615)
sub = g[rowband[0]:rowband[1], :]
col = (sub > 150).sum(axis=0)
on = [x for x in range(W) if col[x] > 0]
if on:
    runs, s0, prev = [], on[0], on[0]
    for x in on[1:]:
        if x - prev > 6:
            runs.append((s0, prev))
            s0 = x
        prev = x
    runs.append((s0, prev))
    for a, b in runs:
        if b - a >= 1:
            print('   x %4d..%4d  宽 %3d' % (a, b, b - a + 1))

# ---- 3) 出图 ----
BOX = (396, 292, 1672, 878)
c = im.crop(BOX)
c.save(os.path.join(REF, 'sudan_面板_1x.png'))
print('整块 →', c.size)
m = im.crop((396, 292, 1250, 878))
m.resize((m.width * 2, m.height * 2), Image.LANCZOS).save(
    os.path.join(REF, 'sudan_面板_主栏_2x.png'))
r = im.crop((1200, 292, 1672, 878))
r.resize((r.width * 2, r.height * 2), Image.LANCZOS).save(
    os.path.join(REF, 'sudan_面板_右栏_2x.png'))
print('主栏 2x / 右栏 2x 已出')
