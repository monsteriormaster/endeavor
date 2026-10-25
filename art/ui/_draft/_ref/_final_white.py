# -*- coding: utf-8 -*-
"""白面定案候选：墨键线贴死卡缘的三种厚度 × （4x 边缘放大 + 1x 真实货架）。"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
IT = lambda n: os.path.join(R, "art", "items", n + ".png")
HERO = os.path.join(R, "art", "hero.png")

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

M_SIDE, M_TOP, M_BOT = 6, 6, 4
NAME_H = 2 * 14 * 1.23
ART_BOX = (M_SIDE, M_TOP + NAME_H + 4, 90 - M_SIDE, 159 - M_BOT)
CONT_W = 90 - 2 * M_SIDE
W_ = (255, 255, 255)

# 墨线全部贴死卡缘（ins 0.5，宽 1.1px = 1x 下正好一整像素）
SPEC = {
    "A":  dict(body=(74, 55, 43), hi=(126, 94, 73), lo=(41, 30, 23), text=(250, 238, 214),
               lines=[(3.4, (196, 158, 84), 0.9), (4.5, (26, 18, 13), 0.45), (5.2, (238, 196, 110), 0.6)]),
    "P1": dict(body=W_, hi=W_, lo=(186, 190, 196), text=(46, 33, 23),
               lines=[(0.5, (40, 26, 14), 1.1), (2.4, (246, 206, 74), 0.6)]),
    "P2": dict(body=W_, hi=W_, lo=(186, 190, 196), text=(46, 33, 23),
               lines=[(0.5, (34, 22, 12), 1.9), (2.6, (246, 206, 74), 0.7)]),
    "P3": dict(body=W_, hi=W_, lo=(186, 190, 196), text=(46, 33, 23),
               # 三层：墨键线 + 金发丝 + 一档更淡的琥珀，凑出 AI 那条的层次但墨线在外
               lines=[(0.5, (40, 26, 14), 1.15), (2.3, (246, 206, 74), 0.6), (3.4, (150, 88, 30), 0.45)]),
}
LAB = {"A": "A 暗匣（现方案对照）", "P1": "P1 墨键线 1.1px + 金 0.6px",
       "P2": "P2 墨键线 1.9px（更重）", "P3": "P3 墨键线 + 金 + 淡琥珀（三层）"}

def render(key, path, nm, sc):
    S = lambda v: int(round(v * sc))
    CW, CH = 90 * sc, 159 * sc
    p = SPEC[key]
    c = Image.new("RGB", (CW, CH), p["body"])
    d = ImageDraw.Draw(c)
    d.rectangle([0, 0, CW - 1, S(1.4) - 1], fill=p["hi"])
    d.rectangle([0, 0, S(1.4) - 1, CH - 1], fill=p["hi"])
    d.rectangle([0, CH - S(1.8), CW - 1, CH - 1], fill=p["lo"])
    d.rectangle([CW - S(1.8), 0, CW - 1, CH - 1], fill=p["lo"])
    for ins, col, w in p["lines"]:
        d.rectangle([S(ins), S(ins), CW - 1 - S(ins), CH - 1 - S(ins)], outline=col, width=max(1, S(w)))
    art = Image.open(path).convert("RGBA")
    bw, bh = S(ART_BOX[2] - ART_BOX[0]), S(ART_BOX[3] - ART_BOX[1])
    s = min(bw / art.size[0], bh / art.size[1])
    art = art.resize((max(1, int(round(art.size[0] * s))), max(1, int(round(art.size[1] * s)))), Image.LANCZOS)
    c.paste(art, (S(ART_BOX[0]) + (bw - art.size[0]) // 2, S(ART_BOX[1]) + (bh - art.size[1]) // 2), art)
    d = ImageDraw.Draw(c)
    f = font(S(14), True)
    per = max(1, int(CONT_W // (14 + 1.5)))
    lines = [nm[i:i + per] for i in range(0, len(nm), per)] or [""]
    lh = 14 * 1.23
    top = M_TOP + (NAME_H - len(lines) * lh) / 2.0
    for i, ln in enumerate(lines):
        d.text((S(45), S(top + lh * (i + 0.5))), ln, fill=p["text"], font=f, anchor="mm")
    return c

paper = Image.open(os.path.join(R, "art", "ui", "paper_tile.png")).convert("RGB")
pw, ph = paper.size
SHELF_W, SHELF_H = 1880, 238
ITEMS13 = [("朱利安", HERO), ("蓝宝石项链", IT("蓝宝石项链")), ("章鱼尾人身塑像", IT("章鱼尾人身塑像")),
           ("几何原本", IT("几何原本")), ("骑士盔甲", IT("骑士盔甲")), ("物种起源", IT("物种起源")),
           ("银之钥", IT("银之钥")), ("古希腊长袍", IT("古希腊长袍")), ("可疑的信", IT("可疑的信")),
           ("爱的艺术", IT("爱的艺术")), ("越狱工具清单", IT("越狱工具清单")),
           ("精心磨制的小刀", IT("精心磨制的小刀")), ("被诅咒的古董", IT("被诅咒的古董"))]

def shelf(key):
    band = Image.new("RGB", (SHELF_W, SHELF_H))
    for y in range(0, SHELF_H, ph):
        for x in range(0, SHELF_W, pw):
            band.paste(paper, (x, y))
    ov = Image.new("RGBA", band.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    for y in range(2, 18):
        od.line([(2, y), (SHELF_W - 3, y)], fill=(20, 15, 8, int(0.36 * 255 * (1 - (y - 2) / 16.0))))
    band = Image.alpha_composite(band.convert("RGBA"), ov).convert("RGB")
    d = ImageDraw.Draw(band)
    d.rectangle([0, 0, SHELF_W - 1, SHELF_H - 1], outline=(115, 85, 37), width=2)
    d.rectangle([102, 14, 103, SHELF_H - 15], fill=(115, 85, 37))
    d.rectangle([1638, 14, 1639, SHELF_H - 15], fill=(115, 85, 37))
    for ci, (nm, p) in enumerate(ITEMS13):
        band.paste(render(key, p, nm, 1), (120 + ci * 108, 39))
    return band

KEYS = ["A", "P1", "P2", "P3"]
CP, CG = 34, 20
sh = Image.new("RGB", (1920 + 20, 40 + len(KEYS) * 300), (150, 153, 158))
d = ImageDraw.Draw(sh)
for i, k in enumerate(KEYS):
    y = 40 + i * 300
    d.text((CP, y - 26), LAB[k], fill=(255, 255, 255), font=font(19, True))
    sh.paste(shelf(k), (CP, y))
sh.save(os.path.join(BASE, "白面定案候选_货架.png"))
print("SAVED 白面定案候选_货架.png", sh.size)

CW4 = 46 * 4
sh2 = Image.new("RGB", (CP * 2 + len(KEYS) * (CW4 + CG) - CG, 100 * 4 + 190), (128, 131, 136))
d2 = ImageDraw.Draw(sh2)
d2.text((CP, 16), "边缘 4x 放大 —— 墨键线贴死卡缘后，白卡的「轮廓」成不成立（左上 46×100）",
        fill=(255, 255, 255), font=font(23, True))
for i, k in enumerate(KEYS):
    x = CP + i * (CW4 + CG)
    im = render(k, HERO, "朱利安", 4).crop((0, 0, CW4, 400))
    sh2.paste(im, (x, 66))
    d2.text((x, 66 + 400 + 12), LAB[k].split("（")[0], fill=(255, 255, 255), font=font(17, True))
sh2.save(os.path.join(BASE, "白面定案候选_边缘4x.png"))
print("SAVED 白面定案候选_边缘4x.png", sh2.size)
