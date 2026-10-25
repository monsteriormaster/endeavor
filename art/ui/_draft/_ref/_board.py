# -*- coding: utf-8 -*-
"""参考原图板：四款游戏真实截图里的卡面，一张板看全。"""
import os
from PIL import Image, ImageDraw, ImageFont

BASE = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"

def font(sz, bold=False):
    for p in ([r"C:\Windows\Fonts\msyhbd.ttc"] if bold else []) + [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        try: return ImageFont.truetype(p, sz)
        except Exception: pass
    return ImageFont.load_default()

ROWS = [
    ("《苏丹的游戏》", "Double Cross / 2P Games · Steam 官方截图 ss00 / ss06",
     "卡面=整片高饱和彩色场（金/绿/米，带金属闪粒肌理）· 细黑键线 + 内侧一条细线 · 卡名深字压在顶部场内 · 下部线稿插画。另有一类特殊「苏丹卡」：近黑底 + 金缠枝带勾出尖拱窗",
     [("sudan/sudan_ss00.jpg", (170, 770, 620, 990)),
      ("sudan/sudan_ss06.jpg", (30, 660, 240, 900))]),
    ("《月圆之夜》", "Giant Network · Steam 官方截图 ss04",
     "厚黑边 + 奶白细内线 + 四角奶白卷草 · 类型色名称条 · 圆形立绘窗（奶白圈 + 芥末金底）· 五角金星 · 深色文本带",
     [("yueyuan/yueyuan_ss04.jpg", (700, 780, 1080, 1080)),
      ("yueyuan/yueyuan_ss00.jpg", (640, 700, 1100, 1080))]),
    ("《忘却前夜》", "B.I.A.V. Studio · Steam 官方截图 ss03",
     "立绘满版出血 · 极细金色哥特尖拱花边（无独立框带）· 白字直接压在画面上、无名称条无文本框",
     [("morimens/morimens_ss03.jpg", (350, 850, 910, 1080)),
      ("morimens/morimens_ss03.jpg", (355, 855, 560, 1080))]),
    ("《王者万象棋》", "腾讯 · 官网 wxq.qq.com 棋子卡条（1480×257 原生）",
     "圆角矩形 · 深蓝外边 + 厚金双线框（四角菱形饰）· 立绘满版 · 左上菱形阵营徽/右上字母徽/左下三枚技能图标/右下 Lv",
     [("wangzhe/wxq_17.png", (0, 0, 794, 257)),
      ("wangzhe/wxq_13.png", (0, 0, 740, 257))]),
]

RH = 250           # 每行图高
PAD, LABW, GAP = 30, 300, 24
sheet_w = PAD*2 + LABW + GAP + 1400
sheet_h = PAD*2 + len(ROWS)*RH + (len(ROWS)-1)*22
sheet = Image.new("RGB", (sheet_w, sheet_h), (240, 238, 234))
d = ImageDraw.Draw(sheet)
f_name, f_src, f_note = font(23, True), font(15), font(15)

y = PAD
for name, src, note, imgs in ROWS:
    d.text((PAD, y+2), name, fill=(24,22,20), font=f_name)
    d.text((PAD, y+34), src, fill=(100,95,88), font=f_src)
    # 折行注释
    line, ly = "", y+58
    for ch in note:
        if len(line) >= 16:
            d.text((PAD, ly), line, fill=(70,66,60), font=f_note); ly += 21; line = ""
        line += ch
    if line: d.text((PAD, ly), line, fill=(70,66,60), font=f_note)

    x = PAD + LABW + GAP
    for rel, box in imgs:
        im = Image.open(os.path.join(BASE, rel)).convert("RGB")
        c = im.crop(box)
        s = min(RH/c.size[1], 660/c.size[0])
        c = c.resize((max(1,int(c.size[0]*s)), max(1,int(c.size[1]*s))), Image.LANCZOS)
        sheet.paste(c, (x, y + (RH - c.size[1])//2))
        x += c.size[0] + 18
    y += RH + 22

sheet.save(os.path.join(BASE, "参考原图_四游戏.png"))
print("SAVED 参考原图_四游戏.png", sheet.size)
