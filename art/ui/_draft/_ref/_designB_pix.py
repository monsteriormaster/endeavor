# -*- coding: utf-8 -*-
"""真·1x 像素检验：把 1x 渲染出的卡（上半部）用 NEAREST 放 8 倍。
和 3x 渲染不同 —— 这张看到的是**游戏里真正会显示的像素**，装饰读不出来就是白做。"""
import os, runpy, statistics
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
ns = runpy.run_path(os.path.join(BASE, "_designB.py"))
render, KEYS, LAB, DESC = ns["render"], ns["KEYS"], ns["LAB"], ns["DESC"]
HERO = os.path.join(R, "art", "hero.png")

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

Z = 6                     # 放大倍数
CROP_H = 62               # 1x 下取卡的上 62px（覆盖名字区 + 立绘开头）
PER_ROW = 4
CWz, CHz = 90 * Z, CROP_H * Z
CG, RG = 26, 74
NROW = (len(KEYS) + PER_ROW - 1) // PER_ROW
sh = Image.new("RGB", (34 * 2 + PER_ROW * (CWz + CG) - CG, 108 + NROW * (CHz + RG)), (128, 131, 136))
d = ImageDraw.Draw(sh)
d.text((34, 16), "真·1x 像素放大 %d 倍（NEAREST）—— 这是游戏里实际显示的像素，装饰读不出来就是白做" % Z,
       fill=(255, 255, 255), font=font(23, True))
d.text((34, 48), "每个候选取「上 %dpx」：覆盖名字区（预留两行）+ 立绘开头 + 四角 / 上缘 / 分隔线" % CROP_H,
       fill=(222, 226, 232), font=font(16))
for i, k in enumerate(KEYS):
    col, row = i % PER_ROW, i // PER_ROW
    x = 34 + col * (CWz + CG)
    y = 100 + row * (CHz + RG)
    c1 = render(k, HERO, "朱利安", 1).convert("RGB").crop((0, 0, 90, CROP_H))
    sh.paste(c1.resize((CWz, CHz), Image.NEAREST), (x, y))
    d.text((x, y + CHz + 10), LAB[k], fill=(255, 255, 255), font=font(18, True))
    d.text((x, y + CHz + 36), DESC[k].replace("**", ""), fill=(206, 210, 216), font=font(14))
sh.save(os.path.join(BASE, "卡面B_小设计_1x像素放大8x.png"))
print("SAVED 卡面B_小设计_1x像素放大8x.png", sh.size)
