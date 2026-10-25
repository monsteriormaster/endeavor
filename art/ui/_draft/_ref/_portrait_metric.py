# -*- coding: utf-8 -*-
import os
from PIL import Image

R = r"c:\Users\26464\IdeaProjects\endeavor"
for n in ("sansi.png", "hero.png"):
    p = os.path.join(R, "art", n)
    if os.path.exists(p):
        im = Image.open(p)
        print("%-12s %dx%d  比例 w/h=%.4f  高/宽=%.4f" % (n, im.width, im.height,
                                                        im.width / float(im.height),
                                                        im.height / float(im.width)))
    else:
        print(n, "<缺>")

# 卡牌比例
print("card_chip CARD_SIZE 90x159 -> 比例 %.4f" % (90 / 159.0))

# 立绘在不同 box 下的实际尺寸（等比 + 靠右下对齐）
for bw, bh in ((224, 340), (224, 300), (224, 284), (224, 260), (208, 340)):
    src = Image.open(os.path.join(R, "art", "sansi.png"))
    r = min(bw / float(src.width), bh / float(src.height))
    print("box %dx%d -> 立绘 %.0fx%.0f" % (bw, bh, src.width * r, src.height * r))
