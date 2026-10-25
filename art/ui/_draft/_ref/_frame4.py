# -*- coding: utf-8 -*-
"""卡框 v3：A 暗 / B 骨 / W 白，三种材质共用同一套 v2 几何，只有颜色不同。
W 的描边按白版原图实测（细金线 ≈1.1px @ 90px 卡宽，内缩 ≈3.4px）重建。
另外出：1x 真实尺寸检验 + 真实货架上下文（paper_tile 平铺 + 铜边 + 13 张真卡）。"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

def mix(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)

# ===== 真实几何（1x px；与改后的 card_chip.gd 一一对应）=====
M_SIDE, M_TOP, M_BOT = 6, 6, 4
NAME_LINES, NAME_FONT = 2, 14
LINE_H = 14 * 1.23
SEP = 4
CARD_W, CARD_H = 90, 159
CONTENT = (M_SIDE, M_TOP, CARD_W - M_SIDE, CARD_H - M_BOT)
NAME_H = NAME_LINES * LINE_H
ART_BOX = (M_SIDE, M_TOP + NAME_H + SEP, CARD_W - M_SIDE, CARD_H - M_BOT)

# W 描边实测（原图卡宽 727 → 1x 90）：3 条线，总厚 ~1.1px，内缩 3.4px
THIN = [
    dict(ins=3.4, col=(150,  88, 30), w=0.90),   # 外：琥珀棕
    dict(ins=4.5, col=( 58,  30,  8), w=0.45),   # 中：近黑压线
    dict(ins=5.2, col=(250, 210,  72), w=0.60),  # 内：亮金发丝
]
# 对照用粗框（= 之前 A/B 用的 2.4px 那条）
THICK = [
    dict(ins=0.8, col=(196, 158,  84), w=1.30),
    dict(ins=2.1, col=(196, 158,  84), w=0.60),
    dict(ins=3.0, col=( 26,  18,  13), w=0.50),
]

COL = {
    "A": dict(label="A 暗匣", body=(74, 55, 43), hi=(126, 94, 73), lo=(41, 30, 23),
              border=THIN, bcol=[(196,158,84),(26,18,13),(238,196,110)], text=(250, 238, 214)),
    "B": dict(label="B 同族", body=(231, 222, 202), hi=(250, 245, 232), lo=(185, 177, 162),
              border=THICK, bcol=[(170,140,70),(104,74,44),(210,180,110)], text=(58, 42, 26)),
    "W": dict(label="W 白面", body=(255, 255, 255), hi=(255, 255, 255), lo=(184, 188, 194),
              border=THIN, bcol=[(150,88,30),(58,30,8),(250,210,72)], text=(46, 33, 23)),
    "T": dict(label="T 白面·粗框", body=(255, 255, 255), hi=(255, 255, 255), lo=(184, 188, 194),
              border=THICK, bcol=[(196,158,84),(26,18,13),(238,196,110)], text=(46, 33, 23)),
}

def build(col, sc):
    S = lambda v: int(round(v * sc))
    CW, CH = CARD_W * sc, CARD_H * sc
    im = Image.new("RGB", (CW, CH), col["body"])
    d = ImageDraw.Draw(im)
    # 厚度：顶/左亮，底/右暗
    d.rectangle([0, 0, CW - 1, S(1.4) - 1], fill=col["hi"])
    d.rectangle([0, 0, S(1.4) - 1, CH - 1], fill=col["hi"])
    d.rectangle([0, CH - S(1.8), CW - 1, CH - 1], fill=col["lo"])
    d.rectangle([CW - S(1.8), 0, CW - 1, CH - 1], fill=col["lo"])
    # 边框：逐条按 spec 画（col["bcol"] 覆盖颜色，用于同规格换色）
    for i, ln in enumerate(col["border"]):
        c = col["bcol"][i] if i < len(col["bcol"]) else ln["col"]
        ins, w = ln["ins"], ln["w"]
        d.rectangle([S(ins), S(ins), CW - 1 - S(ins), CH - 1 - S(ins)],
                    outline=c, width=max(1, S(w)))
    return im

def paste_fit(canvas, box, path, sc):
    S = lambda v: int(round(v * sc))
    x0, y0, x1, y1 = box
    bw, bh = S(x1 - x0), S(y1 - y0)
    art = Image.open(path).convert("RGBA")
    s = min(bw / art.size[0], bh / art.size[1])
    art = art.resize((max(1, int(round(art.size[0] * s))), max(1, int(round(art.size[1] * s)))), Image.LANCZOS)
    canvas.paste(art, (S(x0) + (bw - art.size[0]) // 2, S(y0) + (bh - art.size[1]) // 2), art)
    return bw, bh, art.size

def wrap(s, per):
    return [s[i:i + per] for i in range(0, len(s), per)] or [""]

def render(key, art_path, name, sc):
    S = lambda v: int(round(v * sc))
    col = COL[key]
    c = build(col, sc)
    paste_fit(c, ART_BOX, art_path, sc)
    d = ImageDraw.Draw(c)
    f = font(S(NAME_FONT), True)
    per = max(1, int((CONTENT[2] - CONTENT[0]) // (NAME_FONT + 1.5)))
    lines = wrap(name, per)
    lh = NAME_FONT * 1.23
    top = M_TOP + (NAME_H - len(lines) * lh) / 2.0
    for i, ln in enumerate(lines):
        cy = top + lh * (i + 0.5)
        d.text((S(45), S(cy)), ln, fill=col["text"], font=f, anchor="mm")
    return c

HERO = os.path.join(R, "art", "hero.png")
IT = lambda n: os.path.join(R, "art", "items", n + ".png")
NECK, STAT, BOOK = IT("蓝宝石项链"), IT("章鱼尾人身塑像"), IT("几何原本")

print("内容盒 x%d→%d / y%d→%d" % (CONTENT[0], CONTENT[2], CONTENT[1], CONTENT[3]))
print("名字区 y%.1f→%.1f（预留 %d 行 × font%d）" % (M_TOP, M_TOP + NAME_H, NAME_LINES, NAME_FONT))
print("立绘盒 x%d→%d / y%.1f→%.1f = %d × %.1f" % (ART_BOX[0], ART_BOX[2], ART_BOX[1], ART_BOX[3], ART_BOX[2] - ART_BOX[0], ART_BOX[3] - ART_BOX[1]))

CASES = [(HERO, "朱利安"), (NECK, "蓝宝石项链"), (STAT, "章鱼尾人身塑像")]
KEYS = ["A", "B", "W", "T"]

# ============ 出图 1：四材质对照（3x）============
SC = 3
CG, CP, CL = 30, 34, 96
CW3, CH3 = CARD_W * SC, CARD_H * SC
w1 = 3 * CW3 + 2 * CG
sh = Image.new("RGB", (CP * 2 + w1 * len(KEYS) + 40 * (len(KEYS) - 1), CP * 2 + CL + CH3), (240, 238, 233))
d = ImageDraw.Draw(sh)
f2, f3 = font(24, True), font(15)
ys = CP + CL
for i, key in enumerate(KEYS):
    x0 = CP + i * (w1 + 40)
    d.text((x0, CP), "%s —— 名字在上（预留两行）/ 立绘在下 / 只有一条细金属边框" % COL[key]["label"],
           fill=(26, 24, 22), font=f2)
    bw = "1.1px 细金线" if key in ("W",) else ("2.4px" if key in ("B", "T") else "1.1px 细金线")
    d.text((x0, CP + 34), "内容盒 x6→84 y6→155 · 名字区 y6→40 · 立绘盒 78×111 · 边框 %s" % bw,
           fill=(96, 90, 84), font=f3)
    d.text((x0, CP + 56), "字色 %s  卡身 %s" % (COL[key]["text"], COL[key]["body"]),
           fill=(120, 114, 108), font=f3)
    for j, (p, nm) in enumerate(CASES):
        sh.paste(render(key, p, nm, SC), (x0 + j * (CW3 + CG), ys))
sh.save(os.path.join(BASE, "卡面v3_四材质对照_3x.png"))
print("SAVED 卡面v3_四材质对照_3x.png", sh.size)

# ============ 出图 2：1x 真实尺寸 ============
scales = [1, 2, 3, 4]
rows = {k: [render(k, HERO, "朱利安", s) for s in scales] for k in KEYS}
rows["W"] += [render("W", STAT, "章鱼尾人身塑像", 1), render("W", STAT, "章鱼尾人身塑像", 3)]
TITLE_H = 96
Hmax = max(im.size[1] for v in rows.values() for im in v)
W2 = max(sum(im.size[0] for im in v) + 26 * (len(v) - 1) for v in rows.values())
sh2 = Image.new("RGB", (CP * 2 + W2, CP * 2 + TITLE_H + (Hmax + 52) * len(KEYS)), (216, 206, 186))
d2 = ImageDraw.Draw(sh2)
f4, f5 = font(23, True), font(15)
d2.text((CP, CP), "v3 真实尺寸检验 —— 1x 就是游戏里卡位的实际大小（90×159）",
        fill=(46, 38, 30), font=f4)
LAB = {0: "1x（实尺）", 1: "2x", 2: "3x", 3: "4x", 4: "1x 长名", 5: "3x 长名"}
for k, key in enumerate(KEYS):
    base_y = CP + TITLE_H + k * (Hmax + 52)
    d2.text((CP, base_y - 24), "%s：%s" % (COL[key]["label"], " / ".join(LAB[i] for i in range(len(rows[key])))),
            fill=(84, 72, 58), font=f5)
    x = CP
    for im in rows[key]:
        sh2.paste(im, (x, base_y + (Hmax - im.size[1])))
        x += im.size[0] + 26
sh2.save(os.path.join(BASE, "卡面v3_真实尺寸检验.png"))
print("SAVED 卡面v3_真实尺寸检验.png", sh2.size)

# ============ 出图 3：真实货架上下文 ============
paper = Image.open(os.path.join(R, "art", "ui", "paper_tile.png")).convert("RGB")
pw, ph = paper.size
SHELF_W, SHELF_H = 1880, 238
f6 = font(20, True); f7 = font(14)

ITEMS13 = [("朱利安", HERO), ("蓝宝石项链", NECK), ("章鱼尾人身塑像", STAT), ("几何原本", BOOK),
           ("骑士盔甲", IT("骑士盔甲")), ("物种起源", IT("物种起源")), ("银之钥", IT("银之钥")),
           ("古希腊长袍", IT("古希腊长袍")), ("可疑的信", IT("可疑的信")), ("爱的艺术", IT("爱的艺术")),
           ("越狱工具清单", IT("越狱工具清单")), ("精心磨制的小刀", IT("精心磨制的小刀")),
           ("被诅咒的古董", IT("被诅咒的古董"))]
missing = [n for n, p in ITEMS13 if not os.path.exists(p)]
print("缺素材:", missing)
SHELF_KEYS = [k for k in KEYS if k in ("A", "W")]
sh3 = Image.new("RGB", (1880 + 40, CP + 60 + (SHELF_H + 74) * len(SHELF_KEYS)), (165, 168, 172))
d3 = ImageDraw.Draw(sh3)
d3.text((CP, 14), "真实货架上下文（1x 实尺）—— 货架 = paper_tile 平铺 + 2px 铜边 + 内阴影，卡位 y39~198",
        fill=(20, 20, 22), font=f6)
for si, key in enumerate(SHELF_KEYS):
    oy = CP + 44 + si * (SHELF_H + 74)
    d3.text((CP, oy - 26), "%s（纸底 hex %s）" % (COL[key]["label"], "#%02X%02X%02X" % paper.resize((1, 1)).getpixel((0, 0))),
            fill=(30, 28, 26), font=f7)
    # 纸底平铺
    band = Image.new("RGB", (SHELF_W, SHELF_H))
    for y in range(0, SHELF_H, ph):
        for x in range(0, SHELF_W, pw):
            band.paste(paper, (x, y))
    # 内阴影 y2~18
    ov = Image.new("RGBA", (SHELF_W, SHELF_H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    for y in range(2, 18):
        a = int(0.36 * 255 * (1 - (y - 2) / 16.0))
        od.line([(2, y), (SHELF_W - 3, y)], fill=(20, 15, 8, a))
    band = Image.alpha_composite(band.convert("RGBA"), ov).convert("RGB")
    # 2px 铜边
    d = ImageDraw.Draw(band)
    d.rectangle([0, 0, SHELF_W - 1, SHELF_H - 1], outline=(115, 85, 37), width=2)
    # 分割线
    d.rectangle([102, 14, 103, SHELF_H - 15], fill=(115, 85, 37))
    d.rectangle([1638, 14, 1639, SHELF_H - 15], fill=(115, 85, 37))
    # 卡（HBox: x120 起，间隔 18）
    for ci, (nm, p) in enumerate(ITEMS13):
        im = render(key, p, nm, 1)
        band.paste(im, (120 + ci * (CARD_W + 18), 39))
    sh3.paste(band, (CP, oy))
sh3.save(os.path.join(BASE, "卡面v3_货架上下文.png"))
print("SAVED 卡面v3_货架上下文.png", sh3.size)
