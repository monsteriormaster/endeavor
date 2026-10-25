# -*- coding: utf-8 -*-
"""侦察：card.png 的尺寸/模式/alpha 情况；Godot 进程是否在跑。"""
import os, subprocess
from PIL import Image

R = r"C:\Users\26464\IdeaProjects\endeavor"
p = os.path.join(R, "art", "card.png")
im = Image.open(p)
print("card.png:", im.size, im.mode, "比例 %.4f" % (im.size[0] / im.size[1]))
if im.mode in ("RGBA", "LA"):
    a = im.convert("RGBA").getchannel("A")
    ex = a.getextrema()
    print("  alpha 范围:", ex)
    if ex[0] < 255:
        import collections
        hist = a.histogram()
        tot = sum(hist)
        zero = hist[0]
        print("  全透明像素占比 %.2f%%" % (zero * 100.0 / tot))
    else:
        print("  → 完全不透明")
else:
    print("  → 无 alpha 通道")

print("\n--- 现有 card.png 关联的导入文件 ---")
for ext in (".import",):
    f = p + ext
    print(ext, "存在" if os.path.exists(f) else "缺失")
d = os.path.join(R, ".godot", "imported")
if os.path.isdir(d):
    hits = [f for f in os.listdir(d) if f.startswith("card.png-")]
    print(".godot/imported 里 card 相关:", hits)
    for h in hits:
        print("  ", h, os.path.getsize(os.path.join(d, h)))

print("\n--- Godot 进程 ---")
try:
    out = subprocess.run(["tasklist", "/FO", "CSV"], capture_output=True, encoding="gbk", errors="replace").stdout
    lines = [l for l in out.splitlines() if "godot" in l.lower()]
    print("\n".join(lines) if lines else "（没有 Godot 进程在跑）")
except Exception as e:
    print("tasklist 失败:", e)
