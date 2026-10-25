# -*- coding: utf-8 -*-
"""处理新出的卡面 + 与原图并排对比。
- 裁掉底部 82px AI 水印
- 探测卡面 bbox（排除右下角水印区）
- 按 90:159 = 0.566 归一裁切
- 与真实原图裁切并排，标注
"""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SRC = os.path.join(BASE, "draw", "A_single_vertical_collectible__2026-09-26T17-34-30.png")
OUT = os.path.join(BASE, "卡面_月圆之夜_v1.png")
CMP = os.path.join(BASE, "对比_月圆之夜_原图vs新画.png")
WM_H = 82
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

im = Image.open(SRC).convert("RGB")
W, H = im.size
clean = im.crop((0, 0, W, H - WM_H))
bb, bg = bbox(clean)
x0, y0, x1, y1 = bb
print("src %dx%d  after-wm-crop %dx%d  bg=%s  bbox=%s  card %dx%d ar=%.3f"
      % (W, H, clean.size[0], clean.size[1], bg, bb, x1-x0+1, y1-y0+1, (x1-x0+1)/(y1-y0+1)))

# 归一裁切到 90:159
cw, ch = x1-x0+1, y1-y0+1
cx, cy = (x0+x1)/2.0, (y0+y1)/2.0
if cw/ch < TARGET:      # 偏窄 → 加宽
    nw = int(round(ch*TARGET)); nh = ch
else:                   # 偏宽 → 加高
    nw = cw; nh = int(round(cw/TARGET))
nx0 = int(round(cx - nw/2.0)); ny0 = int(round(cy - nh/2.0))
# 越界则平移回来
nx0 = max(0, min(nx0, clean.size[0]-nw)); ny0 = max(0, min(ny0, clean.size[1]-nh))
card = clean.crop((nx0, ny0, nx0+nw, ny0+nh))
print("normalized -> %dx%d ar=%.4f (target 0.5660)" % (card.size[0], card.size[1], card.size[0]/card.size[1]))

# 放大到成品尺寸（高 954 = 90*10.6）
CH = 954
card = card.resize((int(round(CH*TARGET)), CH), Image.LANCZOS)
card.save(OUT)
print("SAVED", OUT, card.size)

# ---- 并排对比 ----
ref = Image.open(os.path.join(BASE, "yueyuan", "yueyuan_ss04.jpg")).convert("RGB")
refc = ref.crop((700, 800, 940, 1080))   # 真实原图里的卡（手牌，底边被屏幕裁掉）
# 缩放到与 card 同高
rh = CH
rw = int(round(refc.size[0] * rh / refc.size[1]))
refc = refc.resize((rw, rh), Image.LANCZOS)

GAP, PAD, LAB = 56, 40, 52
sheet = Image.new("RGB", (PAD*2 + refc.size[0] + GAP + card.size[0], PAD*2 + LAB + CH), (242, 240, 236))
d = ImageDraw.Draw(sheet)
f = font(26, True); fs = font(19)
lx = PAD
d.text((lx, PAD), "真实原图（月圆之夜 · Steam 实机截图裁切）", fill=(30,28,26), font=f)
d.text((lx, PAD+30), "手牌被屏幕下缘裁切 · 黑底+奶白细内线+四角卷草 · 类型色名称条 · 圆形立绘窗(芥末金)→五角星 →深色文本带",
       fill=(90,86,80), font=fs)
sheet.paste(refc, (lx, PAD+LAB))
rx = PAD + refc.size[0] + GAP
d.text((rx, PAD), "对着原图画的一张（90:159 归一，未去水印已裁）", fill=(30,28,26), font=f)
d.text((rx, PAD+30), "同一版式：厚黑边+奶白内线+角卷草 / 名称条 / 圆形立绘窗 / 五角星 / 底部信息带", fill=(90,86,80), font=fs)
sheet.paste(card, (rx, PAD+LAB))
sheet.save(CMP)
print("SAVED", CMP, sheet.size)
