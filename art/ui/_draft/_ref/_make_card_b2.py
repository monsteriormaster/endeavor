# -*- coding: utf-8 -*-
"""生成 B2 卡面素材（4x = 360×636，满版不透明），并**先备份**旧卡面。

B2 设计（用户选定）= 骨面 + 细铜双线 + 墨压线 + 内缘第二道细线 + 顶中徽记。
几何全部按 1x 的 90×159 写，内部 ×4。素材本身**不编码**名字/立绘分界（分界在 card_chip.gd 里）。
"""
import os, shutil
from PIL import Image, ImageDraw

R = r"C:\Users\26464\IdeaProjects\endeavor"
ART = os.path.join(R, "art")
BAK = os.path.join(ART, "ai_assets_transparent", "card_frame_20260927_v0")

CARD_W, CARD_H = 90, 159
SC = 4                      # 4x → 360×636
S = lambda v: int(round(v * SC))
CW, CH = CARD_W * SC, CARD_H * SC

# ---- B2 配色（= 用户选定的 B 骨面色调）----
BODY   = (231, 222, 202)
HI     = (250, 245, 232)
LO     = (185, 177, 162)
BRASS  = (170, 140, 70)
BRASS2 = (206, 176, 104)
INK    = (104, 74, 44)

BORDER = [(0.8, BRASS, 1.3), (2.1, BRASS, 0.6), (3.0, INK, 0.5)]   # 外圈：铜 1.3 / 铜 0.6 / 墨 0.5
INNER_LINE = (5.0, (150, 122, 60), 0.45)                           # B2 的内缘第二道细线
CREST_Y = 3.0                                                      # B2 的顶中徽记坐在外圈墨线上


def lozenge(d, cx, cy, r, col):
    d.polygon([(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))], fill=col)


def build() -> Image.Image:
    im = Image.new("RGB", (CW, CH), BODY)
    d = ImageDraw.Draw(im)

    # 1) 厚度：顶/左亮、底/右暗
    d.rectangle([0, 0, CW - 1, S(1.4) - 1], fill=HI)
    d.rectangle([0, 0, S(1.4) - 1, CH - 1], fill=HI)
    d.rectangle([0, CH - S(1.8), CW - 1, CH - 1], fill=LO)
    d.rectangle([CW - S(1.8), 0, CW - 1, CH - 1], fill=LO)

    # 2) 外圈细铜双线 + 墨压线
    for ins, col, w in BORDER:
        d.rectangle([S(ins), S(ins), CW - 1 - S(ins), CH - 1 - S(ins)], outline=col, width=max(1, S(w)))

    # 3) B2：内缘第二道细线
    ins, col, w = INNER_LINE
    d.rectangle([S(ins), S(ins), CW - 1 - S(ins), CH - 1 - S(ins)], outline=col, width=max(1, S(w)))

    # 4) B2：顶中徽记 = 外菱形 + 挖芯 + 两侧短须
    lozenge(d, 45.0, CREST_Y, 2.4, BRASS2)
    lozenge(d, 45.0, CREST_Y, 1.1, BODY)
    for ax in (1, -1):
        x0, x1 = 45 + ax * 5.0, 45 + ax * 11.0
        d.rectangle([min(S(x0), S(x1)), S(CREST_Y - 0.4), max(S(x0), S(x1)), S(CREST_Y + 0.4)], fill=BRASS)

    return im


def main():
    # ---------- 备份（无 git，覆盖不可逆）----------
    os.makedirs(BAK, exist_ok=True)
    for fn in ("card.png", "card.png.import"):
        src = os.path.join(ART, fn)
        dst = os.path.join(BAK, fn)
        if os.path.exists(src):
            if os.path.exists(dst):
                print("跳过（备份已存在）", fn)
            else:
                shutil.copy2(src, dst)
                print("已备份", fn, "→", os.path.relpath(dst, R))
    # 顺带把旧卡面的原始 .ctex 也存一份，便于回滚比对
    old_ctex = os.path.join(R, ".godot", "imported", "card.png-cbf59a8dc0f4acbf700dd43db8122ba8.ctex")
    if os.path.exists(old_ctex):
        dst = os.path.join(BAK, "card.png.ctex")
        if not os.path.exists(dst):
            shutil.copy2(old_ctex, dst)
            print("已备份旧 .ctex")

    # ---------- 出图 ----------
    im = build()
    out = os.path.join(ART, "card.png")
    im.convert("RGBA").save(out)
    print("写出 %s  %s  RGBA 全不透明（alpha=255）" % (os.path.relpath(out, R), im.size))
    print("  比例 %.4f  目标显示 90×159 = %.4f" % (im.size[0] / im.size[1], 90 / 159.0))

    # ---------- 附带产出：3x / 1x 便于人眼比对 ----------
    dbg = os.path.join(ART, "ui", "_draft", "_ref")
    for s, tag in ((3, "3x"), (1, "1x实尺"), (8, "1x像素放大8x")):
        if s == 8:
            v = im.resize((90, 159), Image.LANCZOS).resize((90 * 8, 159 * 8), Image.NEAREST)
        else:
            v = im.resize((90 * s, 159 * s), Image.LANCZOS)
        p = os.path.join(dbg, "卡面B2_落地素材_%s.png" % tag)
        v.save(p)
        print("  →", os.path.basename(p), v.size)


main()
