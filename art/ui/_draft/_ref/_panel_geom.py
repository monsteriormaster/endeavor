# -*- coding: utf-8 -*-
"""复核人物面板真实几何：按 character_panel.gd 的公式算出立绘实际矩形，并画到截图上。
只读 + 输出一张标注图，不改任何游戏文件。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_geom.py
"""
import os
from PIL import Image, ImageDraw

ROOT = r"C:\Users\26464\IdeaProjects\endeavor"
OUT = os.path.join(ROOT, r"art\ui\_draft\_ref")

# ---- 1. character_panel.gd 的真实常量（交叉核对过源码） ----
PANEL = (500, 432)          # character_panel.tscn: size = Vector2i(500, 432)
MARGIN = (4, 4, 496, 428)   # $margin offset
WID, LEN = 220, 440         # character_panel.gd: const WID = 220 / LEN = 440
AVATAR_POS = (350, 200)     # $margin/avatar.position（Sprite2D，centered 默认 true → 这是中心点）

# ---- 2. 面板内各控件的真实矩形（来自 --dump） ----
RECTS = {
    "nickname  (325,10)-(405,33)": (325, 10, 405, 33),
    "description (21,34)-(426,74)": (21, 34, 426, 74),
    "att (19,133)-(165,374)": (19, 133, 165, 374),
    "tags (172,76)-(318,372)": (172, 76, 318, 372),
    "equipment (17,337)-(339,403)": (17, 337, 339, 403),
    "closebutton (466,0)-(492,31)": (466, 0, 492, 31),
}

lines = []

# ---- 3. 立绘实际矩形 ----
hero = os.path.join(ROOT, r"art\hero.png")
if os.path.exists(hero):
    w, h = Image.open(hero).size
    ratio = min(WID / float(w), LEN / float(h))
    dw, dh = w * ratio, h * ratio
    cx, cy = AVATAR_POS
    rect = (cx - dw / 2.0, cy - dh / 2.0, cx + dw / 2.0, cy + dh / 2.0)
    lines.append("hero.png 原始 = %d x %d  (比 %.3f)" % (w, h, w / float(h)))
    lines.append("scale_ratio = min(%d/%d, %d/%d) = %.4f" % (WID, w, LEN, h, ratio))
    lines.append("立绘实际渲染 = %.0f x %.0f" % (dw, dh))
    lines.append("立绘矩形（含 centered 居中）= (%.0f, %.0f) - (%.0f, %.0f)" % rect)
    lines.append("  → 相对面板：上溢 %.0f / 下溢 %.0f / 左 %.0f / 右 %.0f"
                 % (max(0, -rect[1]), max(0, rect[3] - PANEL[1]),
                    max(0, -rect[0]), max(0, rect[2] - PANEL[0])))
    # 与各控件重叠
    for name, r in RECTS.items():
        ox = min(rect[2], r[2]) - max(rect[0], r[0])
        oy = min(rect[3], r[3]) - max(rect[1], r[1])
        if ox > 0 and oy > 0:
            lines.append("  ⚠ 与 %s 重叠 %.0f x %.0f px" % (name, ox, oy))
    AV = rect
else:
    AV = None

# ---- 4. 标注到截图 ----
src = os.path.join(ROOT, r"debug\_p_char.png")
if os.path.exists(src):
    im = Image.open(src).convert("RGB")
    d = ImageDraw.Draw(im)
    # 面板截图时被我手动放在视图中心：(1920-500)/2, (1080-432)/2
    OX, OY = (1920 - PANEL[0]) // 2, (1080 - PANEL[1]) // 2
    box = (OX, OY, OX + PANEL[0], OY + PANEL[1])
    d.rectangle(box, outline=(255, 0, 0), width=2)
    if AV:
        d.rectangle((OX + AV[0], OY + AV[1], OX + AV[2], OY + AV[3]),
                    outline=(0, 255, 0), width=2)
    for i, (name, r) in enumerate(RECTS.items()):
        col = [(255, 200, 0), (0, 200, 255), (255, 0, 255), (200, 255, 0),
               (255, 120, 0), (0, 255, 200)][i % 6]
        d.rectangle((OX + r[0], OY + r[1], OX + r[2], OY + r[3]), outline=col, width=1)
    # 2x 放大裁到面板 + 240px 环境
    pad = 120
    crop = im.crop((OX - pad, OY - pad, OX + PANEL[0] + pad, OY + PANEL[1] + pad))
    crop = crop.resize((crop.width * 2, crop.height * 2), Image.NEAREST)
    out_png = os.path.join(OUT, "面板复核_人物面板_几何标注.png")
    crop.save(out_png)
    lines.append("标注图 → %s (%dx%d)" % (out_png, crop.width, crop.height))

txt = "\n".join(lines)
print(txt)
with open(os.path.join(OUT, "_panel_geom.txt"), "w", encoding="utf-8") as f:
    f.write(txt + "\n")
