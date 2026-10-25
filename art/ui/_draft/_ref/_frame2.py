# -*- coding: utf-8 -*-
"""① 把两版 AI 卡框归一裁剪成 90:159 对比图
   ② 按 card_chip.gd 的真实几何矢量重建卡框，装真实立绘/道具 + 名字 → 实装预览
"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")
DRAW = os.path.join(BASE, "draw")
TARGET = 90 / 159.0

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

def bg_of(im):
    px = im.load(); w, _ = im.size
    r = g = b = n = 0
    for y in range(0, 8):
        for x in range(0, w, 4):
            c = px[x, y]; r += c[0]; g += c[1]; b += c[2]; n += 1
    return (r//n, g//n, b//n)

def bbox(im, thr=20):
    w, h = im.size; bg = bg_of(im); px = im.load()
    x0, y0, x1, y1 = w, h, -1, -1
    wx, wy = int(w*0.82), int(h*0.85)
    for y in range(0, h):
        for x in range(0, w):
            if x > wx and y > wy: continue
            c = px[x, y]
            if abs(c[0]-bg[0]) + abs(c[1]-bg[1]) + abs(c[2]-bg[2]) > thr*3:
                if x < x0: x0 = x
                if y < y0: y0 = y
                if x > x1: x1 = x
                if y > y1: y1 = y
    return (x0, y0, x1, y1), bg

def norm_card(src, wm_h=82):
    im = Image.open(src).convert("RGB")
    W, H = im.size
    clean = im.crop((0, 0, W, H - wm_h))
    (x0, y0, x1, y1), _ = bbox(clean)
    cx, cy = (x0+x1)/2.0, (y0+y1)/2.0
    cw, ch = x1-x0+1, y1-y0+1
    if cw/ch < TARGET: nw, nh = int(round(ch*TARGET)), ch
    else:              nw, nh = cw, int(round(cw/TARGET))
    nx0 = max(0, min(int(round(cx-nw/2.0)), max(0, clean.size[0]-nw)))
    ny0 = max(0, min(int(round(cy-nh/2.0)), max(0, clean.size[1]-nh)))
    crop = clean.crop((nx0, ny0, min(clean.size[0], nx0+nw), min(clean.size[1], ny0+nh)))
    # 裁不到边界 → 用等比补齐后再做一次轻微整形到精确 0.566（直边框体形变无感）
    return crop.resize((400, int(round(400/TARGET))), Image.LANCZOS), (cw, ch)

A_raw, A_native = norm_card(os.path.join(DRAW, "A_single_vertical_collectible__2026-09-27T13-18-34.png"))
B_raw, B_native = norm_card(os.path.join(DRAW, "A_single_vertical_collectible__2026-09-27T13-18-59.png"))
print("A native card %dx%d ar=%.3f" % (A_native[0], A_native[1], A_native[0]/A_native[1]))
print("B native card %dx%d ar=%.3f" % (B_native[0], B_native[1], B_native[0]/B_native[1]))

def sample(im, u, v):
    px = im.load()
    return px[int(im.size[0]*u), int(im.size[1]*v)]

# ---- 材质配色（从 AI 图目视取档，比自动采样可靠）----
cA = dict(
    body=(74, 55, 43),        # 深胡桃
    window=(56, 41, 32),      # 图像区略暗一档（凹）
    plate=(150, 104, 60),     # 暖棕铭牌（亮一档，名字压得住）
    brass=(196, 158, 84),
    name=(250, 238, 214),
)
cB = dict(
    body=(231, 222, 202),     # 骨白硬卡
    window=(238, 231, 214),
    plate=(191, 161, 113),    # 暖棕铭牌
    brass=(170, 140, 70),
    name=(58, 42, 26),
)
print("A colors", cA)
print("B colors", cB)

def mix(c, k):
    return tuple(max(0, min(255, int(v*k))) for v in c)


def alpha_blend(c, bg, a):
    return tuple(int(c[i]*a + bg[i]*(1-a)) for i in range(3))

SC = 3                      # 渲染倍数（1x 太糊，3x 便于看图）
CW, CH = 90*SC, 159*SC

def S(v): return int(round(v*SC))

def build_frame(col, dark, plate_top=114):
    """按 1x 真实几何重建卡框"""
    im = Image.new("RGB", (CW, CH), col["body"])
    d = ImageDraw.Draw(im)
    bright = col["brass"]
    dk     = mix(col["brass"], 0.52)
    ink    = (26, 18, 13) if dark else (104, 74, 44)
    hi     = mix(col["body"], 1.7) if dark else (250, 245, 232)
    lo     = mix(col["body"], 0.55) if dark else mix(col["body"], 0.80)

    # 厚度：顶/左亮边，底/右暗边
    d.rectangle([0, 0, CW-1, S(1.5)-1], fill=hi)
    d.rectangle([0, 0, S(1.5)-1, CH-1], fill=hi)
    d.rectangle([0, CH-S(2.0), CW-1, CH-1], fill=lo)
    d.rectangle([CW-S(2.0), 0, CW-1, CH-1], fill=lo)

    # 金工三线（外 2px 暗铜 → 亮金发丝 → 近黑内线）
    ins = 3.0
    d.rectangle([S(ins), S(ins), CW-1-S(ins), CH-1-S(ins)], outline=dk, width=max(1, S(1.3)))
    d.rectangle([S(ins+1.3), S(ins+1.3), CW-1-S(ins+1.3), CH-1-S(ins+1.3)], outline=bright, width=max(1, S(0.7)))
    d.rectangle([S(ins+2.6), S(ins+2.6), CW-1-S(ins+2.6), CH-1-S(ins+2.6)], outline=ink, width=max(1, S(0.6)))

    # 四角小菱形金饰
    def lozenge(cx, cy, r):
        d.polygon([(cx, cy-r), (cx+r, cy), (cx, cy+r), (cx-r, cy)], fill=bright, outline=dk)
    for (cx, cy) in [(S(4.8), S(4.8)), (CW-S(4.8), S(4.8)), (S(4.8), CH-S(4.8)), (CW-S(4.8), CH-S(4.8))]:
        lozenge(cx, cy, S(2.2))

    # 图像区（空）—— 几何取自 card_chip.gd 的 icon 盒，左右各留 2px 呼吸
    WX0, WY1 = 8, plate_top - 3
    WX1, WY0 = 82, 14
    d.rectangle([S(WX0), S(WY0), S(WX1), S(WY1)], outline=None, fill=col["window"])

    # 分隔线 + 中央菱形
    d.line([(S(WX0), S(WY1)), (S(WX1), S(WY1))], fill=bright, width=max(1, S(0.7)))
    lozenge(S((WX0+WX1)/2), S(WY1), S(2.6))

    # 铭牌（名字恰好落在它里面：Label 底 = 159-24 = 135，字高 ~17 → y 118~135）
    PX0, PY0, PX1, PY1 = 8, plate_top, 82, 143
    d.rounded_rectangle([S(PX0), S(PY0), S(PX1), S(PY1)], radius=S(2.2), fill=col["plate"],
                        outline=mix(col["plate"], 0.72), width=max(1, S(0.5)))
    d.rectangle([S(PX0+1), S(PY0+1), S(PX1-1), S(PY0+1.0)], fill=mix(col["plate"], 1.55 if dark else 1.06))
    return im

def icon_box_rect():
    """card_chip.gd 的实际内容几何（1x）"""
    M_T, M_B, M_S = 14, 24, 10
    NAME_H = 17
    ix0, ix1 = M_S, 90-M_S
    iy0 = M_T
    iy1 = 159 - M_B - 4 - NAME_H          # VBox separation=4
    return (ix0, iy0, ix1, iy1)

def paste_keep_aspect(canvas, path):
    """按 card_chip.gd 的 STRETCH_KEEP_ASPECT_CENTERED 在 icon 盒内等比居中贴图。
    注意：所有尺寸都要在画布像素空间算（S() 已经乘过 SC）。"""
    ix0, iy0, ix1, iy1 = icon_box_rect()
    bw, bh = S(ix1-ix0), S(iy1-iy0)
    art = Image.open(path).convert("RGBA")
    s = min(bw/art.size[0], bh/art.size[1])
    aw, ah = max(1, int(round(art.size[0]*s))), max(1, int(round(art.size[1]*s)))
    art = art.resize((aw, ah), Image.LANCZOS)
    ax = S(ix0) + (bw - aw)//2
    ay = S(iy0) + (bh - ah)//2
    canvas.paste(art, (ax, ay), art)
    return (ix0, iy0, ix1, iy1), art.size

def render(col, dark, art_path, name, out_name=None):
    card = build_frame(col, dark)
    box, asz = paste_keep_aspect(card, art_path)
    d = ImageDraw.Draw(card)
    f = font(S(11.5), True)
    tx0, ty0, tx1, ty1 = 8, 114, 82, 143
    d.text((S((tx0+tx1)/2), S((ty0+ty1)/2 - 1)), name, fill=col["name"], font=f, anchor="mm")
    return card

CARDS = [
    (os.path.join(R, "art", "hero.png"),              "朱利安"),
    (os.path.join(R, "art", "items", "蓝宝石项链.png"), "蓝宝石项链"),
    (os.path.join(R, "art", "items", "几何原本.png"),   "几何原本"),
]

rendered = {"A": [], "B": []}
for key, col, dark in (("A", cA, True), ("B", cB, False)):
    for path, nm in CARDS:
        rendered[key].append(render(col, dark, path, nm))

# ===== 出图 1：两版 AI 框 归一对比 =====
GAP, PAD, LAB = 46, 34, 84
sh = Image.new("RGB", (PAD*2 + 400*2 + GAP, PAD*2 + LAB + A_raw.size[1]), (242,240,236))
d = ImageDraw.Draw(sh); ft, fs = font(24, True), font(17)
d.text((PAD, PAD), "A  暗匣 · 深胡桃 + 古董金工线", fill=(28,26,24), font=ft)
d.text((PAD, PAD+32), "推荐：与 trigger.png 同族；卡身深→立绘/道具的透明区自然融掉", fill=(95,90,84), font=fs)
d.text((PAD+400+GAP, PAD), "B  同族 · 骨白硬卡 + 墨线铜铭牌", fill=(28,26,24), font=ft)
d.text((PAD+400+GAP, PAD+32), "保守：与浅米羊皮纸 UI 同族；风险是又读成「纸」", fill=(95,90,84), font=fs)
sh.paste(A_raw, (PAD, PAD+LAB)); sh.paste(B_raw, (PAD+400+GAP, PAD+LAB))
sh.save(os.path.join(BASE, "卡框_AB两版.png"))
print("SAVED 卡框_AB两版.png", sh.size)

# ===== 出图 2：按真实几何重建 + 装真内容 =====
CG, CP, CL = 30, 34, 66
w1 = 3*CW + 2*CG
sh2 = Image.new("RGB", (CP*2 + w1*2 + 60, CP*2 + CL + CH + 30), (242,240,236))
d = ImageDraw.Draw(sh2); f2 = font(23, True); f3 = font(16)
ys = CP + CL
for i, key in enumerate(("A", "B")):
    x0 = CP + i*(w1 + 60)
    title = "A 暗匣 · 按 card_chip.gd 真实几何重建（3x）" if key == "A" else "B 同族 · 同几何（3x）"
    d.text((x0, CP), title, fill=(28,26,24), font=f2)
    d.text((x0, CP+30), "图像区 x8→82 / y14→111 · 铭牌 y114→143（名字恰好落在铭牌内，零代码改动）", fill=(95,90,84), font=f3)
    for j, card in enumerate(rendered[key]):
        sh2.paste(card, (x0 + j*(CW+CG), ys))
sh2.save(os.path.join(BASE, "卡面实装预览_AB.png"))
print("SAVED 卡面实装预览_AB.png", sh2.size)

# ===== 出图 3：真实尺寸检验（1x = 90×159 就是游戏里的实际大小）=====
def render_scale(col, dark, art, name, sc):
    global SC, CW, CH, S
    old = (SC, CW, CH)
    SC = sc
    CW, CH = 90*SC, 159*SC
    S = lambda v: int(round(v*SC))
    c = build_frame(col, dark)
    paste_keep_aspect(c, art)
    d = ImageDraw.Draw(c)
    f = font(max(6, S(11.5)), True)
    d.text((S(45), S(128.5)), name, fill=col["name"], font=f, anchor="mm")
    SC, CW, CH = old
    S = lambda v: int(round(v*SC))
    return c

scales = [1, 2, 3, 4]
imgs = [render_scale(cA, True, CARDS[0][0], CARDS[0][1], s) for s in scales]
imgs2 = [render_scale(cB, False, CARDS[0][0], CARDS[0][1], s) for s in scales]
TITLE_H = 96
Hmax = max(i.size[1] for i in imgs)
W2 = sum(i.size[0] for i in imgs) + 30*(len(imgs)-1)
sh3 = Image.new("RGB", (CP*2 + W2, CP*2 + TITLE_H + Hmax*2 + 40), (214, 202, 178))  # 模拟浅米货架底
d3 = ImageDraw.Draw(sh3); f4 = font(22, True); f5 = font(15)
d3.text((CP, CP), "真实尺寸检验 —— 1x 就是游戏里卡位的实际大小（90×159）", fill=(46,38,30), font=f4)
d3.text((CP, CP+30), "A 暗匣：1x / 2x / 3x / 4x", fill=(84,72,58), font=f5)
x = CP
for im in imgs:
    sh3.paste(im, (x, CP+TITLE_H-  (0 if False else 0) + (Hmax - im.size[1])))
    x += im.size[0] + 30
d3.text((CP, CP+TITLE_H+Hmax+34), "B 同族：1x / 2x / 3x / 4x", fill=(84,72,58), font=f5)
x = CP
for im in imgs2:
    sh3.paste(im, (x, CP+TITLE_H+Hmax+34+40 - 40 + (Hmax - im.size[1])))
    x += im.size[0] + 30
sh3.save(os.path.join(BASE, "卡面_真实尺寸检验.png"))
print("SAVED 卡面_真实尺寸检验.png", sh3.size)

# ===== 出图 4：长名字边界情况（名字最长的卡）=====
LONG = "章鱼尾人身塑像"      # 7 字；70px 宽 × font14 → 只能放 5 字/行，必然折 2 行

def wrap(s, per):
    return [s[i:i+per] for i in range(0, len(s), per)]

def render_long(col, dark, art, sc=3, font_px=14, plate_top=114, label_bottom=135):
    """复刻 card_chip.gd 的 Label 行为：贴底、宽度 70px、auto wrap、水平居中"""
    global SC, CW, CH, S
    old = (SC, CW, CH)
    SC = sc; CW, CH = 90*SC, 159*SC
    S = lambda v: int(round(v*SC))
    c = build_frame(col, dark, plate_top=plate_top)
    paste_keep_aspect(c, art)
    d = ImageDraw.Draw(c)
    f = font(S(font_px), True)
    lines = wrap(LONG, max(1, int(70 // (font_px * 1.05))))
    lh = font_px * 1.38
    # Label 贴底：底边 = label_bottom
    top = label_bottom - lh * len(lines)
    for i, ln in enumerate(lines):
        cy = top + lh * (i + 0.5)
        d.text((S(45), S(cy)), ln, fill=col["name"], font=f, anchor="mm")
    SC, CW, CH = old
    S = lambda v: int(round(v*SC))
    return c

cur = render_long(cA, True, os.path.join(R, "art", "items", "章鱼尾人身塑像.png"), plate_top=114, font_px=14)
fix = render_long(cA, True, os.path.join(R, "art", "items", "章鱼尾人身塑像.png"), plate_top=100, font_px=12)
sh4 = Image.new("RGB", (CP*2 + CW*2 + 70, CP*2 + 122 + CH), (242,240,236))
d4 = ImageDraw.Draw(sh4); f6 = font(21, True); f7 = font(14)
d4.text((CP, CP), "边界情况：名字最长的卡「章鱼尾人身塑像」（7 字）—— 铭牌装不装得下", fill=(28,26,24), font=f6)
d4.text((CP, CP+30), "① 现状：font14 / 70px 宽 / 贴底至 y135 → 折 2 行，字块 y97→135，上沿越出铭牌(114)", fill=(150,46,38), font=f7)
d4.text((CP, CP+50), "② 修法：铭牌上沿 114→100 + 字号 14→12 → 两行 y105→135，完全落在铭牌内；代价=图像区 14→97（立绘小 14%）", fill=(46,110,60), font=f7)
sh4.paste(cur, (CP, CP+122)); sh4.paste(fix, (CP+CW+70, CP+122))
sh4.save(os.path.join(BASE, "卡面_长名字边界.png"))
print("SAVED 卡面_长名字边界.png", sh4.size)
