# -*- coding: utf-8 -*-
"""白底可行性判定 v2：10 个素材 × 白/暗/骨 三种卡身，2.5x，同尺寸可直读。"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
IT = lambda n: os.path.join(R, "art", "items", n + ".png")

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

SC = 2.5
CW, CH = int(90 * SC), int(159 * SC)
M_SIDE, M_TOP, M_BOT = 6, 6, 4
NAME_H = 2 * 14 * 1.23
ART_BOX = (M_SIDE, M_TOP + NAME_H + 4, 90 - M_SIDE, 159 - M_BOT)

GROUNDS = [
    ("白面 W", (255, 255, 255), (46, 33, 23), (150, 88, 30)),
    ("暗匣 A", (74, 55, 43), (250, 238, 214), (196, 158, 84)),
    ("骨面 B", (231, 222, 202), (58, 42, 26), (170, 140, 70)),
]

ITEMS = [("朱利安", os.path.join(R, "art", "hero.png")), ("蓝宝石项链", IT("蓝宝石项链")),
         ("章鱼尾人身塑像", IT("章鱼尾人身塑像")), ("几何原本", IT("几何原本")),
         ("可疑的信", IT("可疑的信")), ("被诅咒的古董", IT("被诅咒的古董")),
         ("银之钥", IT("银之钥")), ("精心磨制的小刀", IT("精心磨制的小刀")),
         ("骑士盔甲", IT("骑士盔甲")), ("物种起源", IT("物种起源"))]

def card(path, bg, text_col, edge):
    S = lambda v: int(round(v * SC))
    c = Image.new("RGB", (CW, CH), bg)
    d = ImageDraw.Draw(c)
    d.rectangle([0, 0, CW - 1, CH - 1], outline=edge, width=max(1, S(1.1)))
    art = Image.open(path).convert("RGBA")
    bw, bh = S(ART_BOX[2] - ART_BOX[0]), S(ART_BOX[3] - ART_BOX[1])
    s = min(bw / art.size[0], bh / art.size[1])
    art = art.resize((max(1, int(round(art.size[0] * s))), max(1, int(round(art.size[1] * s)))), Image.LANCZOS)
    c.paste(art, (S(ART_BOX[0]) + (bw - art.size[0]) // 2, S(ART_BOX[1]) + (bh - art.size[1]) // 2), art)
    return c

CP, CG, RG = 34, 16, 46
TITLE = 120
W = CP * 2 + len(ITEMS) * (CW + CG) - CG
H = TITLE + len(GROUNDS) * (CH + RG + 40) + 20
sh = Image.new("RGB", (W, H), (152, 155, 160))
d = ImageDraw.Draw(sh)
d.text((CP, 16), "白底可行性判定 —— 同一素材 × 白/暗/骨 三种卡身（%.1fx，等比）" % SC, fill=(255, 255, 255), font=font(26, True))
d.text((CP, 56), "看两件事：① 素材在哪种底上最立得住；② 白卡身和羊皮纸货架（#E1D1B8）的分离度", fill=(226, 228, 232), font=font(16))
f3 = font(16)
for gi, (lab, bg, tc, ec) in enumerate(GROUNDS):
    y = TITLE + gi * (CH + RG + 40)
    d.text((CP, y - 30), lab, fill=(255, 255, 255), font=font(19, True))
    for i, (n, p) in enumerate(ITEMS):
        x = CP + i * (CW + CG)
        sh.paste(card(p, bg, tc, ec), (x, y))
        if gi == 0:
            d.text((x + CW // 2, y + CH + 6), n, fill=(255, 255, 255), font=f3, anchor="ma")
sh.save(os.path.join(BASE, "白底可行性判定.png"))
print("SAVED 白底可行性判定.png", sh.size)
