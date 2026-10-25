# -*- coding: utf-8 -*-
"""批量裁切放大 → 直接出联络表（一眼看多张）。"""
import os, sys, glob
from PIL import Image, ImageDraw, ImageFont

JOBS = [
    # (src, x0,y0,x1,y1, scale, label)
    (r"wangzhe\wxq_13.png", 0, 0, 0, 0, 2.2, "万象棋 r1_card 棋子卡条"),
    (r"wangzhe\wxq_14.png", 0, 0, 0, 0, 1.5, "万象棋 香香棋手"),
    (r"wangzhe\wxq_05.png", 0, 0, 0, 0, 1.6, "万象棋 p2_img3"),
    (r"wangzhe\wxq_07.png", 0, 0, 0, 0, 0.7, "万象棋 p3_img5"),
    (r"wangzhe\wxq_09.png", 0, 0, 0, 0, 0.7, "万象棋 p3_img3"),
    (r"wangzhe\wxq_11.png", 0, 0, 0, 0, 0.7, "万象棋 p3_img1"),
    (r"wangzhe\wxq_06.png", 0, 0, 0, 0, 0.7, "万象棋 p3_img"),
    (r"yueyuan\yueyuan_ss00.jpg", 620, 690, 1080, 1080, 2.0, "月圆之夜 选牌"),
    (r"yueyuan\yueyuan_ss01.jpg", 660, 660, 1120, 1080, 2.0, "月圆之夜 战斗卡"),
    (r"yueyuan\yueyuan_ss04.jpg", 300, 300, 800, 800, 1.6, "月圆之夜 图腾选择"),
    (r"morimens\morimens_ss03.jpg", 355, 862, 905, 1080, 2.6, "忘却前夜 手牌"),
    (r"morimens\morimens_ss04.jpg", 700, 300, 1250, 800, 1.6, "忘却前夜 事件卡"),
]

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
OUTD = os.path.join(BASE, "crops")
os.makedirs(OUTD, exist_ok=True)

def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

made = []
for i, (rel, x0, y0, x1, y1, sc, label) in enumerate(JOBS):
    p = os.path.join(BASE, rel)
    if not os.path.exists(p):
        print("MISS", rel); continue
    im = Image.open(p).convert("RGB")
    W, H = im.size
    if x1 == 0: x1 = W
    if y1 == 0: y1 = H
    c = im.crop((x0, y0, min(x1, W), min(y1, H)))
    c = c.resize((max(1,int(c.size[0]*sc)), max(1,int(c.size[1]*sc))), Image.LANCZOS)
    dst = os.path.join(OUTD, "crop%02d.png" % i)
    c.save(dst)
    made.append((label, dst, c.size))
    print("OK %-24s %dx%d -> %s" % (label, c.size[0], c.size[1], os.path.basename(dst)))

# 联络表
CH, GAP, PAD, LAB, COLS = 420, 22, 28, 32, 3
rows = (len(made) + COLS - 1) // COLS
CW = int(CH * 2.0)
sheet = Image.new("RGB", (PAD*2 + COLS*CW + (COLS-1)*GAP, PAD*2 + rows*(LAB+CH) + (rows-1)*GAP), (240,238,234))
d = ImageDraw.Draw(sheet); f = font(19)
for i, (label, path, sz) in enumerate(made):
    r, c = divmod(i, COLS)
    x = PAD + c*(CW+GAP); y = PAD + r*(LAB+CH+GAP)
    th = Image.open(path)
    s = min(CH/th.size[1], CW/th.size[0])
    th = th.resize((max(1,int(th.size[0]*s)), max(1,int(th.size[1]*s))), Image.LANCZOS)
    d.text((x, y), label, fill=(30,28,26), font=f)
    sheet.paste(th, (x + (CW-th.size[0])//2, y + LAB))
sheet.save(os.path.join(BASE, "sheet_ref_cards.png"))
print("SAVED sheet_ref_cards.png", sheet.size)
