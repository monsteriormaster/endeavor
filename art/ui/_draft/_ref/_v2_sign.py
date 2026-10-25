# -*- coding: utf-8 -*-
"""苏丹参考图 —— 第一遍签名扫描。
对每张图给出：尺寸 / 主色 / 行亮度剖面(16 段) / 列亮度剖面(16 段) / 强水平线数 / 强垂直线数。
目的：不靠肉眼（本模型读不了图）定位「事件放置画面」，再决定深挖哪几张。
"""
import os, io, glob
from PIL import Image
import numpy as np

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
OUT = os.path.join(REF, "_v2_sign.log")
buf = []
def p(*a): buf.append(" ".join(str(x) for x in a))

files = []
for sub in ["sudan_panel", "sudan", "."]:
    d = os.path.join(REF, sub)
    if not os.path.isdir(d): continue
    for f in sorted(os.listdir(d)):
        if f.endswith(".import"): continue
        if not f.lower().endswith((".png", ".jpg", ".jpeg")): continue
        files.append(os.path.join(d, f))

def prof(v, n=16):
    """把一维亮度数组压成 n 段均值，映射成 0-9 的字符串"""
    idx = np.linspace(0, len(v), n + 1).astype(int)
    out = []
    for i in range(n):
        seg = v[idx[i]:idx[i + 1]]
        m = float(seg.mean()) if len(seg) else 0.0
        out.append(str(max(0, min(9, int(round(m / 25.6))))))
    return "".join(out)

def strong_lines(v, thr_rel=0.55):
    """统计明显偏离全局均值的行数（相对阈值），用来找分隔线/框线"""
    m = float(v.mean()); sd = float(v.std())
    if sd < 1e-6: return 0
    thr = max(6.0, sd * thr_rel)
    return int((np.abs(v - m) > thr).sum())

for f in files:
    try:
        im = Image.open(f).convert("RGB")
    except Exception as e:
        p("ERR", f, e); continue
    W, H = im.size
    a = np.asarray(im, dtype=np.float32)
    lum = 0.299 * a[:, :, 0] + 0.587 * a[:, :, 1] + 0.114 * a[:, :, 2]
    rows = lum.mean(axis=1)
    cols = lum.mean(axis=0)

    small = im.resize((48, 27), Image.BOX)
    pal = small.quantize(colors=5, method=Image.MEDIANCUT).convert("RGB")
    cnt = {}
    for px in pal.getdata():
        cnt[px] = cnt.get(px, 0) + 1
    top = sorted(cnt.items(), key=lambda kv: -kv[1])[:4]
    pals = " ".join("%02X%02X%02X:%.0f%%" % (c[0], c[1], c[2], 100.0 * n / (48 * 27)) for c, n in top)

    p("--", os.path.relpath(f, REF))
    p("   %dx%d  lum min/max/mean=%.0f/%.0f/%.0f  hlines=%d vlines=%d"
      % (W, H, lum.min(), lum.max(), lum.mean(), strong_lines(rows), strong_lines(cols)))
    p("   pal %s" % pals)
    p("   row %s" % prof(rows))
    p("   col %s" % prof(cols))

io.open(OUT, "w", encoding="utf-8").write("\n".join(buf))
print("\n".join(buf[:400]))
