# -*- coding: utf-8 -*-
"""把彩铅按钮装进 loading 标题界面（1920x1080 原尺寸）：上半 v4，下半 v5"""
import os, numpy as np
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
ROOT = r"C:\Users\26464\IdeaProjects\endeavor"
LOG = os.path.join(BASE, "_mock_log.txt")
lines = []
def P(*x):
    lines.append(" ".join(str(i) for i in x))

MARGIN = 14
FA = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 20)
FB = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 40)


def nine_slice(src, w, h, m):
    tw, th = src.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, chh = max(1, w - 2 * m), max(1, h - 2 * m)
    spec = [
        (0, 0, m, m, 0, 0), (m, 0, tw - m, m, m, 0), (tw - m, 0, tw, m, w - m, 0),
        (0, m, m, th - m, 0, m), (m, m, tw - m, th - m, m, m), (tw - m, m, tw, th - m, w - m, m),
        (0, th - m, m, th, 0, h - m), (m, th - m, tw - m, th, m, h - m), (tw - m, th - m, tw, th, w - m, h - m),
    ]
    for sx0, sy0, sx1, sy1, dx, dy in spec:
        dw = m if dx in (0, w - m) else cw
        dh = m if dy in (0, h - m) else chh
        c = src.crop((sx0, sy0, sx1, sy1)).resize((max(1, dw), max(1, dh)), Image.LANCZOS)
        out.paste(c, (dx, dy))
    return out


BTNS = [
    ("继续游戏", 764, 120), ("新游戏", 764, 276), ("商店", 764, 424),
    ("设置", 764, 572), ("成就", 764, 720), ("退出游戏", 764, 868),
]
W_BTN, H_BTN = 393, 99

ta = Image.open(os.path.join(BASE, "btn_pencil_v4.png")).convert("RGBA")
tb = Image.open(os.path.join(BASE, "btn_pencil_v5.png")).convert("RGBA")
P("v4", ta.size, " v5", tb.size)

bg = Image.open(os.path.join(ROOT, "art", "title_bg.png")).convert("RGBA")
P("背景", bg.size)

top = bg.copy()
bot = bg.copy()
dt = ImageDraw.Draw(top)
db = ImageDraw.Draw(bot)
for text, x, y in BTNS:
    for canvas, tex, dr in ((top, ta, dt), (bot, tb, db)):
        b = nine_slice(tex, W_BTN, H_BTN, MARGIN)
        canvas.paste(b, (x, y), b)
        dr.text((x + W_BTN / 2, y + H_BTN / 2), text, font=FB, fill=(38, 29, 18, 255), anchor="mm")

BAR = 40
stack = Image.new("RGBA", (bg.width, bg.height * 2 + BAR), (0, 0, 0, 255))
stack.paste(top, (0, 0))
stack.paste(bot, (0, bg.height + BAR))
d2 = ImageDraw.Draw(stack)
d2.rectangle([0, 0, bg.width, BAR - 1], fill=(24, 20, 16, 255))
d2.text((20, 8), "v4 · 单笔 + 笔压呼吸", font=FA, fill=(220, 214, 204, 255))
d2.rectangle([0, bg.height + BAR - 1, bg.width, bg.height + BAR * 2 - 1], fill=(24, 20, 16, 255))
d2.text((20, bg.height + BAR + 7), "v5 · 双笔叠色 + 四角排线 + 收笔出锋", font=FA, fill=(220, 214, 204, 255))

out = stack.convert("RGB")
tw = 1180
out = out.resize((tw, int(out.height * tw / out.width)), Image.LANCZOS)
out.save(os.path.join(BASE, "_mock_loading_v5.png"))
P("已存 _mock_loading_v5.png", out.size)
open(LOG, "w", encoding="utf-8").write("\n".join(lines))
