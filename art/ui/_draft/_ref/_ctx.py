# -*- coding: utf-8 -*-
"""一图看清：现有容器美术 + 卡面要装的内容。"""
import os
from PIL import Image, ImageDraw, ImageFont
R = r"C:\Users\26464\IdeaProjects\endeavor"
def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

ITEMS = [
    ("art/card.png", "art/card.png  现卡面 367x648"),
    ("art/ai_assets_transparent/objects/trigger.png", "trigger.png  触发器底图"),
    ("art/character_panel_bg.png", "character_panel_bg.png 面板底图"),
    ("art/items/蓝宝石项链.png", "道具·竖 蓝宝石项链 0.638"),
    ("art/items/几何原本.png", "道具·横 几何原本 1.341"),
    ("art/hero.png", "立绘 hero 1088x1920 ar0.567"),
    ("art/ui/paper_tile.png", "ui/paper_tile 平铺纸"),
    ("art/ui/nav_btn.png", "ui/nav_btn 报纸按钮"),
    ("art/ui/frame_square.png", "ui/frame_square 未接入"),
]
CH = 420
GAP, PAD, LAB, COLS = 22, 28, 40, 3
rows = (len(ITEMS)+COLS-1)//COLS
CW = int(CH*1.5)
sheet = Image.new("RGB", (PAD*2+COLS*CW+(COLS-1)*GAP, PAD*2+rows*(LAB+CH)+(rows-1)*GAP), (238,236,232))
d = ImageDraw.Draw(sheet); f = font(17)
for i,(rel,txt) in enumerate(ITEMS):
    p = os.path.join(R, rel)
    r,c = divmod(i,COLS)
    x = PAD+c*(CW+GAP); y = PAD+r*(LAB+CH+GAP)
    d.text((x,y+4), txt, fill=(30,28,26), font=f)
    if not os.path.exists(p):
        d.text((x,y+60), "MISSING", fill=(180,50,40), font=f); continue
    im = Image.open(p)
    if im.mode in ("RGBA","LA","P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (60,60,60)); bg.paste(im, mask=im.split()[-1]); im = bg
    else: im = im.convert("RGB")
    s = min(CH/im.size[1], CW/im.size[0])
    im = im.resize((max(1,int(im.size[0]*s)), max(1,int(im.size[1]*s))), Image.LANCZOS)
    sheet.paste(im, (x+(CW-im.size[0])//2, y+LAB))
sheet.save(os.path.join(R,"art/ui/_draft/_ref/现有素材与卡面内容.png"))
print("SAVED", sheet.size)
