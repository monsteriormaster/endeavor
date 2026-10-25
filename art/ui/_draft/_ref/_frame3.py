# -*- coding: utf-8 -*-
"""卡框 v2：名字在上（预留两行）→ 立绘在下 → 全卡只有一条细金属边框。
不猜几何：全部按 card_chip.gd 改后的真实数值算。"""
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
    return tuple(max(0, min(255, int(v*k))) for v in c)

# ===== 真实几何（1x px；与改后的 card_chip.gd 一一对应）=====
M_SIDE, M_TOP, M_BOT = 6, 6, 4
NAME_LINES, NAME_FONT = 2, 14
LINE_H = 17.2                     # Godot 默认字体 font14 单行高 ≈ 1.23×14
NAME_H = NAME_LINES * LINE_H      # 34.4 → 取整 35？保持浮点即可
SEP = 4
CARD_W, CARD_H = 90, 159
CONTENT = (M_SIDE, M_TOP, CARD_W - M_SIDE, CARD_H - M_BOT)      # x6→84 / y6→155
NAME_BOX = (M_SIDE, M_TOP, CARD_W - M_SIDE, M_TOP + NAME_H)     # y6→40.4
ART_BOX  = (M_SIDE, M_TOP + NAME_H + SEP, CARD_W - M_SIDE, CARD_H - M_BOT)  # y44.4→155

COL = {
    "A": dict(name="A 暗匣", body=(74,55,43),  brass=(196,158,84), ink=(26,18,13),
              hi=(126,94,73),  lo=(41,30,23),   text=(250,238,214)),
    "B": dict(name="B 同族", body=(231,222,202), brass=(170,140,70), ink=(104,74,44),
              hi=(250,245,232), lo=(185,177,162), text=(58,42,26)),
}

SC = 3
S = lambda v: int(round(v*SC))
CW, CH = CARD_W*SC, CARD_H*SC

def build(col):
    im = Image.new("RGB", (CW, CH), col["body"])
    d = ImageDraw.Draw(im)
    # 厚度：顶/左亮边，底/右暗边
    d.rectangle([0, 0, CW-1, S(1.4)-1], fill=col["hi"])
    d.rectangle([0, 0, S(1.4)-1, CH-1], fill=col["hi"])
    d.rectangle([0, CH-S(1.8), CW-1, CH-1], fill=col["lo"])
    d.rectangle([CW-S(1.8), 0, CW-1, CH-1], fill=col["lo"])
    # 唯一一条边框：暗金 1.3px → 亮金发丝 0.6px → 近黑 0.5px（总宽 ~2.4px）
    for ins, c, w in ((0.8, col["brass"], 1.3), (2.1, col["brass"], 0.6), (3.0, col["ink"], 0.5)):
        cc = mix(c, 0.62) if (ins == 0.8) else c
        d.rectangle([S(ins), S(ins), CW-1-S(ins), CH-1-S(ins)], outline=cc, width=max(1, S(w)))
    return im

def paste_art(canvas, path):
    x0, y0, x1, y1 = ART_BOX
    bw, bh = S(x1-x0), S(y1-y0)
    art = Image.open(path).convert("RGBA")
    s = min(bw/art.size[0], bh/art.size[1])
    art = art.resize((max(1, int(round(art.size[0]*s))), max(1, int(round(art.size[1]*s)))), Image.LANCZOS)
    canvas.paste(art, (S(x0) + (bw-art.size[0])//2, S(y0) + (bh-art.size[1])//2), art)
    return bw, bh, art.size

def wrap(s, per):
    return [s[i:i+per] for i in range(0, len(s), per)] or [""]

def render(key, art_path, name, sc=SC):
    global SC, CW, CH, S
    old = (SC, CW, CH)
    SC = sc; CW, CH = CARD_W*SC, CARD_H*SC
    S = lambda v: int(round(v*SC))
    col = COL[key]
    c = build(col)
    paste_art(c, art_path)
    d = ImageDraw.Draw(c)
    f = font(S(NAME_FONT), True)
    per = max(1, int((CONTENT[2]-CONTENT[0]) // (NAME_FONT + 1.5)))
    lines = wrap(name, per)
    lh = S(NAME_FONT * 1.23)
    # 名字在预留区里垂直居中（1 行居中 / 2 行铺满）
    top = M_TOP + (NAME_H - len(lines)*NAME_FONT*1.23)/2.0
    for i, ln in enumerate(lines):
        cy = top + NAME_FONT*1.23*(i+0.5)
        d.text((S(45), S(cy)), ln, fill=col["text"], font=f, anchor="mm")
    SC, CW, CH = old
    S = lambda v: int(round(v*SC))
    return c

HERO = os.path.join(R, "art", "hero.png")
NECK = os.path.join(R, "art", "items", "蓝宝石项链.png")
BOOK = os.path.join(R, "art", "items", "几何原本.png")
STAT = os.path.join(R, "art", "items", "章鱼尾人身塑像.png")

print("内容盒 x%d→%d / y%d→%d" % CONTENT)
print("名字盒 y%.1f→%.1f（预留 %d 行 × font%d = %.1fpx）" % (NAME_BOX[1], NAME_BOX[3], NAME_LINES, NAME_FONT, NAME_H))
print("立绘盒 x%d→%d / y%.1f→%.1f  = %d × %.1f" % (ART_BOX[0], ART_BOX[2], ART_BOX[1], ART_BOX[3], ART_BOX[2]-ART_BOX[0], ART_BOX[3]-ART_BOX[1]))

# ===== 出图 1：实装预览（A/B 各 3 张）=====
CG, CP, CL = 30, 34, 70
w1 = 3*CW + 2*CG
sh = Image.new("RGB", (CP*2 + w1*2 + 60, CP*2 + CL + CH), (242,240,236))
d = ImageDraw.Draw(sh); f2 = font(23, True); f3 = font(16)
ys = CP + CL
CASES = [(HERO, "朱利安"), (NECK, "蓝宝石项链"), (STAT, "章鱼尾人身塑像")]
for i, key in enumerate(("A", "B")):
    x0 = CP + i*(w1 + 60)
    d.text((x0, CP), "%s —— 名字在上（预留两行）/ 立绘在下 / 只有一条细金属边框（3x）" % COL[key]["name"], fill=(28,26,24), font=f2)
    d.text((x0, CP+32), "内容盒 x6→84 y6→155 · 名字区 y6→40(=2行) · 立绘盒 x6→84 y44→155 (78×111) · 边框仅 2.4px", fill=(95,90,84), font=f3)
    for j, (p, nm) in enumerate(CASES):
        sh.paste(render(key, p, nm), (x0 + j*(CW+CG), ys))
sh.save(os.path.join(BASE, "卡面v2_实装预览_AB.png"))
print("SAVED 卡面v2_实装预览_AB.png", sh.size)

# ===== 出图 2：真实尺寸检验 =====
scales = [1, 2, 3, 4]
rows = {k: [render(k, HERO, "朱利安", s) for s in scales] for k in ("A", "B")}
TITLE_H = 100
Hmax = max(i.size[1] for v in rows.values() for i in v)
W2 = sum(i.size[0] for i in rows["A"]) + 30*(len(scales)-1)
sh2 = Image.new("RGB", (CP*2 + W2, CP*2 + TITLE_H + Hmax*2 + 46), (214,202,178))
d2 = ImageDraw.Draw(sh2); f4 = font(22, True); f5 = font(15)
d2.text((CP, CP), "v2 真实尺寸检验 —— 1x 就是游戏里卡位的实际大小（90×159）", fill=(46,38,30), font=f4)
for k, lab in (("A", "A 暗匣"), ("B", "B 同族")):
    base_y = CP + TITLE_H + (0 if k == "A" else Hmax + 46)
    d2.text((CP, base_y - 22), "%s：1x / 2x / 3x / 4x" % lab, fill=(84,72,58), font=f5)
    x = CP
    for im in rows[k]:
        sh2.paste(im, (x, base_y + (Hmax - im.size[1])))
        x += im.size[0] + 30
sh2.save(os.path.join(BASE, "卡面v2_真实尺寸检验.png"))
print("SAVED 卡面v2_真实尺寸检验.png", sh2.size)
