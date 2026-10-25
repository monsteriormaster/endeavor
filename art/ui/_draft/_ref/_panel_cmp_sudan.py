# -*- coding: utf-8 -*-
"""苏丹人物面板 ↔ 本作面板：对照 + 量化诊断板。

数据来源（全部实测，非目测）：
  · 苏丹截图 art/ui/_draft/_ref/sudan/sudan_ss06.jpg（1920×1080）
    左栏（x 430..1300，避开左侧「银」等级章）逐行亮像素计数 → 分区带
      y 314..332  描述句            （高 19）
      y 417..441  「属性」小标题     （高 24）
      y 486       通栏细分隔线        （1px，n=189）
      y 570..607  属性行（图标框+名称+数字）
      y 725       通栏细分隔线        （1px，n=174）
      y 770..815  「标签」+ 标签值
    面板本体 ≈ x 400..1665 / y 300..870 → 1265×570（宽高比 2.22）
    属性行横向元素（y 565..625 扫列）：图标框 x 415..455 / 「体魄」460..488 / 「10」557..571
  · 本作 art/ui/_draft/_ref/面板R1改v7_状态B_1x.png（634×510）

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_cmp_sudan.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

REF = r"C:\Users\26464\IdeaProjects\endeavor\art\ui\_draft\_ref"
SUDAN = os.path.join(REF, "sudan", "sudan_ss06.jpg")
OURS = os.path.join(REF, "面板R1改v7_状态B_1x.png")

# 苏丹面板裁切（源坐标）
BOX = (396, 296, 1670, 874)          # 1274 × 578
SU_W, SU_H = BOX[2] - BOX[0], BOX[3] - BOX[1]

# 实测分区带（源坐标 y）
SU_BANDS = [
    ("描述句（一行，铺满整幅宽）", 314, 332, (120, 210, 255)),
    ("「属性」小标题", 417, 441, (255, 210, 120)),
    ("通栏细分隔线", 486, 488, (255, 120, 120)),
    ("属性行：图标框 + 名称 + 数字", 565, 612, (140, 230, 150)),
    ("通栏细分隔线", 725, 727, (255, 120, 120)),
    ("「标签」+ 标签值", 765, 820, (215, 160, 255)),
]

# 本作坐标（1x）
OUR_BANDS = [
    ("名字 27px（11px 的行都靠它压着）", 29, 67, (255, 210, 120)),
    ("金线", 112, 112, (255, 120, 120)),
    ("属性 4 行（每行 38 高，pitch 52）", 144, 328, (140, 230, 150)),
    ("描述（一行，关在 246 宽的左栏里）", 382, 402, (120, 210, 255)),
    ("标签（胶囊）", 446, 472, (215, 160, 255)),
]


def font(sz):
    for p in (r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


F_T, F_S, F_M = font(20), font(14), font(15)


def build():
    sc = 900.0 / SU_W
    su = Image.open(SUDAN).convert("RGB").crop(BOX).resize((900, int(SU_H * sc)), Image.LANCZOS)
    ours = Image.open(OURS).convert("RGB")

    OW, OH = 634, 510
    PAD, GAP = 40, 34
    W = max(su.size[0], OW) + PAD * 2
    HDR = 356
    H = HDR + 28 + su.size[1] + GAP + 28 + OH + 40

    sh = Image.new("RGB", (W, H), (34, 32, 29))
    d = ImageDraw.Draw(sh)

    # ---------- 表头 ----------
    d.text((PAD, 18), "为什么《苏丹的游戏》的人物面板「自然」—— 逐条实测对照", font=F_T, fill=(240, 232, 214))
    lines = [
        ("① 留白被「命名 + 划线」框住", (255, 236, 170)),
        ("   苏丹每个区块都有一行小标题（属性 / 标签）+ 一条通栏细线；本作把标题全删了，空白裸露在外。", (150, 220, 150)),
        ("② 「一区一行」，不是「一区四行」", (255, 236, 170)),
        ("   苏丹：一条属性行独占约 310px 区块高（行本身 38px）—— 一个属性占 310px。", (150, 220, 150)),
        ("   本作：4 条挤进 184px → 每行 46px。疏密差 6.7 倍，越密越像表格。", (226, 160, 120)),
        ("③ 行有「骨架」把一行撑开", (255, 236, 170)),
        ("   苏丹行 = [图标框 415–455] + [名称 460–488] + [数字 557–571]；本作只有两段紧挨的文字。", (150, 220, 150)),
        ("④ 立绘占面板高约 80%，且出血到边", (255, 236, 170)),
        ("   苏丹立绘顶到上/右/下内缘；本作占 67%，四周还留一圈空纸 —— 右半边有一整块「空的」。", (150, 220, 150)),
        ("⑤ 底色是「材质」，不是「纯色」", (255, 236, 170)),
        ("   苏丹底是带纹理的深皮革，空白读作材质；本作底是平涂米色，空白读作「没画」。", (150, 220, 150)),
        ("※ 反直觉的一条：苏丹的属性行内容也「缩在左边」（x415–571 只占栏宽 18%）。", (255, 190, 110)),
        ("   所以「没排满」不是病根 —— 病根是留白没有被框住、也没有材质。", (255, 190, 110)),
    ]
    y = 50
    for txt, c in lines:
        d.text((PAD, y), txt, font=F_S, fill=c)
        y += 21

    # ---------- 苏丹面板 ----------
    ysu = HDR
    d.text((PAD, ysu), "苏丹 · 官方截图 ss06（左栏区；已按实测坐标标出每个分区带）", font=F_M, fill=(226, 210, 180))
    ysu += 28
    su2 = su.copy()
    d2 = ImageDraw.Draw(su2)
    for name, y0, y1, col in SU_BANDS:
        Y0 = int((y0 - BOX[1]) * sc)
        Y1 = int((y1 - BOX[1]) * sc)
        d2.rectangle([0, Y0, su2.size[0] - 1, max(Y1, Y0 + 1)], outline=col, width=2)
        d2.rectangle([0, Y0 - 1, 250, Y0 + 17], fill=(20, 18, 16))
        d2.text((4, Y0), name, font=font(13), fill=col)
    # 属性区高度括号（rule 486 → rule 725）
    bx = su2.size[0] - 8
    a1, a2 = int((486 - BOX[1]) * sc), int((725 - BOX[1]) * sc)
    d2.line([bx, a1, bx, a2], fill=(255, 90, 90), width=3)
    d2.line([bx - 12, a1, bx, a1], fill=(255, 90, 90), width=3)
    d2.line([bx - 12, a2, bx, a2], fill=(255, 90, 90), width=3)
    d2.text((bx - 250, (a1 + a2) // 2 - 10), "「属性」区高 239px，里面只有 1 行", font=font(15), fill=(255, 140, 140))
    sh.paste(su2, (PAD, ysu))
    ysu += su2.size[1] + GAP

    # ---------- 本作面板 ----------
    d.text((PAD, ysu), "本作 · v7（1:1 真实大小，同样的标注）", font=F_M, fill=(226, 210, 180))
    ysu += 28
    o2 = ours.copy()
    d3 = ImageDraw.Draw(o2)
    for name, y0, y1, col in OUR_BANDS:
        d3.rectangle([0, y0, OW - 1, max(y1, y0 + 1)], outline=col, width=2)
        d3.rectangle([0, y0 - 1, 268, y0 + 16], fill=(250, 246, 236))
        d3.text((4, y0), name, font=font(12), fill=(120, 60, 30))
    a1, a2 = 112, 370
    bx = OW - 8
    d3.line([bx, a1, bx, a2], fill=(200, 40, 40), width=3)
    d3.line([bx - 12, a1, bx, a1], fill=(200, 40, 40), width=3)
    d3.line([bx - 12, a2, bx, a2], fill=(200, 40, 40), width=3)
    d3.text((bx - 200, (a1 + a2) // 2 - 8), "属性区 258px 里塞了 4 行", font=font(13), fill=(200, 40, 40))
    sh.paste(o2, (PAD, ysu))

    out = os.path.join(REF, "面板_苏丹对照诊断.png")
    sh.save(out)
    print("写出", out, sh.size)


build()
