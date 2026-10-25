# -*- coding: utf-8 -*-
"""查 art/items 下图标是否真透明（有 alpha 且四角透明）——面板槽里会出现方块还是浮起来的物件。"""
import os
from PIL import Image

D = r"c:\Users\26464\IdeaProjects\endeavor\art\items"
names = ["多功能军刀", "骑士盔甲", "章鱼尾人身塑像", "越狱工具", "蓝宝石项链", "古希腊长袍",
         "被诅咒的古董", "银之钥", "年少的欢喜", "精心磨制的小刀"]
for n in names:
    p = os.path.join(D, n + ".png")
    if not os.path.exists(p):
        print("%-14s  <缺文件>" % n)
        continue
    im = Image.open(p)
    has_a = im.mode in ("RGBA", "LA") or "transparency" in im.info
    im2 = im.convert("RGBA")
    w, h = im2.size
    corners = [im2.getpixel((0, 0))[3], im2.getpixel((w - 1, 0))[3],
               im2.getpixel((0, h - 1))[3], im2.getpixel((w - 1, h - 1))[3]]
    # 透明像素占比
    a = im2.split()[-1]
    hist = a.histogram()
    trans = sum(hist[:16]) / float(w * h)
    print("%-14s mode=%-4s %dx%d alpha角=%s 近似全透明像素占比=%.1f%%"
          % (n, im.mode, im2.width, im2.height, corners, trans * 100))
