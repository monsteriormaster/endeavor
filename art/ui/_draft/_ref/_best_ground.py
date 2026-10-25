# -*- coding: utf-8 -*-
"""算最优卡身亮度：对每个候选底，求全素材"最差对比度/平均对比度"，找最稳的那个。"""
import os
from PIL import Image

R = r"C:\Users\26464\IdeaProjects\endeavor"
BASE = os.path.join(R, "art", "ui", "_draft", "_ref")

def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]

paths = {"朱利安(立绘)": os.path.join(R, "art", "hero.png")}
for f in os.listdir(os.path.join(R, "art", "items")):
    if f.endswith(".png"):
        paths[f[:-4]] = os.path.join(R, "art", "items", f)

items = {}
for n, p in paths.items():
    im = Image.open(p).convert("RGBA")
    px, ap = im.load(), im.getchannel("A").load()
    w, h = im.size
    # 只取靠近物体的像素（alpha 高）+ 排除全透明区
    s = 0.0; t = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if ap[x, y] > 200:
                s += lum(px[x, y][:3]); t += 1
    if t:
        items[n] = s / t
print("素材数", len(items))

CAND = [
    ("白 255", 255), ("骨 231 (现B)", 231), ("浅暖 200", 200), ("中亮 160", 160),
    ("中调 128", 128), ("中调 115", 115), ("中暗 96", 96), ("暗 74 (现A)", 74), ("暗 55 实测", 55),
]
print("\n%-16s %8s %8s %8s   %s" % ("候选底", "最差对比", "平均对比", "标准差", "最差的那个素材"))
print("-" * 84)
rows = []
for lab, L in CAND:
    ds = [(abs(L - v), n) for n, v in items.items()]
    ds.sort()
    mn, mnn = ds[0]
    mean = sum(d for d, _ in ds) / len(ds)
    var = (sum((d - mean) ** 2 for d, _ in ds) / len(ds)) ** 0.5
    rows.append((mn, mean, var, lab, L, mnn))
    print("%-16s %8.1f %8.1f %8.1f   %s" % (lab, mn, mean, var, mnn))

rows.sort(key=lambda r: -r[0])
print("\n按【最差对比度】从好到差：")
for mn, mean, var, lab, L, mnn in rows:
    print("  %-16s 最差 %6.1f  平均 %6.1f   (最差素材: %s)" % (lab, mn, mean, mnn))

best = rows[0]
print("\n>>> 结论：最稳的卡身亮度 L≈%d（%s），最差对比 %.1f；白底最差 %.1f"
      % (best[4], best[3], best[0], dict((r[3], r[0]) for r in rows)["白 255"]))
