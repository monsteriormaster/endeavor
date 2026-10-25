# -*- coding: utf-8 -*-
"""货架三方对照：A 暗匣 / W 白面(细金线) / W2 白面(外圈墨键线+内金发丝)。
关键变量 = 卡的"silhouette"（外轮廓键线）能不能在白卡身上成立。"""
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

# 描边 spec：ins = 内缩(1x px)，col/w
SPEC = {
    "A":  dict(body=(74, 55, 43),  hi=(126, 94, 73), lo=(41, 30, 23),   text=(250, 238, 214),
               lines=[(3.4, (196, 158, 84), 0.9), (4.5, (26, 18, 13), 0.45), (5.2, (238, 196, 110), 0.6)]),
    "W":  dict(body=(255, 255, 255), hi=(255, 255, 255), lo=(184, 188, 194), text=(46, 33, 23),
               lines=[(3.4, (150, 88, 30), 0.9), (4.5, (58, 30, 8), 0.45), (5.2, (250, 210, 72), 0.6)]),
    "W2": dict(body=(255, 255, 255), hi=(255, 255, 255), lo=(184, 188, 194), text=(46, 33, 23),
               # 墨键线在外（提供外轮廓），金发丝在内（金属感）
               lines=[(1.6, (46, 30, 16), 1.0), (3.2, (250, 210, 72), 0.65)]),
    "W3": dict(body=(255, 255, 255), hi=(255, 255, 255), lo=(184, 188, 194), text=(46, 33, 23),
               # 再收一点：墨线 1.3px + 金 0.6px，更细更"印刷"
               lines=[(1.4, (52, 34, 18), 1.25), (3.0, (245, 202, 66), 0.6)]),
}
LAB = {"A": "A 暗匣（现方案）", "W": "W 白面·细金线（AI 原样）",
       "W2": "W2 白面·墨键线在外", "W3": "W3 白面·墨键线更细"}

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
        d.rectangle([S(ins), S(ins), CW - 1 - S(ins), CH - 1 - S(ins)],
                    outline=col, width=max(1, S(w)))
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

def shelf(key, sc=1):
    band = Image.new("RGB", (SHELF_W * sc, SHELF_H * sc))
    tile = paper.resize((pw * sc, ph * sc), Image.NEAREST) if sc != 1 else paper
    for y in range(0, band.size[1], tile.size[1]):
        for x in range(0, band.size[0], tile.size[0]):
            band.paste(tile, (x, y))
    ov = Image.new("RGBA", band.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    for y in range(2 * sc, 18 * sc):
        a = int(0.36 * 255 * (1 - (y - 2 * sc) / float(16 * sc)))
        od.line([(2 * sc, y), (band.size[0] - 3 * sc, y)], fill=(20, 15, 8, a))
    band = Image.alpha_composite(band.convert("RGBA"), ov).convert("RGB")
    d = ImageDraw.Draw(band)
    d.rectangle([0, 0, band.size[0] - 1, band.size[1] - 1], outline=(115, 85, 37), width=2 * sc)
    d.rectangle([102 * sc, 14 * sc, 103 * sc, (SHELF_H - 15) * sc], fill=(115, 85, 37))
    d.rectangle([1638 * sc, 14 * sc, 1639 * sc, (SHELF_H - 15) * sc], fill=(115, 85, 37))
    for ci, (nm, p) in enumerate(ITEMS13):
        band.paste(render(key, p, nm, sc), ((120 + ci * 108) * sc, 39 * sc))
    return band

KEYS = ["A", "W", "W2", "W3"]
CP = 34
TITLE = 96
sh = Image.new("RGB", (1880 + CP * 2, TITLE + len(KEYS) * (SHELF_H + 56)), (150, 153, 158))
d = ImageDraw.Draw(sh)
d.text((CP, 16), "货架上下文对照（1x 实尺）—— 白卡面真正的考题是「和羊皮纸货架拉不拉得开」",
       fill=(255, 255, 255), font=font(25, True))
d.text((CP, 56), "货架 = paper_tile(#E1D1B8) 平铺 + 2px 铜边 + 内阴影；卡位 y39~198；同一批 13 张真卡",
       fill=(228, 230, 234), font=font(16))
for i, k in enumerate(KEYS):
    y = TITLE + i * (SHELF_H + 56)
    d.text((CP, y - 26), LAB[k], fill=(255, 255, 255), font=font(19, True))
    sh.paste(shelf(k), (CP, y))
sh.save(os.path.join(BASE, "卡面v3_货架四方对照.png"))
print("SAVED 卡面v3_货架四方对照.png", sh.size)

# 单个卡的边缘放大对照（看 silhouette）
def crop_edge(key, sc=4):
    im = render(key, HERO, "朱利安", sc)
    return im.crop((0, 0, 46 * sc, 100 * sc))
CG = 22
CW4 = 46 * 4
sh2 = Image.new("RGB", (CP * 2 + len(KEYS) * (CW4 + CG) - CG, 100 * 4 + 150), (128, 131, 136))
d2 = ImageDraw.Draw(sh2)
d2.text((CP, 14), "边缘 4x 放大 —— 看白卡的「轮廓」成不成立（左上角 46×100 区域）",
        fill=(255, 255, 255), font=font(22, True))
for i, k in enumerate(KEYS):
    x = CP + i * (CW4 + CG)
    sh2.paste(crop_edge(k), (x, 62))
    d2.text((x, 62 + 400 + 10), LAB[k].split("（")[0], fill=(255, 255, 255), font=font(17, True))
sh2.save(os.path.join(BASE, "卡面v3_边缘4x放大.png"))
print("SAVED 卡面v3_边缘4x放大.png", sh2.size)
