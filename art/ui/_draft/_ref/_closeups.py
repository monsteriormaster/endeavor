# -*- coding: utf-8 -*-
"""四游戏真实卡面特写对比表 —— 每张都是"对照原图"用的实证素材。"""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
OUTD = os.path.join(BASE, "closeups")
os.makedirs(OUTD, exist_ok=True)

# (src, crop, scale, label)
JOBS = [
    # 苏丹的游戏 —— 底部手牌
    ("sudan/sudan_ss00.jpg",  (0, 780, 1920, 1080), 1.0, "苏丹 手牌行 ss00"),
    ("sudan/sudan_ss04.jpg",  (0, 760, 1920, 1080), 1.0, "苏丹 手牌行 ss04"),
    ("sudan/sudan_ss06.jpg",  (0, 700, 1920, 1080), 1.0, "苏丹 手牌行 ss06"),
    ("sudan/sudan_ss02.jpg",  (0, 0, 1920, 1080),   0.42, "苏丹 整屏 ss02"),
    # 月圆之夜
    ("yueyuan/yueyuan_ss00.jpg", (620, 690, 1080, 1080), 3.0, "月圆 选牌特写"),
    ("yueyuan/yueyuan_ss01.jpg", (660, 660, 1120, 1080), 3.0, "月圆 战斗卡特写"),
    # 忘却前夜
    ("morimens/morimens_ss03.jpg", (355, 862, 905, 1080), 2.8, "忘却 手牌行"),
    # 王者万象棋
    ("wangzhe/wxq_13.png", (0, 0, 1480, 257), 2.0, "万象棋 棋子卡条 r1"),
    ("wangzhe/wxq_17.png", (0, 0, 794, 257),  3.0, "万象棋 棋子卡条 r3"),
]

def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

made = []
for i, (rel, box, sc, label) in enumerate(JOBS):
    p = os.path.join(BASE, rel)
    if not os.path.exists(p):
        print("MISS", rel); continue
    im = Image.open(p).convert("RGB")
    W, H = im.size
    x0, y0, x1, y1 = box
    c = im.crop((max(0,x0), max(0,y0), min(x1,W), min(y1,H)))
    if sc != 1.0:
        c = c.resize((max(1,int(c.size[0]*sc)), max(1,int(c.size[1]*sc))), Image.LANCZOS)
    dst = os.path.join(OUTD, "cu%02d.png" % i)
    c.save(dst)
    made.append((label, dst))
    print("OK %-22s %dx%d" % (label, c.size[0], c.size[1]))

CH, GAP, PAD, LAB, COLS = 400, 20, 26, 30, 2
rows = (len(made) + COLS - 1) // COLS
CW = int(CH * 1.9)
sheet = Image.new("RGB", (PAD*2 + COLS*CW + (COLS-1)*GAP, PAD*2 + rows*(LAB+CH) + (rows-1)*GAP), (238,236,232))
d = ImageDraw.Draw(sheet); f = font(18)
for i, (label, path) in enumerate(made):
    r, c = divmod(i, COLS)
    x = PAD + c*(CW+GAP); y = PAD + r*(LAB+CH+GAP)
    th = Image.open(path)
    s = min(CH/th.size[1], CW/th.size[0])
    th = th.resize((max(1,int(th.size[0]*s)), max(1,int(th.size[1]*s))), Image.LANCZOS)
    d.text((x, y), label, fill=(30,28,26), font=f)
    sheet.paste(th, (x + (CW-th.size[0])//2, y + LAB))
sheet.save(os.path.join(BASE, "sheet_closeups.png"))
print("SAVED sheet_closeups.png", sheet.size)
