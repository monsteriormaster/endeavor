# -*- coding: utf-8 -*-
"""彩铅按钮贴图：抠底 -> 归一 -> 中心纯色化 -> 九宫格装配预览"""
import os, numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

BASE = os.path.dirname(os.path.abspath(__file__))
LOG  = os.path.join(BASE, "_prep_log.txt")
lines = []
def P(*x):
    lines.append(" ".join(str(i) for i in x))

SRC = None
for f in sorted(os.listdir(BASE)):
    if f.lower().endswith(".png") and f.startswith("_H1"):
        SRC = os.path.join(BASE, f)
if SRC is None:
    P("!! 找不到源图"); open(LOG, "w", encoding="utf-8").write("\n".join(lines)); raise SystemExit

im = Image.open(SRC).convert("RGB")
W, H = im.size
P("原图尺寸", W, H)

a = np.asarray(im).astype(np.int16)
mx, mn = a.max(2), a.min(2)
nonwhite = (mx < 246) | ((mx - mn) > 14)
wz = np.zeros_like(nonwhite); wz[int(H * 0.89):, int(W * 0.76):] = True
P("水印区(右下角)非白像素数 =", int((nonwhite & wz).sum()))

nw2 = nonwhite.copy(); nw2[wz] = False
lab, nlab = ndimage.label(nw2, np.ones((3, 3), int))
sizes = ndimage.sum(nw2, lab, range(1, nlab + 1))
big = int(np.argmax(sizes)) + 1
ys, xs = np.nonzero(lab == big)
bx0, by0, bx1, by1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
P("纸片 bbox =", bx0, by0, bx1, by1, " 尺寸 =", bx1 - bx0, "x", by1 - by0,
  " 宽高比 =", round((bx1 - bx0) / (by1 - by0), 3))

TEX_W, TEX_H = 512, 192
MARGIN = 12
small = im.crop((bx0, by0, bx1, by1)).resize((TEX_W, TEX_H), Image.LANCZOS)

sa = np.asarray(small.convert("RGB")).astype(np.int16)
smx, smn = sa.max(2), sa.min(2)
white = (smx >= 242) & ((smx - smn) <= 18)
alpha = np.where(white, 0, 255).astype(np.uint8)
P("抠白后透明占比 =", round(float((alpha == 0).mean()) * 100, 2), "%")

op = alpha > 0
idx = ndimage.distance_transform_edt(~op, return_distances=False, return_indices=True)
rgb = sa.astype(np.uint8)[tuple(idx)]

core = rgb[MARGIN:TEX_H - MARGIN, MARGIN:TEX_W - MARGIN].reshape(-1, 3).astype(np.float32)
med = np.median(core, axis=0)
P("中心区中位色 =", [int(v) for v in med])

rgb2 = rgb.copy()
inner = np.zeros((TEX_H, TEX_W), bool)
inner[MARGIN:TEX_H - MARGIN, MARGIN:TEX_W - MARGIN] = True
rgb2[inner] = med.astype(np.uint8)
P("已把「距四边 >= %dpx」的中心区填成中位色（恰好等于九宫格中心区）" % MARGIN)

tex = Image.fromarray(np.dstack([rgb2, alpha]).astype(np.uint8), "RGBA")
tex.save(os.path.join(BASE, "btn_pencil_512.png"))
P("已存 btn_pencil_512.png")

ta = np.asarray(tex)
for tag, sub in (("中心区", ta[MARGIN + 4:TEX_H - MARGIN - 4, MARGIN + 4:TEX_W - MARGIN - 4, :3]),
                 ("上边块", ta[0:MARGIN, MARGIN:TEX_W - MARGIN, :3]),
                 ("左上角块", ta[0:MARGIN, 0:MARGIN, :3])):
    f = sub.astype(np.float32)
    L = 0.299 * f[:, :, 0] + 0.587 * f[:, :, 1] + 0.114 * f[:, :, 2]
    P("%s 亮度均值 = %.2f  标准差 = %.2f" % (tag, L.mean(), L.std()))

row = TEX_H // 2
lum = ta[row, :, :3].mean(1); al = ta[row, :, 3]
seg = best = 0
for i in range(TEX_W):
    if al[i] > 0 and lum[i] < 165: seg += 1; best = max(best, seg)
    else: seg = 0
P("中线深色段最长 =", best, "px")


def nine_slice(src, w, h, m):
    tw, th = src.size
    if w < 2 * m or h < 2 * m:
        return None, "溢出: 角块 %d×2=%d > 短边 %d" % (m, 2 * m, min(w, h))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, chh = w - 2 * m, h - 2 * m
    spec = [
        (0, 0, m, m, 0, 0), (m, 0, tw - m, m, m, 0), (tw - m, 0, tw, m, w - m, 0),
        (0, m, m, th - m, 0, m), (m, m, tw - m, th - m, m, m), (tw - m, m, tw, th - m, w - m, m),
        (0, th - m, m, th, 0, h - m), (m, th - m, tw - m, th, m, h - m), (tw - m, th - m, tw, th, w - m, h - m),
    ]
    for sx0, sy0, sx1, sy1, dx, dy in spec:
        dw = m if dx in (0, w - m) else cw
        dh = m if dy in (0, h - m) else chh
        c = src.crop((sx0, sy0, sx1, sy1)).resize((max(1, dw), max(1, dh)), Image.LANCZOS)
        out.paste(c, (dx, dy))
    return out, "OK"


FONT = r"C:\Windows\Fonts\msyh.ttc"
f13 = ImageFont.truetype(FONT, 13)
f15 = ImageFont.truetype(FONT, 15)
f22 = ImageFont.truetype(FONT, 22)
BG = (216, 210, 196, 255)

PW, PH = 1180, 1360
prev = Image.new("RGBA", (PW, PH), BG)
d = ImageDraw.Draw(prev)
d.text((30, 16), "彩铅按钮 · 九宫格装配预览    margin = %dpx   中心区已纯色化" % MARGIN,
       font=f22, fill=(40, 34, 26, 255))

d.text((30, 56), "① 贴图 512x192（1.6x 放大；黄线 = 九宫格切分线）", font=f15, fill=(70, 60, 48, 255))
big = tex.resize((int(TEX_W * 1.6), int(TEX_H * 1.6)), Image.LANCZOS)
prev.paste(big, (30, 80), big)
for gx in (MARGIN, TEX_W - MARGIN):
    d.line([30 + gx * 1.6, 80, 30 + gx * 1.6, 80 + TEX_H * 1.6], fill=(200, 150, 40, 220), width=1)
for gy in (MARGIN, TEX_H - MARGIN):
    d.line([30, 80 + gy * 1.6, 30 + TEX_W * 1.6, 80 + gy * 1.6], fill=(200, 150, 40, 220), width=1)

d.text((30, 412), "② 真实控件尺寸 1:1 装配（红框 = 控件边界）", font=f15, fill=(70, 60, 48, 255))
y = 440
for name, w, h in [("loading 继续游戏", 393, 99), ("main_ui 下一天", 176, 84), ("settings 保存进度", 250, 44)]:
    img, st = nine_slice(tex, w, h, MARGIN)
    x = 30
    if img is not None: prev.paste(img, (x, y), img)
    d.rectangle([x - 1, y - 1, x + w, y + h], outline=(180, 60, 60, 255))
    d.text((x + w + 14, y + h // 2 - 16), name, font=f13, fill=(40, 34, 26, 255))
    d.text((x + w + 14, y + h // 2 + 2), "%dx%d  %s" % (w, h, st), font=f13,
           fill=(50, 110, 60, 255) if st == "OK" else (150, 40, 40, 255))
    y += h + 24

d.text((30, 736), "③ 小按钮 84x28（游戏里真实像素；右 = 6x NEAREST 放大）", font=f15, fill=(70, 60, 48, 255))
yy = 790
for mm in (8, 10, 12):
    img, st = nine_slice(tex, 84, 28, mm)
    d.text((30, yy + 8), "m=%d" % mm, font=f13, fill=(40, 34, 26, 255))
    if img is not None: prev.paste(img, (76, yy), img)
    yy += 36
img, _ = nine_slice(tex, 84, 28, MARGIN)
up = img.resize((84 * 6, 28 * 6), Image.NEAREST)
prev.paste(up, (210, 736), up)
d.text((210, 908), "m=%d 的 6x 放大" % MARGIN, font=f13, fill=(70, 60, 48, 255))

d.text((740, 742), "④ 短边下限 = margin×2 = %dpx" % (MARGIN * 2), font=f15, fill=(70, 60, 48, 255))
img, st = nine_slice(tex, 16, 45, MARGIN)
d.text((740, 772), "16x45（selection 加减号）", font=f13, fill=(40, 34, 26, 255))
d.text((740, 792), st, font=f13, fill=(150, 40, 40, 255))
img, st = nine_slice(tex, 24, 24, MARGIN)
d.text((740, 822), "24x24  m=%d → %s" % (MARGIN, st), font=f13,
       fill=(50, 110, 60, 255) if st == "OK" else (150, 40, 40, 255))
img, st = nine_slice(tex, 84, 28, 6)
d.text((740, 852), "84x28 m=6 → %s   中心区 72x16" % st, font=f13, fill=(50, 110, 60, 255))

prev.convert("RGB").save(os.path.join(BASE, "_preview_nineslice.png"))
P("已存 _preview_nineslice.png")

nav_path = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\nav_btn.png"
nav = Image.open(nav_path).convert("RGBA") if os.path.exists(nav_path) else None
P("nav_btn.png 读入 =", nav is not None, nav.size if nav else "")

CASES2 = [
    ("继续游戏", 393, 99, 40, "loading"),
    ("下一天", 176, 84, 22, "main_ui"),
    ("保存进度", 250, 44, 20, "settings"),
    ("人物", 84, 28, 14, "card_area"),
]
Y0 = 1000
d.text((30, 948), "⑤ 现状 vs 彩铅（1:1 真实尺寸 + 真文字，底色 = 主城彩铅底）", font=f15, fill=(70, 60, 48, 255))
d.text((30, 974), "左 = 现状", font=f13, fill=(70, 60, 48, 255))
d.text((470, 974), "右 = 彩铅贴图", font=f13, fill=(70, 60, 48, 255))

yy = Y0
for text, w, h, fs, where in CASES2:
    flat = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flat)
    if where == "main_ui" and nav is not None:
        flat.paste(nav.resize((w, h), Image.LANCZOS), (0, 0))
    else:
        bgc = (232, 220, 199, 255) if where == "card_area" else (219, 219, 219, 255)
        bdc = (143, 108, 46, 180) if where == "card_area" else (150, 150, 150, 255)
        fd.rounded_rectangle([0, 0, w - 1, h - 1], radius=3, fill=bgc, outline=bdc, width=1)
    prev.paste(flat, (30, yy), flat)
    fnt = ImageFont.truetype(FONT, fs)
    tcol = (45, 34, 21, 255) if where in ("card_area", "settings", "main_ui") else (20, 18, 16, 255)
    d.text((30 + w / 2, yy + h / 2), text, font=fnt, fill=tcol, anchor="mm")

    newb, st = nine_slice(tex, w, h, MARGIN)
    if newb is None:
        newb, st = nine_slice(tex, w, h, 6)
    prev.paste(newb, (470, yy), newb)
    d.text((470 + w + 12, yy + h // 2), "%dx%d  m=%d %s" % (w, h, MARGIN, st), font=f13,
           fill=(50, 110, 60, 255) if st == "OK" else (150, 40, 40, 255))
    y2 = yy + h / 2
    d.text((470 + w / 2, y2), text, font=fnt, fill=(38, 29, 18, 255), anchor="mm")
    yy += h + 24

prev.convert("RGB").save(os.path.join(BASE, "_preview_nineslice.png"))
P("已存 _preview_nineslice.png (含 ⑤ 现状对比)")
open(LOG, "w", encoding="utf-8").write("\n".join(lines))
