# -*- coding: utf-8 -*-
"""量面板相关素材的尺寸 / 不透明边界 / 九宫格安全区（只读，不改图）。
用系统 python（自带 Pillow）跑：
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_measure.py
"""
import os
from PIL import Image

ROOT = r"C:\Users\26464\IdeaProjects\endeavor"

TARGETS = [
    r"art\character_panel_bg.png",
    r"art\ui\frame_square.png",
    r"art\ui\frame_strip.png",
    r"art\ui\frame_strip_ink.png",
    r"art\ui\paper_tile.png",
    r"art\ui\tool_btn.png",
    r"art\ui\nav_btn.png",
    r"art\ui\seal_day.png",
]


def alpha_bbox(im):
    if im.mode not in ("RGBA", "LA"):
        return None
    a = im.convert("RGBA").split()[-1]
    return a.getbbox()


def opaque_ratio(im):
    if im.mode not in ("RGBA", "LA"):
        return 1.0
    a = im.convert("RGBA").split()[-1]
    hist = a.histogram()
    total = sum(hist)
    return sum(hist[8:]) / float(total) if total else 0.0


def border_color(im, x, y):
    return im.convert("RGB").getpixel((x, y))


lines = []
for rel in TARGETS:
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        lines.append("%-34s  MISSING" % rel)
        continue
    im = Image.open(p)
    w, h = im.size
    bb = alpha_bbox(im)
    op = opaque_ratio(im)
    extra = ""
    if bb is not None and (bb != (0, 0, w, h)):
        extra = "  alpha_bbox=%s (内缩 L%d T%d R%d B%d)" % (
            bb, bb[0], bb[1], w - bb[2], h - bb[3])
    lines.append("%-34s  %4d x %4d   size=%.3f  不透明占比=%.3f%s"
                 % (rel, w, h, w / float(h), op, extra))
    if rel.endswith("frame_square.png") and bb is not None:
        # 沿中线扫描，找第一处「明显偏离中心纸色」的列/行 → 内框位置
        rgb = im.convert("RGB")
        cx, cy = w // 2, h // 2
        center = rgb.getpixel((cx, cy))
        # 从左往右扫，找第一次出现「比中心暗很多」的位置（金属边）
        def lum(c):
            return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
        cl = lum(center)
        first_dark_x = None
        for x in range(cx):
            if lum(rgb.getpixel((x, cy))) < cl - 35:
                first_dark_x = x
                break
        first_dark_y = None
        for y in range(cy):
            if lum(rgb.getpixel((cx, y))) < cl - 35:
                first_dark_y = y
                break
        lines.append("     中心纸色=%s L=%.1f  左侧首个暗带 x=%s  上方首个暗带 y=%s"
                     % (str(center), cl, first_dark_x, first_dark_y))

out = "\n".join(lines)
print(out)
with open(os.path.join(ROOT, r"art\ui\_draft\_ref\_panel_measure.txt"), "w", encoding="utf-8") as f:
    f.write(out + "\n")
