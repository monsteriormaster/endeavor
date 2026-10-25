# -*- coding: utf-8 -*-
"""人物面板「重设计」三方案 —— 硬约束：任何两个元素不许重叠（程序化断言，不是口头保证）。

用户上一轮反馈：「不好看重新设计，要避免遮挡」。
上一版的两个问题（自省，不是用户明说）：
  1) 布局是「三栏平均分 + 一堆小字平铺」，没有视觉重心，读起来像资料表/名片，不像角色卡；
  2) 立绘被塞在中栏当一条窄带（143×252），存在感几乎没有；
  3) 底面用了旧纸纹 `paper_tile`（自带污斑），在 1x 下读作「脏」。
本轮的三个方向：
  R1 右像左文  —— 立绘贴右下满高、竖铜线切分，最稳
  R2 象上居中文下 —— 立绘装进「肖像框」（内凹 + 四角角标），下方横排信息带
  R3 立绘满幅 + 底栏信息板 —— 立绘出血铺满，底部一条**不透明**信息板；板是实底，所以永不遮挡

只读素材 + 输出图，不碰任何游戏文件。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_redesign.py
"""
import os
from PIL import Image, ImageDraw, ImageChops, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
UI = os.path.join(R, "art", "ui")
OUT = os.path.join(R, "art", "ui", "_draft", "_ref")

PW, PH = 634, 432
SC = 2
S = lambda v: int(round(v * SC))

# ---- 配色：与卡面 B2 同源，但面板底改「干净骨面」（不再用带污斑的旧纸纹） ----
BODY = (231, 222, 202)        # 与卡面 B2 同一骨色
BODY_HI = (240, 233, 217)     # 面板上部提亮
BODY_LO = (219, 208, 186)     # 面板下部压暗
BRASS = (170, 140, 70)
BRASS2 = (206, 176, 104)
BRASS_LT = (222, 199, 140)
INK = (104, 74, 44)
INK_TEXT = (46, 33, 23)
SUB_TEXT = (122, 100, 72)
PLATE = (223, 212, 190)       # 信息板实底（比面板底略亮，读作"贴上去的一块"）
SHADOW = (128, 112, 84)

FONT_REG = "C:/Windows/Fonts/msyh.ttc"
FONT_BD = "C:/Windows/Fonts/msyhbd.ttc"
_fc = {}


def F(size, bold=False):
    k = (size, bold)
    if k not in _fc:
        _fc[k] = ImageFont.truetype(FONT_BD if bold else FONT_REG, int(size * SC))
    return _fc[k]


def Fs(size, bold=False):
    """1x 字号（拼板用）。F() 是 SC 倍的渲染字号，拼板是 1x，**不能混用**——
    否则表头/说明会大两倍并互相压住（已踩）。"""
    k = (size, bold, "sheet")
    if k not in _fc:
        _fc[k] = ImageFont.truetype(FONT_BD if bold else FONT_REG, int(size))
    return _fc[k]


def tw(d, s, f):
    return d.textlength(s, font=f)


def wrap(d, s, f, maxw):
    lines, cur = [], ""
    for ch in s:
        if ch == "\n":
            lines.append(cur)
            cur = ""
            continue
        if d.textlength(cur + ch, font=f) > maxw and cur:
            lines.append(cur)
            cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines


def mix(c1, c2, a):
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * a)) for i in range(3))


# ============================================================
#  底 / 框
# ============================================================
def base_bg(w, h, clean=True):
    """干净骨面 + 极轻纵向渐变（避免平板）。"""
    im = Image.new("RGB", (S(w), S(h)), BODY)
    d = ImageDraw.Draw(im)
    for y in range(S(h)):
        t = y / float(S(h) - 1)
        # 上亮下暗，幅度很小（±9），只做"有光"的暗示
        c = mix(BODY_HI, BODY_LO, t) if clean else BODY
        if y % 2 == 0:
            d.line([(0, y), (S(w), y)], fill=c)
    return im


def frame(im, w, h, crest=True):
    """卡面 B2 的描边配方（放大到面板）+ 内阴影 + 可选顶中徽记。"""
    d = ImageDraw.Draw(im)
    for ins, col, wd in ((8.0, BRASS, 2.4), (11.0, BRASS, 1.2), (13.0, INK, 1.0)):
        d.rectangle([S(ins), S(ins), S(w) - 1 - S(ins), S(h) - 1 - S(ins)],
                    outline=col, width=max(1, S(wd)))
    d.rectangle([S(19.0), S(19.0), S(w) - 1 - S(19.0), S(h) - 1 - S(19.0)],
                outline=(150, 122, 60), width=max(1, S(0.9)))
    # 内阴影：贴着内缘线往内几圈，越往里越淡 → 面板读作"凹进去的纸"
    K = 7
    for k in range(K):
        a = 0.20 * ((1 - k / float(K)) ** 2.2)
        col = mix(BODY, SHADOW, a)
        ins = 20.5 + k
        d.rectangle([S(ins), S(ins), S(w) - 1 - S(ins), S(h) - 1 - S(ins)],
                    outline=col, width=max(1, S(1.0)))
    if crest:
        cx, cy, r = w / 2.0, 14.0, 7.0
        d.polygon([(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))], fill=BRASS2)
        d.polygon([(S(cx), S(cy - r * 0.45)), (S(cx + r * 0.45), S(cy)),
                   (S(cx), S(cy + r * 0.45)), (S(cx - r * 0.45), S(cy))], fill=BODY)
        for ax in (1, -1):
            a, b = sorted((cx + ax * 11, cx + ax * 34))
            d.rectangle([S(a), S(cy - 1.1), S(b), S(cy + 1.1)], fill=BRASS)


def rule(d, x0, y0, x1, y1, col=BRASS, a=0.55, th=1.0, diamond=False):
    """细铜分割线；diamond=True 时中点加一枚小菱形（避免"表格感"）。"""
    c = mix(BODY, col, a)
    d.rectangle([S(min(x0, x1)), S(min(y0, y1)), S(max(x0, x1)), S(max(y0, y1)) + max(1, S(th)) - 1], fill=c)
    if diamond:
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        r = 2.2
        d.polygon([(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))], fill=BRASS2)


def gold_rule(d, x0, x1, y, col=BRASS2, th=1.4, diamond=True):
    """金色细线 + 两端菱形（标题下的分隔，比纯直线"贵"）。"""
    d.rectangle([S(x0), S(y), S(x1), S(y + th)], fill=col)
    r = 2.6
    for cx in (x0, x1):
        d.polygon([(S(cx), S(y - r)), (S(cx + r), S(y)), (S(cx), S(y + r)), (S(cx - r), S(y))], fill=col)


# ============================================================
#  立绘
# ============================================================
PORTRAIT = os.path.join(R, "art", "sansi.png")


def portrait_fit(box_w, box_h, fade=None):
    """按 box 等比缩放立绘；fade = (方向, 像素) 做边缘渐隐，让立绘融入纸面。"""
    pt = Image.open(PORTRAIT).convert("RGBA")
    r = min(box_w / float(pt.width), box_h / float(pt.height))
    nw, nh = max(1, int(round(pt.width * r))), max(1, int(round(pt.height * r)))
    pt = pt.resize((S(nw), S(nh)), Image.LANCZOS)
    if fade:
        axis, px = fade
        mask = Image.new("L", pt.size, 255)
        dm = ImageDraw.Draw(mask)
        n = S(px)
        for i in range(n):
            v = int(255 * (i / float(max(1, n - 1))))
            if axis == "bottom":
                dm.line([(0, pt.height - n + i), (pt.width, pt.height - n + i)], fill=v)
            elif axis == "left":
                dm.line([(i, 0), (i, pt.height)], fill=v)
            elif axis == "top":
                dm.line([(0, i), (pt.width, i)], fill=v)
        pt.putalpha(ImageChops.multiply(pt.split()[-1], mask))
    return pt


def place(im, pt, x, y, shadow=True):
    if shadow:
        # 极淡落影：把立绘的 alpha 平移到右下渲染一层
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
        a = pt.split()[-1].point(lambda v: int(v * 0.22))
        sh.paste((0, 0, 0, 255), (x + S(4), y + S(5)), a)
        im.alpha_composite(sh) if im.mode == "RGBA" else im.paste(
            Image.alpha_composite(im.convert("RGBA"), sh).convert("RGB"), (0, 0))
    if im.mode == "RGBA":
        im.alpha_composite(pt, (x, y))
    else:
        im.paste(pt.convert("RGB"), (x, y), pt.split()[-1])


# ============================================================
#  真实内容（characters.json「衫斯」）
# ============================================================
NAME = "衫斯"
SUB = "人物 · 男"
DESC = "海在呼唤他的孩子，可是他必须继续前进。"
ATTRS = [("智力", 8), ("魅力", 5), ("力量", 3), ("体魄", 4)]
TAGS = ["学习"]
EQUIP = ["章鱼尾人身塑像"]


def tier_col(v):
    if v >= 7:
        return BRASS
    if v >= 4:
        return INK
    return (150, 134, 112)


# ============================================================
#  区块 + 重叠断言
# ============================================================
def meter(d, x, y, w, v, col, h=5.0):
    """属性刻度条：10 = 人类极限（项目标度）。细、低对比底槽 + 铜色填充，不做成"光面游戏血条"。"""
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=S(h / 2.0),
                        fill=mix(BODY, SHADOW, 0.16))
    fw = w * max(0.0, min(1.0, v / 10.0))
    if fw >= 1.0:
        d.rounded_rectangle([S(x), S(y), S(x + fw), S(y + h)], radius=S(h / 2.0), fill=col)
    # 中位刻度（5 = 正常人）：一根很淡的竖线，给"标度感"
    mx = x + w * 0.5
    d.rectangle([S(mx), S(y - 1), S(mx), S(y + h + 1)], fill=mix(BODY, INK, 0.28))


def glow_band(d, w, y0, y1, half=180, color=(250, 244, 228), strength=0.55):
    """立绘背后的柔和竖向光带：让居中的立绘不显孤立（不是发光特效，只是一层纸面提亮）。"""
    cx = w / 2.0
    for x in range(int(cx - half), int(cx + half) + 1):
        t = 1.0 - abs(x - cx) / float(half)
        d.line([(S(x), S(y0)), (S(x), S(y1))], fill=mix(BODY, color, strength * (t ** 1.6)))


def overlap_report(name, blocks, containers=()):
    """两两检查区块矩形；返回 (重叠对数, 文本报告)。零重叠是硬约束。

    `containers` = 容器型区块（如 R3 的信息板）—— 它**本就是要托住**内容的，
    所以不参与「内容 × 内容」的两两检查；但**必须**单独验它没压住立绘。
    """
    cont = set(containers)
    keys = [k for k in blocks if k not in cont]
    bad = []

    def pair(a, b, ka, kb, allow_touch=True):
        ox = min(a[2], b[2]) - max(a[0], b[0])
        oy = min(a[3], b[3]) - max(a[1], b[1])
        if ox > 0 and oy > 0:
            bad.append((ka, kb, ox, oy))

    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            pair(blocks[keys[i]], blocks[keys[j]], keys[i], keys[j])
    # 容器 × 立绘：容器不许覆盖立绘
    for c in cont:
        if "portrait" in blocks:
            pair(blocks[c], blocks["portrait"], c, "portrait")

    lines = ["[%s] 内容区块 %d 个 + 容器 %d 个，重叠 %d 对"
             % (name, len(keys), len(cont), len(bad))]
    for x, y, ox, oy in bad:
        lines.append("   ⚠ %s × %s = %d × %d px" % (x, y, ox, oy))
    if not bad:
        lines.append("   ✅ 零重叠")
    return len(bad), "\n".join(lines)


# ============================================================
#  R1 —— 右像左文
# ============================================================
def r1():
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    # 立绘：贴右下，满高；顶到 y=64 是为了给右上角「关闭」让位，且不压内框线（内缘线在 y=19）
    px0, py0, px1, py1 = 392, 64, 616, 404
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // SC, pt.height // SC
    ax = px1 - pw
    ay = py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    # 竖分割线（在立绘左侧之外 → 不压立绘）
    rule(d, 372, 34, 372, 400, a=0.5)

    f_name, f_sub, f_lab, f_val, f_body = F(27, True), F(12), F(12, True), F(19, True), F(13)

    # 名字 + 副标
    d.text((S(40), S(34)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = (40, 34, 40 + int(tw(d, NAME, f_name) / SC) + 1, 34 + 40)
    d.text((S(42), S(78)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = (42, 78, 42 + int(tw(d, SUB, f_sub) / SC) + 1, 78 + 18)
    gold_rule(d, 40, 300, 104)

    # 属性：一行四格（名小值大），格宽 76
    d.text((S(40), S(120)), "属 性", font=f_lab, fill=INK)
    B["attr_label"] = (40, 120, 92, 136)
    for i, (k, v) in enumerate(ATTRS):
        gx = 40 + i * 82
        d.text((S(gx), S(146)), k, font=f_sub, fill=SUB_TEXT)
        d.text((S(gx), S(162)), str(v), font=f_val, fill=tier_col(v))
        meter(d, gx, 190, 66, v, tier_col(v))
        B["attr_%d" % i] = (gx, 146, gx + 74, 197)

    # 标签
    d.text((S(40), S(206)), "标 签", font=f_lab, fill=INK)
    B["tag_label"] = (40, 206, 92, 222)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / SC) + 20
        d.rounded_rectangle([S(tx), S(226), S(tx + bw), S(252)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * SC)), fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(230)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 226, tx, 252)

    # 装备
    d.text((S(40), S(272)), "装 备", font=f_lab, fill=INK)
    B["eq_label"] = (40, 272, 92, 288)
    d.text((S(40), S(292)), "· " + EQUIP[0], font=f_body, fill=INK_TEXT)
    B["equip"] = (40, 292, 40 + int(tw(d, EQUIP[0], f_body) / SC) + 14, 310)

    # 描述（信息区底部）
    rule(d, 40, 328, 356, 328, a=0.35)
    yy = 338
    for ln in wrap(d, DESC, f_body, S(320)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        yy += 20
    B["desc"] = (40, 338, 360, yy)

    close_btn(d, 556, 20, 602, 50)
    B["close"] = (556, 20, 602, 50)
    return im, B


# ============================================================
#  R2 —— 象上居中文下（肖像框）
# ============================================================
def r2():
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=True)
    d = ImageDraw.Draw(im)
    B = {}

    # 肖像框：居中
    bx0, by0, bx1, by1 = 209, 40, 425, 268
    d.rectangle([S(bx0), S(by0), S(bx1), S(by1)], outline=BRASS, width=max(1, S(1.6)))
    d.rectangle([S(bx0 + 3), S(by0 + 3), S(bx1 - 3), S(by1 - 3)], outline=INK, width=max(1, S(0.8)))
    for cx, cy in ((bx0, by0), (bx1, by0), (bx0, by1), (bx1, by1)):
        r = 5.0
        d.polygon([(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))], fill=BRASS2)
    pt = portrait_fit(bx1 - bx0 - 12, by1 - by0 - 12)
    place(im, pt, S(bx0 + 6 + ((bx1 - bx0 - 12) - pt.width // SC) // 2),
          S(by1 - 6 - pt.height // SC))
    B["portrait_frame"] = (bx0, by0, bx1, by1)

    f_name, f_sub, f_lab, f_val, f_body = F(25, True), F(12), F(12, True), F(18, True), F(13)

    # 名字在肖像框上方还是下方？—— 放肖像框上方会挤，放下方做"署名"
    # 名字：居中于肖像框（之前左对齐于框左缘，读起来是"没对齐"）
    fcx = (bx0 + bx1) / 2.0
    d.text((S(fcx) - tw(d, NAME, f_name) / 2.0, S(276)), NAME, font=f_name, fill=INK_TEXT)
    nw = int(tw(d, NAME, f_name) / SC)
    B["name"] = (int(fcx - nw / 2.0), 276, int(fcx + nw / 2.0) + 1, 276 + 38)
    d.text((S(fcx) - tw(d, SUB, f_sub) / 2.0, S(316)), SUB, font=f_sub, fill=BRASS)
    sw = int(tw(d, SUB, f_sub) / SC)
    B["sub"] = (int(fcx - sw / 2.0), 316, int(fcx + sw / 2.0) + 1, 316 + 18)

    # 左栏：属性（4 行）
    d.text((S(46), S(48)), "属 性", font=f_lab, fill=INK)
    B["attr_label"] = (46, 48, 98, 64)
    for i, (k, v) in enumerate(ATTRS):
        yy = 74 + i * 40
        d.text((S(46), S(yy + 6)), k, font=f_body, fill=SUB_TEXT)
        d.text((S(160) - tw(d, str(v), f_val) / SC, S(yy)), str(v), font=f_val, fill=tier_col(v))
        meter(d, 46, yy + 25, 114, v, tier_col(v))
        B["attr_%d" % i] = (46, yy, 162, yy + 31)

    # 右栏：标签 + 装备
    d.text((S(470), S(48)), "标 签", font=f_lab, fill=INK)
    B["tag_label"] = (470, 48, 522, 64)
    yy = 74
    for s in TAGS:
        bw = int(tw(d, s, f_body) / SC) + 20
        d.rounded_rectangle([S(470), S(yy), S(470 + bw), S(yy + 26)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * SC)), fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(470 + 10), S(yy + 4)), s, font=f_body, fill=INK_TEXT)
        yy += 34
    B["tags"] = (470, 74, 470 + 120, yy)
    d.text((S(470), S(yy + 12)), "装 备", font=f_lab, fill=INK)
    B["eq_label"] = (470, yy + 12, 522, yy + 28)
    d.text((S(470), S(yy + 36)), "· " + EQUIP[0], font=f_body, fill=INK_TEXT)
    B["equip"] = (470, yy + 36, 470 + int(tw(d, EQUIP[0], f_body) / SC) + 14, yy + 54)

    # 底部：描述（横跨，在肖像框下方之外）；宽度用实测行宽，别用「w - 104」拍脑袋
    rule(d, 46, 356, w - 46, 356, a=0.4, diamond=True)
    yy = 368
    dlines = wrap(d, DESC, f_body, S(w - 46 - 46 - 96))
    for ln in dlines:
        d.text((S(46), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        yy += 20
    wmax = max(int(tw(d, ln, f_body) / SC) for ln in dlines)
    B["desc"] = (46, 368, 46 + wmax + 2, yy)

    close_btn(d, w - 108, PH - 62, w - 52, PH - 30)
    B["close"] = (w - 108, PH - 62, w - 52, PH - 30)
    return im, B


# ============================================================
#  R3 —— 立绘满幅 + 底部实底信息板
# ============================================================
def r3():
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=True)
    d = ImageDraw.Draw(im)
    B = {}

    # 立绘：居中、尽量放大（顶到 y=14），底部渐隐融入信息板；先铺一层柔和背衬光带
    plate_y = 292
    px0, px1 = 26, w - 26
    glow_band(d, w, 18, plate_y - 4)
    pt = portrait_fit(px1 - px0, plate_y - 14, fade=("bottom", 48))
    ax = (px0 + px1) // 2 - pt.width // SC // 2
    place(im, pt, S(ax), S(14), shadow=False)
    B["portrait"] = (ax, 14, ax + pt.width // SC, 14 + pt.height // SC)

    f_name, f_sub, f_lab, f_val, f_body = F(26, True), F(12), F(12, True), F(18, True), F(13)

    # 名字：压在立绘**上方留白区**（y 14 处的框内空白），不与立绘重叠
    d.text((S(46), S(40)), NAME, font=f_name, fill=INK_TEXT, stroke_width=S(2), stroke_fill=mix(BODY, BRASS_LT, 0.5))
    B["name"] = (46, 40, 46 + int(tw(d, NAME, f_name) / SC), 40 + 38)
    d.text((S(48), S(82)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = (48, 82, 48 + int(tw(d, SUB, f_sub) / SC) + 1, 82 + 18)

    # 底部实底信息板（不透明 → 永不遮挡）
    d.rectangle([S(26), S(plate_y), S(w - 26), S(h - 26)], fill=PLATE)
    d.rectangle([S(26), S(plate_y), S(w - 26), S(plate_y + 1.6)], fill=BRASS)
    d.rectangle([S(26), S(plate_y + 1.6), S(w - 26), S(plate_y + 2.8)], fill=mix(PLATE, INK, 0.35))
    # 板的内阴影（下缘压暗）
    for k in range(4):
        a = 0.10 * (1 - k / 4.0)
        d.rectangle([S(26 + k), S(h - 26 - 1 - k), S(w - 26 - k), S(h - 26 - k)],
                    outline=mix(PLATE, SHADOW, 0), fill=mix(PLATE, SHADOW, a))
    B["plate"] = (26, plate_y, w - 26, h - 26)

    y0 = plate_y + 14
    # 左：属性四行两列
    d.text((S(46), S(y0)), "属 性", font=f_lab, fill=INK)
    B["attr_label"] = (46, y0, 98, y0 + 16)
    for i, (k, v) in enumerate(ATTRS):
        col = i % 2
        row = i // 2
        gx = 46 + col * 128
        gy = y0 + 24 + row * 36
        d.text((S(gx), S(gy + 4)), k, font=f_body, fill=SUB_TEXT)
        d.text((S(gx + 96) - tw(d, str(v), f_val) / SC, S(gy - 2)), str(v), font=f_val, fill=tier_col(v))
        meter(d, gx, gy + 22, 100, v, tier_col(v), h=4.5)
        B["attr_%d" % i] = (gx, gy, gx + 116, gy + 29)

    # 中：标签
    d.text((S(314), S(y0)), "标 签", font=f_lab, fill=INK)
    B["tag_label"] = (314, y0, 366, y0 + 16)
    tx = 314
    for s in TAGS:
        bw = int(tw(d, s, f_body) / SC) + 20
        d.rounded_rectangle([S(tx), S(y0 + 24), S(tx + bw), S(y0 + 50)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * SC)), fill=mix(PLATE, BRASS_LT, 0.3))
        d.text((S(tx + 10), S(y0 + 28)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (314, y0 + 24, tx, y0 + 50)

    # 右：描述（窄栏，wrap）
    d.text((S(410), S(y0)), "简 介", font=f_lab, fill=INK)
    B["desc_label"] = (410, y0, 462, y0 + 16)
    yy = y0 + 24
    for ln in wrap(d, DESC, f_body, S(180)):
        d.text((S(410), S(yy)), ln, font=f_body, fill=mix(PLATE, INK_TEXT, 0.8))
        yy += 19
    B["desc"] = (410, y0 + 24, 590, yy)

    close_btn(d, w - 66, PH - 60, w - 36, PH - 30, small=True)
    B["close"] = (w - 66, PH - 60, w - 36, PH - 30)
    return im, B


# ============================================================
#  另外两块面板（同步换到新语言）—— 道具卡详情 / 行动结算
# ============================================================
ITEM = {
    "name": "章鱼尾人身塑像",
    "sub": "道具 · jewelry",
    "rows": [("加成", "魅力 +1"), ("类别", "jewelry"), ("标签", "饰品、故乡")],
    "desc": "潮汐终会落下，海洋的子民终会回到大海。",
    # 真实路径来自 resoures/items/equipment.json 的 icon 字段（不猜）
    "icon": os.path.join(R, "art", "items", "章鱼尾人身塑像.png"),
}
RESULT_TITLE = "行动结算"
RESULT_TEXT = ["夜里你把自己关在书房，灯芯烧到最短。",
               "那些数字终于排成了行，你却没有想象中那样轻松。"]


def item_detail():
    w, h = 580, 500
    im = base_bg(w, h)
    frame(im, w, h, crest=True)
    d = ImageDraw.Draw(im)
    B = {}
    f_name, f_sub, f_lab, f_body = F(22, True), F(12), F(12, True), F(14)

    # 标题带
    d.text((S(w / 2.0) - tw(d, ITEM["name"], f_name) / 2.0, S(30)), ITEM["name"], font=f_name, fill=INK_TEXT)
    nw = int(tw(d, ITEM["name"], f_name) / SC)
    B["name"] = (int(w / 2.0 - nw / 2.0), 30, int(w / 2.0 + nw / 2.0) + 1, 30 + 32)
    d.text((S(w / 2.0) - tw(d, ITEM["sub"], f_sub) / 2.0, S(68)), ITEM["sub"], font=f_sub, fill=BRASS)
    sw = int(tw(d, ITEM["sub"], f_sub) / SC)
    B["sub"] = (int(w / 2.0 - sw / 2.0), 68, int(w / 2.0 + sw / 2.0) + 1, 68 + 18)
    gold_rule(d, 40, w - 40, 96)

    # 左：图像区（内凹方框）
    ix0, iy0, ix1, iy1 = 46, 122, 226, 302
    d.rectangle([S(ix0), S(iy0), S(ix1), S(iy1)], fill=mix(BODY, SHADOW, 0.10))
    for k in range(5):
        a = 0.14 * (1 - k / 5.0)
        d.rectangle([S(ix0 + k), S(iy0 + k), S(ix1 - k), S(iy1 - k)], outline=mix(BODY, SHADOW, a))
    d.rectangle([S(ix0), S(iy0), S(ix1), S(iy1)], outline=BRASS, width=max(1, int(1.4 * SC)))
    if os.path.exists(ITEM["icon"]):
        ic = Image.open(ITEM["icon"]).convert("RGBA")
        ic.thumbnail((S(ix1 - ix0 - 30), S(iy1 - iy0 - 30)), Image.LANCZOS)
        im.paste(ic.convert("RGB"),
                 (S((ix0 + ix1) // 2) - ic.width // 2, S((iy0 + iy1) // 2) - ic.height // 2),
                 ic.split()[-1])
    B["icon"] = (ix0, iy0, ix1, iy1)

    # 右：三组「标签 + 值」
    xr = 258
    for i, (lab, val) in enumerate(ITEM["rows"]):
        yy = 122 + i * 62
        d.text((S(xr), S(yy)), lab, font=f_lab, fill=INK)
        B["lab_%d" % i] = (xr, yy, xr + int(tw(d, lab, f_lab) / SC) + 2, yy + 16)
        rule(d, xr, yy + 22, w - 46, yy + 22, a=0.45)
        d.text((S(xr), S(yy + 30)), val, font=f_body, fill=INK_TEXT)
        B["val_%d" % i] = (xr, yy + 30, xr + int(tw(d, val, f_body) / SC) + 2, yy + 52)

    # 描述（底部，横跨）—— 注意左缘要避开图像区下缘（图像区到 y=302）
    rule(d, 46, 336, w - 46, 336, a=0.4, diamond=True)
    dlines = wrap(d, ITEM["desc"], f_body, S(w - 200))
    yy = 350
    for ln in dlines:
        d.text((S(w / 2.0) - tw(d, ln, f_body) / 2.0, S(yy)), ln, font=f_body,
               fill=mix(BODY, INK_TEXT, 0.74))
        yy += 21
    wmax = max(int(tw(d, ln, f_body) / SC) for ln in dlines)
    B["desc"] = (int(w / 2.0 - wmax / 2.0), 350, int(w / 2.0 + wmax / 2.0) + 1, yy)

    close_btn(d, w - 118, h - 60, w - 46, h - 28)
    B["close"] = (w - 118, h - 60, w - 46, h - 28)
    return im, B


def result_panel():
    w, h = 480, 300
    im = base_bg(w, h)
    frame(im, w, h, crest=True)
    d = ImageDraw.Draw(im)
    B = {}
    f_t, f_body = F(19, True), F(14)

    d.text((S(w / 2.0) - tw(d, RESULT_TITLE, f_t) / 2.0, S(28)), RESULT_TITLE, font=f_t, fill=INK_TEXT)
    tw_ = int(tw(d, RESULT_TITLE, f_t) / SC)
    B["title"] = (int(w / 2.0 - tw_ / 2.0), 28, int(w / 2.0 + tw_ / 2.0) + 1, 28 + 28)
    gold_rule(d, 40, w - 40, 76)

    y = 100
    ymax = y
    xmin, xmax = w, 0
    for para in RESULT_TEXT:
        for ln in wrap(d, para, f_body, S(w - 110)):
            d.text((S(w / 2.0) - tw(d, ln, f_body) / 2.0, S(y)), ln, font=f_body, fill=INK_TEXT)
            lw = int(tw(d, ln, f_body) / SC)
            xmin = min(xmin, int(w / 2.0 - lw / 2.0))
            xmax = max(xmax, int(w / 2.0 + lw / 2.0))
            y += 22
        y += 4
        ymax = y
    B["text"] = (xmin, 100, xmax + 1, ymax)

    close_btn(d, w - 112, h - 56, w - 44, h - 24, label="确定")
    B["close"] = (w - 112, h - 56, w - 44, h - 24)
    return im, B


def close_btn(d, x0, y0, x1, y1, small=False, label="关闭"):
    d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(6),
                        outline=BRASS, width=max(1, int(1.2 * SC)), fill=mix(BODY, BRASS_LT, 0.30))
    f = F(13) if small else F(14)
    d.text((S((x0 + x1) / 2.0) - tw(d, label, f) / 2.0, S((y0 + y1) / 2.0) - 10), label, font=f, fill=INK_TEXT)


# ============================================================
#  组装 + 断言 + 出图
# ============================================================
def draw_debug_rects(im, B):
    o = im.copy()
    d = ImageDraw.Draw(o)
    cols = [(220, 60, 60), (60, 160, 220), (60, 190, 120), (230, 160, 40), (190, 90, 210), (30, 200, 200)]
    for i, k in enumerate(B):
        r = B[k]
        d.rectangle([S(r[0]), S(r[1]), S(r[2]), S(r[3])], outline=cols[i % len(cols)], width=2)
    return o


def main():
    log = []
    imgs = []
    specs = (
        ("R1", r1, ()),
        ("R2", r2, ()),
        ("R3", r3, ("plate",)),   # R3 的信息板是容器，不参与"内容 × 内容"检查
    )
    for name, fn, cont in specs:
        im, B = fn()
        n, rep = overlap_report(name, B, cont)
        log.append(rep)
        imgs.append((name, im.resize((PW, PH), Image.LANCZOS)))
        imgs.append((name + "_debug", draw_debug_rects(im, B).resize((PW, PH), Image.LANCZOS)))

    # 对照表：3 个方案竖排（拼板 = 1x，所以文字一律用 Fs）
    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 26
    W = PW + 68
    H = 76 + (PH + CAP_H + GAP) * 3 + 34
    sh = Image.new("RGB", (W, H), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 16), "人物面板 · 重设计三方案（1:1 真实大小）—— 硬约束：零重叠",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 44), "底改干净骨面（弃用带污斑的旧纸纹）｜框与卡面 B2 同源｜立绘不再与任何文字同区｜属性加刻度条（5=常人 / 10=极限）",
           font=f_s, fill=(206, 186, 150))
    y = 78
    caps = {
        "R1": "R1 · 右像左文 —— 立绘贴右下满高，竖铜线切分；最稳，信息密度最高",
        "R2": "R2 · 象上居中文下 —— 立绘装进肖像框（内凹 + 四角角标），属性/标签分左右栏，描述横跨底部",
        "R3": "R3 · 立绘满幅 + 底部实底信息板 —— 立绘出血、底部渐隐；信息板是不透明实底，永不遮挡",
    }
    for name, img in imgs:
        if name.endswith("_debug"):
            continue
        d.text((34, y), caps[name], font=f_t, fill=(226, 210, 180))
        sh.paste(img, (34, y + CAP_H))
        y += PH + CAP_H + GAP
    p = os.path.join(OUT, "面板重设计_三方案.png")
    sh.save(p)
    print("写出", p, sh.size)

    # 第二张：区块框线图（把"零重叠"变成能看见的东西）
    dbg = [x for x in imgs if x[0].endswith("_debug")]
    H2 = 62 + (PH + 34) * len(dbg) + 34
    sh2 = Image.new("RGB", (W, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同上三方案 · 区块边界图（每个彩色框 = 一个内容区块，两两不相交）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 42), "彩色框互不相交 = 零遮挡；R3 的「plate」是容器（托住内容），不计入两两检查，但单独验过它没压立绘",
            font=f_s, fill=(206, 186, 150))
    y2 = 62
    for name, img in dbg:
        sh2.paste(img, (34, y2))
        y2 += PH + 34
    p2 = os.path.join(OUT, "面板重设计_三方案_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    # 第三张：另外两块面板也换到同一套语言
    extra = []
    for nm, fn2, sz in (("道具卡详情", item_detail, (580, 500)),
                        ("行动结算", result_panel, (480, 300))):
        eim, EB = fn2()
        n, rep = overlap_report(nm, EB, ())
        log.append(rep)
        extra.append((nm, eim.resize(sz, Image.LANCZOS)))

    H3 = 76 + sum(im.height + 26 for _, im in extra) + 20
    sh3 = Image.new("RGB", (W, H3), (42, 39, 35))
    d3 = ImageDraw.Draw(sh3)
    d3.text((16, 16), "另两块面板 · 同步换到同一套语言（之前是 Godot 默认灰板）",
            font=Fs(17, True), fill=(240, 232, 214))
    d3.text((16, 44), "布局沿用现有信息结构（不加不减字段），只换皮 + 分区断言；行动结算保持根节点 IGNORE 无遮罩",
            font=f_s, fill=(206, 186, 150))
    y3 = 76
    for nm, eim in extra:
        d3.text((34, y3), nm, font=f_t, fill=(226, 210, 180))
        sh3.paste(eim, (34, y3 + 24))
        y3 += eim.height + 26
    p3 = os.path.join(OUT, "面板重设计_另两块面板.png")
    sh3.save(p3)
    print("写出", p3, sh3.size)

    for name, img in imgs:
        q = os.path.join(OUT, "面板重设计_%s%s.png" % (name, "" if name.endswith("debug") else "_1x"))
        img.save(q)
    print("\n".join(log))
    with open(os.path.join(OUT, "_panel_redesign.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
