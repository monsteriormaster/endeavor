# -*- coding: utf-8 -*-
"""从 1920×1080 真截图里裁出卡牌区：① 1:1 原样 ② 2x ③ 单卡 6x 看描边。"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
SHOT = os.path.join(R, "debug", "_card_b2_after.png")
OUT = os.path.join(R, "art", "ui", "_draft", "_ref")

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

im = Image.open(SHOT).convert("RGB")
print("截图", im.size)

# 卡牌区：卡位从 x140 起，卡 90×159，间隔 18；货架 y822~1060
CROP = (130, 830, 1110, 1050)
band = im.crop(CROP)
band.save(os.path.join(OUT, "落地验收_卡牌区_1x.png"))
print("SAVED 落地验收_卡牌区_1x.png", band.size)

# 2x
b2 = band.resize((band.width * 2, band.height * 2), Image.LANCZOS)
b2.save(os.path.join(OUT, "落地验收_卡牌区_2x.png"))
print("SAVED 落地验收_卡牌区_2x.png", b2.size)

# 单卡 6x（第 1 张「主角」+ 第 5 张「精心磨制的小刀」两行名）
for i, lab in ((0, "主角"), (4, "精心磨制的小刀")):
    x0 = 140 + i * 108
    card = im.crop((x0, 861, x0 + 90, 861 + 159))
    big = card.resize((90 * 6, 159 * 6), Image.NEAREST)
    p = os.path.join(OUT, "落地验收_单卡6x_%d.png" % (i + 1))
    big.save(p)
    print("SAVED", os.path.basename(p), big.size, "←", lab)

# 横向拼一张对照条：两张单卡并排
a = im.crop((140, 861, 230, 1020)).resize((540, 954), Image.NEAREST)
b = im.crop((140 + 4 * 108, 861, 140 + 4 * 108 + 90, 1020)).resize((540, 954), Image.NEAREST)
sh = Image.new("RGB", (540 * 2 + 70, 954 + 110), (150, 153, 158))
d = ImageDraw.Draw(sh)
d.text((26, 14), "引擎真图 · 单卡 6x（NEAREST）—— 左：1 行名「主角」　右：2 行名「精心磨制的小刀」",
       fill=(255, 255, 255), font=font(22, True))
d.text((26, 48), "验两件事：① 四层描边在真渲染里读不读得出　② 两行预留有没有让立绘区高度一致",
       fill=(220, 224, 230), font=font(16))
sh.paste(a, (26, 84))
sh.paste(b, (26 + 540 + 18, 84))
sh.save(os.path.join(OUT, "落地验收_单卡6x对照.png"))
print("SAVED 落地验收_单卡6x对照.png", sh.size)
