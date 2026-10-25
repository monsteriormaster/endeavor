# -*- coding: utf-8 -*-
"""把 v8 布局叠到**游戏真实底图**上：`art/character_panel_bg.png`。

为什么要这一步：mock（`_panel_r1_v8.py`）的边框是我程序化画的细铜线，
而游戏真实底图是 **1370×933 的金色卷草角饰 + 旧纸**，角饰大得多。
按实测，拉伸到 634×520 后：
    左上角饰 x0..279 / y0..257 ，右上 x345..633 / y0..259
    左下 x0..316 / y313..519 ，右下 x317..633 / y260..519
→ 名字(8.5%) / 关闭(18.7%) / 标签(7.6%) 会压在花纹上。
本脚本把真实底图铺进去，**目视确认到底能不能用**，再决定是否微调坐标。

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_realbg_check.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)

import _panel_redesign as pr          # noqa: E402
import _panel_r1_v8 as v8             # noqa: E402
from PIL import Image, ImageDraw      # noqa: E402

S, Fs = pr.S, pr.Fs
BG = os.path.join(R, "art", "character_panel_bg.png")


def real_bg(w, h):
    """按 StyleBoxTexture 的行为：整图拉伸到面板尺寸（SC 倍渲染）。"""
    return Image.open(BG).convert("RGB").resize((S(w), S(h)), Image.LANCZOS)


def main():
    base = real_bg(v8.W, v8.H)
    im, B = v8.r1_v8(v8.STATE_B, base=base, frame_on=False)
    out = im.resize((v8.W, v8.H), Image.LANCZOS)
    p = os.path.join(REF, "面板v8_叠真实底图_状态B.png")
    out.save(p)
    print("写出", p, out.size)

    # 同一张 + 区块框，方便看「内容 vs 花纹」的位置关系
    dbg = pr.draw_debug_rects(im, B).resize((v8.W, v8.H), Image.LANCZOS)
    p2 = os.path.join(REF, "面板v8_叠真实底图_状态B_区块边界.png")
    dbg.save(p2)
    print("写出", p2, dbg.size)

    # A / C 两态也出一遍，确认不会互相打架
    for tag, st in (("A", v8.STATE_A), ("C", v8.STATE_C)):
        i2, _ = v8.r1_v8(st, base=real_bg(v8.W, v8.H), frame_on=False)
        q = os.path.join(REF, "面板v8_叠真实底图_状态%s.png" % tag)
        i2.resize((v8.W, v8.H), Image.LANCZOS).save(q)
        print("写出", q)

    # 与「现役面板尺寸 500×432」的对照（同一张底图按现役尺寸拉伸）
    old = real_bg(500, 432)
    po = os.path.join(REF, "面板v8_底图现役尺寸500x432.png")
    old.resize((500, 432), Image.LANCZOS).save(po)
    print("写出", po)


if __name__ == "__main__":
    main()
