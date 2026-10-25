# -*- coding: utf-8 -*-
"""收集"卡面到底要装什么"的事实：卡片数量/类型/图标尺寸比例。"""
import io, os, json, glob
from PIL import Image

R = r"C:\Users\26464\IdeaProjects\endeavor"
out = io.open(os.path.join(R, "art", "ui", "_draft", "_ref", "_facts.log"), "w", encoding="utf-8")
def w(*a):
    out.write(" ".join(str(x) for x in a) + "\n"); print(*a)

w("=== resoures/ ===")
for f in sorted(os.listdir(os.path.join(R, "resoures"))):
    w("  ", f, os.path.getsize(os.path.join(R, "resoures", f)))

w("\n=== 找卡片定义文件 ===")
for pat in ("**/*card*.json", "**/*cards*.json"):
    for f in glob.glob(os.path.join(R, pat), recursive=True):
        if "addons" in f: continue
        w("  ", os.path.relpath(f, R), os.path.getsize(f))

w("\n=== 卡面图标尺寸（art/ai_assets_transparent/items + art/*.png 立绘）===")
rows = []
for d in ("art/ai_assets_transparent/items", "art/items", "art/characters_extras", "art"):
    p = os.path.join(R, d)
    if not os.path.isdir(p): continue
    for f in sorted(glob.glob(os.path.join(p, "*.png"))):
        if "_draft" in f: continue
        try:
            im = Image.open(f); ww, hh = im.size
        except Exception as e:
            continue
        rows.append((os.path.relpath(f, R), ww, hh, round(ww/hh, 3)))
for r in rows:
    w("   %-62s %4dx%-5d ar=%.3f" % r)

w("\n=== 汇总：竖/横构图分布 ===")
v = sum(1 for _, ww, hh, _ in rows if ww/hh < 1)
h = sum(1 for _, ww, hh, _ in rows if ww/hh >= 1)
w("   竖构图 %d 张 / 横构图 %d 张 / 共 %d" % (v, h, len(rows)))
out.close()
