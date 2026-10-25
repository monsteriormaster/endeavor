# -*- coding: utf-8 -*-
"""量化两件事：
① 「脏不脏」= 卡身空白区的亮度标准差（越大越花）
② 「名字区和立绘区分不分得开」= 名字带平均亮度 − 立绘区顶部平均亮度（越大越分得开）
"""
import os, runpy, statistics
from PIL import Image

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
ns = runpy.run_path(os.path.join(BASE, "_designB.py"))
render, KEYS = ns["render"], ns["KEYS"]
HERO = os.path.join(R, "art", "hero.png")


def meanbox(im, sc, x0, y0, x1, y1):
    px = im.load()
    v = []
    for y in range(int(y0 * sc), int(y1 * sc)):
        for x in range(int(x0 * sc), int(x1 * sc)):
            r, g, b = px[x, y]
            v.append(0.299 * r + 0.587 * g + 0.114 * b)
    return statistics.mean(v), statistics.pstdev(v)


print("候选   卡身空白(均亮/标准差)   名字带   带下   Δ带下-带   判定")
print("-" * 78)
for k in KEYS:
    im = render(k, HERO, "朱利安", 3).convert("RGB")
    m0, sd = meanbox(im, 3, 6.8, 21.0, 15.0, 36.0)     # 名字带左侧空白（避开角饰/线/字）
    mb, _ = meanbox(im, 3, 6.8, 21.0, 15.0, 36.0)
    mt, _ = meanbox(im, 3, 6.8, 46.0, 15.0, 61.0)       # 立绘区顶部左侧空白
    d = mb - mt
    if sd < 0.6: t1 = "均匀"
    elif sd < 2.5: t1 = "有纹理"
    else: t1 = "★花"
    if abs(d) < 2.0: t2 = "两区同色（靠线/无分隔）"
    elif abs(d) < 8.0: t2 = "轻微分开"
    else: t2 = "明显分开"
    print("%-5s %7.2f / %5.2f        %6.1f  %6.1f   %+6.1f    %s / %s" % (k, m0, sd, mb, mt, d, t1, t2))
