# -*- coding: utf-8 -*-
"""B 骨面色调上做「小设计」的 6 个候选（B0 = 当前基线）。
方向一：四角发生点事（角饰）；方向二：边框加一层（双线 + 顶中徽记）；
方向三：名字与立绘之间给个分隔（细金线 + 中央菱形）；方向四：材质（纸纹 + 微凹）；
方向五：综合。全部只动「装饰」，不动 v2 几何（内容盒 / 名字预留两行 / 立绘盒）。"""
import os
import random
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

# ===== B 骨面配色（用户选定）=====
BODY = (231, 222, 202)
HI   = (250, 245, 232)
LO   = (185, 177, 162)
BRASS  = (170, 140, 70)
BRASS2 = (206, 176, 104)
INK    = (104, 74, 44)
TEXT   = (58, 42, 26)

M_SIDE, M_TOP, M_BOT = 6, 6, 4
NAME_H = 2 * 14 * 1.23                 # 34.44
CONT = (M_SIDE, M_TOP, 90 - M_SIDE, 159 - M_BOT)
NAMES_Y = (M_TOP, M_TOP + NAME_H)      # 6 → 40.44
ART_BOX = (M_SIDE, M_TOP + NAME_H + 4, 90 - M_SIDE, 159 - M_BOT)   # y 44.44 → 155
CONT_W = 90 - 2 * M_SIDE

# 基线边框（= 现在 B 那条）
BORDER = [(0.8, BRASS, 1.3), (2.1, BRASS, 0.6), (3.0, INK, 0.5)]

# ===== 纸纹：从已实装的 paper_tile 里取真实纸纹（低透明度叠加，不做假噪点）=====
_paper = Image.open(os.path.join(R, "art", "ui", "paper_tile.png")).convert("RGB")

def paper_wash(size, sc, strength):
    """返回一张和卡同尺寸的 RGBA 纸纹层（把 paper_tile 转灰度、中心化、按 strength 混）。"""
    w, h = size
    pw, ph = _paper.size
    t = Image.new("RGB", (w, h))
    for y in range(0, h, ph):
        for x in range(0, w, pw):
            t.paste(_paper, (x, y))
    g = t.convert("L")
    # 拉到以 128 为中心 → 得到 ±delta
    px = g.load()
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            d = (px[x, y] - 150) * strength      # 150 = 纸的基准亮度
            if d > 0:
                a = min(255, int(d * 2.2))
                op[x, y] = (255, 250, 236, a)    # 亮处偏暖白
            else:
                a = min(255, int(-d * 2.2))
                op[x, y] = (120, 96, 62, a)      # 暗处偏棕
    return out

# ===== 装饰绘制（全部按 1x 坐标写，内部 ×sc）=====
def lozenge(d, S, cx, cy, r, col):
    d.polygon([(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))], fill=col)

def corner_brackets(d, S, ins, arm, w, col):
    """四角的 L 形内衬线（英伦装帧的折角线）。"""
    x0, x1, y0, y1 = ins, 90 - ins, ins, 159 - ins
    lw = max(1, S(w))
    for (ax, ay) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        cx = x0 if ax > 0 else x1
        cy = y0 if ay > 0 else y1
        d.rectangle([min(S(cx), S(cx + ax * arm)), min(S(cy), S(cy + lw) - lw), max(S(cx), S(cx + ax * arm)), max(S(cy), S(cy + lw) - lw)], fill=col)
        d.rectangle([min(S(cx), S(cx + lw) - lw), min(S(cy), S(cy + ay * arm)), max(S(cx), S(cx + lw) - lw), max(S(cy), S(cy + ay * arm))], fill=col)

def render(key, path, nm, sc, wash_cache={}):
    S = lambda v: int(round(v * sc))
    CW, CH = 90 * sc, 159 * sc
    c = Image.new("RGB", (CW, CH), BODY)
    d = ImageDraw.Draw(c)

    # 1) 底：B 骨色 + （B4 才有的）纵向 3% 渐变 + 极轻纸纹。注意顺序：先合成底，再画线
    base = Image.new("RGB", (CW, CH), BODY)
    if key == "B4":
        # 名字区一道低调的色调带（比卡身深 ~5.5%），下缘 3px 软过渡。**无任何线条**
        bd = ImageDraw.Draw(base)
        K = 0.945
        band = tuple(int(BODY[j] * K) for j in range(3))
        y_end, fade = 40.0, 3.0
        for y in range(S(2.5), S(y_end + fade)):
            if y <= S(y_end):
                bd.line([(0, y), (CW - 1, y)], fill=band)
            else:
                t = (y - S(y_end)) / float(S(fade))
                col = tuple(int(band[j] * (1 - t) + BODY[j] * t) for j in range(3))
                bd.line([(0, y), (CW - 1, y)], fill=col)
    c = base.copy()
    d = ImageDraw.Draw(c)

    # 2) 厚度：顶/左亮，底/右暗
    d.rectangle([0, 0, CW - 1, S(1.4) - 1], fill=HI)
    d.rectangle([0, 0, S(1.4) - 1, CH - 1], fill=HI)
    d.rectangle([0, CH - S(1.8), CW - 1, CH - 1], fill=LO)
    d.rectangle([CW - S(1.8), 0, CW - 1, CH - 1], fill=LO)

    # 3) 基线边框
    for ins, col, w in BORDER:
        d.rectangle([S(ins), S(ins), CW - 1 - S(ins), CH - 1 - S(ins)], outline=col, width=max(1, S(w)))

    # 4) （B4 的色调带已在 base 阶段画好，这里不再画任何东西）
    if False:
        pass

    # 5) 方向一：四角角饰（折角线收短到 9px，别压到名字）
    if key in ("B1", "B5", "B6"):
        corner_brackets(d, S, 5.0, 9.0, 0.8, BRASS)
        for (cx, cy) in ((3.0, 3.0), (87.0, 3.0), (3.0, 156.0), (87.0, 156.0)):
            lozenge(d, S, cx, cy, 1.7, BRASS2)

    # 6) 方向二：内缘第二道细线 + 顶中徽记（B6 特意不要这条，避免整排卡变重）
    if key in ("B2", "B5"):
        d.rectangle([S(5.0), S(5.0), CW - 1 - S(5.0), CH - 1 - S(5.0)], outline=(150, 122, 60), width=max(1, S(0.45)))
        lozenge(d, S, 45.0, 3.0, 2.4, BRASS2)
        lozenge(d, S, 45.0, 3.0, 1.1, BODY)
        for ax in (1, -1):
            d.rectangle([min(S(45 + ax * 5.0), S(45 + ax * 11.0)), S(2.6), max(S(45 + ax * 5.0), S(45 + ax * 11.0)), S(3.4)], fill=BRASS)

    # 7) 方向三：名字与立绘之间的分隔（细金线 + 中央菱形，两端各一个小点）
    if key in ("B3", "B5", "B6"):
        y = 41.4
        d.rectangle([S(16.0), S(y - 0.28), S(74.0), S(y + 0.28)], fill=BRASS)
        lozenge(d, S, 45.0, y, 2.2, BRASS2)
        lozenge(d, S, 45.0, y, 0.95, BODY)
        for cx in (16.0, 74.0):
            lozenge(d, S, cx, y, 1.05, BRASS)

    # ===== 内容：立绘 + 名字 =====
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
        d.text((S(45), S(top + lh * (i + 0.5))), ln, fill=TEXT, font=f, anchor="mm")
    return c

KEYS = ["B0", "B1", "B2", "B3", "B4", "B5", "B6"]
LAB = {
    "B0": "B0 基线（现在这张）",
    "B1": "B1 四角加折角线 + 铜钉",
    "B2": "B2 内缘第二道细线 + 顶中徽记",
    "B3": "B3 名字／立绘间加细金分隔",
    "B4": "B4 名字区色调带（无线）",
    "B5": "B5 综合（角饰 + 双线徽记 + 名字分隔）",
    "B6": "B6 只有角饰 + 名字分隔 ★",
}
DESC = {
    "B0": "一个平涂米色矩形，一条细线",
    "B1": "四角各一组 L 形折角线（英伦装帧，9px）+ 角点铜钉",
    "B2": "贴边第二道细铜线（双线框）+ 顶中一个小菱形徽记",
    "B3": "**用一条线**：名字区下面一道短金线，正中嵌菱形，两端收小点",
    "B4": "**不用线**：名字区整条比卡身深 5.5% 的色调带，下缘 3px 软过渡",
    "B5": "角饰 + 双线徽记 + 名字分隔全上 —— 看小尺寸下会不会太满",
    "B6": "**角饰 + 名字分隔，不要那道双线框** —— 有装饰但不压重量",
}
CASES = [(HERO, "朱利安"), (IT("蓝宝石项链"), "蓝宝石项链"), (IT("章鱼尾人身塑像"), "章鱼尾人身塑像")]

CP, CG, RG = 34, 22, 46
SC = 3
CW3, CH3 = 90 * SC, 159 * SC

# ============ 出图 1：3x 逐项对照（每个候选 3 张真内容，2 列 × 3 行）============
w1 = 3 * CW3 + 2 * CG
BLK_W, BLK_H = w1, CH3 + 62
NROW = (len(KEYS) + 1) // 2
sh = Image.new("RGB", (CP * 2 + BLK_W * 2 + 56, 118 + NROW * (BLK_H + 44)), (238, 236, 231))
d = ImageDraw.Draw(sh)
d.text((CP, 16), "B 骨面色调 · 卡面「小设计」七版对照（3x）—— 几何完全一致，只加装饰",
       fill=(28, 26, 24), font=font(25, True))
d.text((CP, 58), "内容盒 x6→84 y6→155 · 名字区 y6→40（预留 2 行）· 立绘盒 78×111 · 基线边框 2.4px",
       fill=(96, 90, 84), font=font(16))
d.text((CP, 84), "每版第三张「章鱼尾人身塑像」= 7 字，用来验证两行预留没被装饰挤掉",
       fill=(96, 90, 84), font=font(16))
for k, key in enumerate(KEYS):
    col, row = k % 2, k // 2
    bx = CP + col * (BLK_W + 56)
    by = 118 + row * (BLK_H + 44)
    d.text((bx, by), LAB[key], fill=(30, 28, 26), font=font(21, True))
    d.text((bx + 300, by + 4), DESC[key], fill=(104, 98, 90), font=font(15))
    for j, (p, nm) in enumerate(CASES):
        sh.paste(render(key, p, nm, SC), (bx + j * (CW3 + CG), by + 34))
sh.save(os.path.join(BASE, "卡面B_小设计七版_3x.png"))
print("SAVED 卡面B_小设计七版_3x.png", sh.size)

# ============ 出图 2：真实货架（1x 实尺）============
pw_, ph_ = _paper.size
SHELF_W, SHELF_H = 1880, 238
ITEMS13 = [("朱利安", HERO), ("蓝宝石项链", IT("蓝宝石项链")), ("章鱼尾人身塑像", IT("章鱼尾人身塑像")),
           ("几何原本", IT("几何原本")), ("骑士盔甲", IT("骑士盔甲")), ("物种起源", IT("物种起源")),
           ("银之钥", IT("银之钥")), ("古希腊长袍", IT("古希腊长袍")), ("可疑的信", IT("可疑的信")),
           ("爱的艺术", IT("爱的艺术")), ("越狱工具清单", IT("越狱工具清单")),
           ("精心磨制的小刀", IT("精心磨制的小刀")), ("被诅咒的古董", IT("被诅咒的古董"))]

def shelf(key):
    band = Image.new("RGB", (SHELF_W, SHELF_H))
    for y in range(0, SHELF_H, ph_):
        for x in range(0, SHELF_W, pw_):
            band.paste(_paper, (x, y))
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

sh2 = Image.new("RGB", (SHELF_W + CP * 2, 40 + len(KEYS) * (SHELF_H + 56)), (150, 153, 158))
d2 = ImageDraw.Draw(sh2)
for i, k in enumerate(KEYS):
    y = 40 + i * (SHELF_H + 56)
    d2.text((CP, y - 26), LAB[k], fill=(255, 255, 255), font=font(19, True))
    sh2.paste(shelf(k), (CP, y))
sh2.save(os.path.join(BASE, "卡面B_小设计七版_货架.png"))
print("SAVED 卡面B_小设计七版_货架.png", sh2.size)

# ============ 出图 3：四角 / 上缘 4x 局部 ============
CROP = 52
sh3 = Image.new("RGB", (CP * 2 + len(KEYS) * (CROP * 4 + CG) - CG, 78 * 4 + 150), (128, 131, 136))
d3 = ImageDraw.Draw(sh3)
d3.text((CP, 16), "左上角 4x 放大（52×78 区域）—— 看装饰在小尺寸下是否成立、会不会打架",
        fill=(255, 255, 255), font=font(23, True))
for i, k in enumerate(KEYS):
    x = CP + i * (CROP * 4 + CG)
    sh3.paste(render(k, HERO, "朱利安", 4).crop((0, 0, CROP * 4, 78 * 4)), (x, 64))
    d3.text((x, 64 + 78 * 4 + 12), LAB[k].split("（")[0].split(" ")[0] + " " + LAB[k].split(" ")[1],
            fill=(255, 255, 255), font=font(16, True))
sh3.save(os.path.join(BASE, "卡面B_小设计七版_边缘4x.png"))
print("SAVED 卡面B_小设计七版_边缘4x.png", sh3.size)
