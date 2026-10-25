# -*- coding: utf-8 -*-
"""量化：21 个道具素材的"不透明像素平均亮度"，判断白底/暗底上的对比度。
并出一张 1x 实尺 + 4x 局部放大的"白底可行性判定"图。"""
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

def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

names = ["朱利安(立绘)"] + [f[:-4] for f in os.listdir(os.path.join(R, "art", "items")) if f.endswith(".png")]
paths = {"朱利安(立绘)": os.path.join(R, "art", "hero.png")}
for f in os.listdir(os.path.join(R, "art", "items")):
    if f.endswith(".png"):
        paths[f[:-4]] = os.path.join(R, "art", "items", f)

WHITE_L, DARK_L = 255.0, lum((74, 55, 43))
BONE_L = lum((231, 222, 202))

rows = []
for n in names:
    im = Image.open(paths[n]).convert("RGBA")
    al = im.getchannel("A")
    px, ap = im.load(), al.load()
    w, h = im.size
    tot = 0; s = 0.0
    for y in range(h):
        for x in range(w):
            if ap[x, y] > 200:
                s += lum(px[x, y][:3]); tot += 1
    if tot == 0:
        rows.append((n, -1, 0)); continue
    m = s / tot
    rows.append((n, m, tot / float(w * h)))

rows.sort(key=lambda r: r[1])
print("素材            不透明均亮   覆盖率   白底对比  暗底对比  骨底对比  判定(白底)")
print("-" * 90)
fail = []
for n, m, cov in rows:
    cw_, cd, cb = abs(WHITE_L - m), abs(DARK_L - m), abs(BONE_L - m)
    if m < 0: verdict = "空"
    elif cw_ < 32: verdict = "★ 糊掉"; fail.append(n)
    elif cw_ < 55: verdict = "弱"
    else: verdict = "OK"
    print("%-14s %6.1f      %5.1f%%   %6.1f    %6.1f    %6.1f   %s" % (n, m, cov * 100, cw_, cd, cb, verdict))

print("\n白底会糊掉的素材（%d / %d）：" % (len(fail), len(rows)))
for f in fail: print("  -", f)

# ---------- 判定图：1x 实尺 + 4x 局部 ----------
ITEMS13 = [("朱利安", os.path.join(R, "art", "hero.png")), ("蓝宝石项链", IT("蓝宝石项链")),
           ("章鱼尾人身塑像", IT("章鱼尾人身塑像")), ("几何原本", IT("几何原本")),
           ("可疑的信", IT("可疑的信")), ("被诅咒的古董", IT("被诅咒的古董")),
           ("精心磨制的小刀", IT("精心磨制的小刀")), ("银之钥", IT("银之钥")),
           ("骑士盔甲", IT("骑士盔甲")), ("物种起源", IT("物种起源"))]

def card_norm(path, bg):
    """把素材按立绘盒 78×111 等比放进 90×159 卡，白卡 = 纯白底。"""
    S = lambda v: int(round(v * 4))
    c = Image.new("RGB", (90 * 4, 159 * 4), bg)
    d = ImageDraw.Draw(c)
    d.rectangle([0, 0, c.size[0] - 1, c.size[1] - 1], outline=(150, 88, 30), width=4)
    art = Image.open(path).convert("RGBA")
    bw, bh = S(78), S(110.6)
    s = min(bw / art.size[0], bh / art.size[1])
    art = art.resize((max(1, int(round(art.size[0] * s))), max(1, int(round(art.size[1] * s)))), Image.LANCZOS)
    c.paste(art, (S(6) + (bw - art.size[0]) // 2, S(44.4) + (bh - art.size[1]) // 2), art)
    return c

CP, CG = 30, 20
CW4, CH4 = 90 * 4, 159 * 4
sheet = Image.new("RGB", (CP * 2 + len(ITEMS13) * (CW4 + CG) - CG + 40, 40 + CH4 + 220), (150, 152, 156))
d = ImageDraw.Draw(sheet)
f6, f7 = font(22, True), font(15)
d.text((CP, 12), "白底可行性判定（4x）—— 每个素材同时放「白底」和「暗底」，看哪个糊", fill=(255, 255, 255), font=f6)
for i, (n, p) in enumerate(ITEMS13):
    x = CP + i * (CW4 + CG)
    sheet.paste(card_norm(p, (255, 255, 255)), (x, 48))
    sheet.paste(card_norm(p, (74, 55, 43)), (x, 48 + CH4 + 34))
    d.text((x + CW4 // 2, 48 + CH4 * 2 + 44), n, fill=(255, 255, 255), font=f7, anchor="ma")
sheet.save(os.path.join(BASE, "白底可行性判定.png"))
print("\nSAVED 白底可行性判定.png", sheet.size)
