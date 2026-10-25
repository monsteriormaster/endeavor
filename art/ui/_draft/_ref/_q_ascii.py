import os
import numpy as np
from PIL import Image

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
OUT = os.path.join(REF, "_q_ascii.log")

RAMP = " .:-=+*#%@"


def ascii_map(im, cols=104, label=""):
    w, h = im.size
    rows = max(1, int(cols * h / w * 0.50))
    g = im.convert("L").resize((cols, rows), Image.LANCZOS)
    a = np.asarray(g, dtype=np.float32)
    lo, hi = np.percentile(a, 2), np.percentile(a, 98)
    if hi - lo < 1:
        hi = lo + 1
    n = np.clip((a - lo) / (hi - lo), 0, 1)
    lines = []
    for r in range(rows):
        lines.append("".join(RAMP[int(v * 9.999)] for v in n[r]))
    return label, "%dx%d" % (w, h), lines


def palette(im, k=8):
    q = im.convert("RGB").resize((160, 160), Image.LANCZOS).quantize(colors=k, method=Image.MEDIANCUT)
    pal = q.getpalette()
    counts = sorted(q.getcolors(), reverse=True)
    tot = 160 * 160
    out = []
    for cnt, idx in counts:
        r, g, b = pal[idx * 3:idx * 3 + 3]
        out.append("#%02X%02X%02X %5.2f%%" % (r, g, b, cnt * 100.0 / tot))
    return out


TARGETS = [
    ("sudan_panel/wywyx_slots.jpg", 104),
    ("sudan_panel/ali_0403.png", 104),
    ("sudan_panel/ali_0401.png", 92),
    ("sudan_放大_卡带.png", 104),
    ("sudan_放大_装备形态.png", 96),
    ("sudan_ss06.jpg", 104),
]

with open(OUT, "w", encoding="utf-8") as f:
    for rel, cols in TARGETS:
        p = os.path.join(REF, rel.replace("/", os.sep))
        if not os.path.exists(p):
            f.write("MISSING %s\n\n" % rel)
            continue
        im = Image.open(p)
        label, size, lines = ascii_map(im, cols)
        f.write("=" * 110 + "\n")
        f.write("%s   %s\n" % (rel, size))
        f.write("palette: " + " | ".join(palette(im)) + "\n")
        f.write("-" * 110 + "\n")
        for ln in lines:
            f.write(ln + "\n")
        f.write("\n")

print("OK", OUT)
