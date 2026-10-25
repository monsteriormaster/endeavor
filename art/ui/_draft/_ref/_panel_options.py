# -*- coding: utf-8 -*-
"""人物面板「框语言」候选对照：同一块面板、同一套内容、同一套布局，只换框。

目的：把"方向上二选一"变成**能看的真实像素**，避免用文字描述风格。
  A = 沿用现有 art/character_panel_bg.png（金雕花）—— 但按 1:1 比例重排尺寸，消除当前拉伸变形
  B = 细线羊皮纸 —— 与已实装的卡面 B2 / 底栏货架同源（paper_tile 底 + 细铜双线 + 墨压线 + 顶中徽记）

只读素材 + 输出对照图，不碰任何游戏文件。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_options.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

R = r"C:\Users\26464\IdeaProjects\endeavor"
UI = os.path.join(R, "art", "ui")
OUT = os.path.join(R, "art", "ui", "_draft", "_ref")

# ---------- 面板几何（A / B 相同，便于公平比对） ----------
PW, PH = 634, 432          # 634/432 = 1.4676；character_panel_bg 源比 1370/933 = 1.4684 → 1:1 不变形
SC = 2                     # 2x 超采样
S = lambda v: int(round(v * SC))

# ---------- B 语言配色（与 _make_card_b2.py 同一套） ----------
BRASS = (170, 140, 70)
BRASS2 = (206, 176, 104)
INK = (104, 74, 44)
INK_TEXT = (46, 33, 23)
SUB_TEXT = (120, 98, 70)
BODY = (231, 222, 202)

FONT_REG = "C:/Windows/Fonts/msyh.ttc"
FONT_BD = "C:/Windows/Fonts/msyhbd.ttc"
_fc = {}


def F(size, bold=False):
    k = (size, bold)
    if k not in _fc:
        _fc[k] = ImageFont.truetype(FONT_BD if bold else FONT_REG, int(size * SC))
    return _fc[k]


def text_w(d, s, f):
    return d.textlength(s, font=f)


def wrap(d, s, f, maxw):
    """按像素宽度折行（中文逐字、西文按空格）。"""
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


def ctext(d, cx, y, s, f, col):
    d.text((S(cx) - text_w(d, s, f) / 2.0, S(y)), s, font=f, fill=col)


# ============================================================
#  两种框
# ============================================================
def bg_ornate():
    """A：现有金雕花素材，按 1:1 比例铺到 634×432（MATCH 比 → 零变形）。"""
    src = Image.open(os.path.join(R, "art", "character_panel_bg.png")).convert("RGB")
    return src.resize((S(PW), S(PH)), Image.LANCZOS)


def bg_plain():
    """B：paper_tile 无缝平铺（取偏中一块，避开平铺接缝落在边框上）。"""
    return bg_plain_at(PW, PH)


def frame_b2(im, w, h):
    """B：卡面 B2 描边配方按面板尺寸放大 + 顶中菱形徽记。"""
    d = ImageDraw.Draw(im)
    for ins, col, wd in ((8.0, BRASS, 2.4), (11.0, BRASS, 1.2), (13.0, INK, 1.0)):
        d.rectangle([S(ins), S(ins), S(w) - 1 - S(ins), S(h) - 1 - S(ins)],
                    outline=col, width=max(1, S(wd)))
    d.rectangle([S(19.0), S(19.0), S(w) - 1 - S(19.0), S(h) - 1 - S(19.0)],
                outline=(150, 122, 60), width=max(1, S(0.9)))
    # 顶中徽记（菱形 + 两侧短须）
    cx, cy, r = w / 2.0, 14.0, 7.0
    d.polygon([(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))], fill=BRASS2)
    d.polygon([(S(cx), S(cy - r * 0.45)), (S(cx + r * 0.45), S(cy)),
               (S(cx), S(cy + r * 0.45)), (S(cx - r * 0.45), S(cy))], fill=BODY)
    for ax in (1, -1):
        # ax=-1 时 x0 > x1，PIL 要求 x1>=x0 → 排序后再画
        a, b = sorted((cx + ax * 11, cx + ax * 34))
        d.rectangle([S(a), S(cy - 1.1), S(b), S(cy + 1.1)], fill=BRASS)


def hrule(d, x0, x1, y, col=(170, 140, 70), a=140, th=1.0):
    """细铜分割线（带 alpha 感：与纸色混合）。"""
    c = tuple(int(BODY[i] + (col[i] - BODY[i]) * (a / 255.0)) for i in range(3))
    d.rectangle([S(x0), S(y), S(x1), S(y + th)], fill=c)


# ============================================================
#  共同内容（真实数据：characters.json 的「衫斯」）
# ============================================================
NAME = "衫斯"
SUB = "人物 · 男"
DESC = "海在呼唤他的孩子，可是他必须继续前进。"
ATTRS = [("智力", 8), ("魅力", 5), ("力量", 3), ("体魄", 4)]
TAGS = ["学习"]
EQUIP = ["章鱼尾人身塑像"]
PORTRAIT = os.path.join(R, "art", "sansi.png")


def draw_content(im, ornate: bool):
    d = ImageDraw.Draw(im)
    lw = 1.0 * SC          # 文字描边，保证压在纹理/雕花上也读得清
    stroke = (252, 248, 238) if not ornate else (245, 236, 214)

    def t(x, y, s, f, col, anchor_left=True):
        d.text((S(x), S(y)), s, font=f, fill=col, stroke_width=int(lw), stroke_fill=stroke)

    # --- 标题带 ---
    f_name, f_sub, f_body, f_lab = F(24, True), F(12), F(14), F(12, True)
    ctext(d, PW / 2.0, 30, NAME, f_name, INK_TEXT)
    ctext(d, PW / 2.0, 62, SUB, f_sub, SUB_TEXT)
    # 标题带下横线
    if not ornate:
        hrule(d, 30, PW - 30, 84)
    # 描述
    for i, ln in enumerate(wrap(d, DESC, f_body, S(PW - 120))):
        ctext(d, PW / 2.0, 94 + i * 19, ln, f_body, INK_TEXT)

    # --- 三栏 ---
    y0 = 138
    # 左栏：属性
    x = 46
    t(x, y0, "属性", f_lab, INK)
    if not ornate:
        hrule(d, x, x + 120, y0 + 22)
    for i, (k, v) in enumerate(ATTRS):
        yy = y0 + 36 + i * 30
        t(x, yy, k, f_body, INK_TEXT)
        d.text((S(x + 118) - text_w(d, str(v), f_body), S(yy)), str(v),
               font=f_body, fill=INK, stroke_width=int(lw), stroke_fill=stroke)

    # 中栏：立绘（占面板高 ~58%）
    ph = 252
    pt = Image.open(PORTRAIT).convert("RGBA")
    pw = int(pt.width * (ph / float(pt.height)))
    pt = pt.resize((S(pw), S(ph)), Image.LANCZOS)
    px = int((PW - pw) / 2.0)
    im.paste(pt, (S(px), S(y0 - 6)), pt)

    # 右栏：标签 / 装备
    xr = PW - 46 - 150
    t(xr, y0, "标签", f_lab, INK)
    if not ornate:
        hrule(d, xr, xr + 150, y0 + 22)
    for i, s in enumerate(TAGS):
        yy = y0 + 36 + i * 26
        d.rounded_rectangle([S(xr), S(yy - 3), S(xr + 16 + text_w(d, s, f_body) / SC), S(yy + 21)],
                            radius=S(6), outline=BRASS, width=max(1, int(1.0 * SC)), fill=(238, 230, 210))
        t(xr + 8, yy, s, f_body, INK_TEXT)
    ye = y0 + 36 + len(TAGS) * 26 + 18
    t(xr, ye, "装备", f_lab, INK)
    if not ornate:
        hrule(d, xr, xr + 150, ye + 22)
    if EQUIP:
        for i, s in enumerate(EQUIP):
            t(xr, ye + 36 + i * 24, "· " + s, f_body, INK_TEXT)
    else:
        t(xr, ye + 36, "—", f_body, SUB_TEXT)

    # --- 右下关闭 ---
    bx0, by0, bx1, by1 = PW - 116, PH - 52, PW - 34, PH - 20
    d.rounded_rectangle([S(bx0), S(by0), S(bx1), S(by1)], radius=S(6),
                        outline=BRASS, width=max(1, int(1.2 * SC)),
                        fill=(238, 230, 210) if not ornate else (240, 231, 208))
    ctext(d, (bx0 + bx1) / 2.0, by0 + 6, "关闭", f_body, INK_TEXT)


def render(ornate: bool) -> Image.Image:
    im = bg_ornate() if ornate else bg_plain()
    if not ornate:
        frame_b2(im, PW, PH)
    draw_content(im, ornate)
    return im


# ============================================================
#  拼对照表
# ============================================================
def main():
    # 拼板前降到 1x：拼板即玩家实际看到的大小（2x 超采样层只用于渲染时抗锯齿）
    a = render(True).resize((PW, PH), Image.LANCZOS)
    b = render(False).resize((PW, PH), Image.LANCZOS)
    f_t = F(15, True)
    f_s = F(12)
    pad, gap, head = 34, 40, 132
    W = pad * 2 + PW * 2 + gap
    H = head + PH + 88
    sheet = Image.new("RGB", (W, H), (42, 39, 35))
    d = ImageDraw.Draw(sheet)

    d.text((16, 16), "人物面板 · 框语言候选（同尺寸 634×432 / 同内容 / 同布局）",
           font=F(17, True), fill=(240, 232, 214))
    d.text((16, 48), "A = 沿用现有金雕花素材（本图已按 1:1 重排尺寸，消除变形）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 70), "B = 细线羊皮纸（与卡面 B2 / 底栏货架同源：paper_tile + 细铜双线 + 墨压线 + 顶中徽记）",
           font=f_s, fill=(206, 186, 150))

    sheet.paste(a, (pad, head))
    sheet.paste(b, (pad + PW + gap, head))
    d.text((pad + 6, head - 26), "A · 金雕花", font=f_t, fill=(240, 232, 214))
    d.text((pad + PW + gap + 6, head - 26), "B · 细线羊皮纸",
           font=f_t, fill=(240, 232, 214))

    ytxt = head + PH + 20
    d.text((pad, ytxt), "A 代价：素材比 1.4684 → 面板必须改成 634×432 才不变形；雕花繁复，角部吃掉约 90px 可用宽度",
           font=f_s, fill=(190, 172, 140))
    d.text((pad, ytxt + 24), "B 代价：需新出一个「面板框」素材（或程序化 StyleBoxFlat + 角标），四角不再是雕花",
           font=f_s, fill=(190, 172, 140))

    p = os.path.join(OUT, "面板候选_框语言_A金雕花_vs_B细线羊皮纸.png")
    sheet.save(p)
    print("写出", p, sheet.size)
    sheet.save(p)
    for tag, v in (("A", a), ("B", b)):
        q = os.path.join(OUT, "面板候选_%s_1x.png" % tag)
        v.save(q)
        print("  →", os.path.basename(q), (PW, PH))


# ============================================================
#  另外两个面板（B 语言）：道具卡详情 / 行动结算
# ============================================================
ITEM = {
    "name": "章鱼尾人身塑像",
    "sub": "道具 · jewelry",
    "bonus": "魅力 +1",
    "klass": "jewelry",          # card_class（代码里就是 card.card_class，不是中文）
    "tags": "饰品、故乡",
    "desc": "潮汐终会落下，海洋的子民终会回到大海",
    # 真实路径来自 resoures/items/equipment.json 的 icon 字段（不是猜的）
    "icon": os.path.join(R, "art", "items", "章鱼尾人身塑像.png"),
}
RESULT_TITLE = "行动结算"
RESULT_TEXT = ("夜里你把自己关在书房，灯芯烧到最短。\n"
               "那些数字终于排成了行，你却没有想象中那样轻松。")


def _pick_icon():
    """图标路径必须来自数据（equipment.json 的 icon 字段）。
    不要用 glob 兜底猜 —— 会把未去背的原始素材（白底）抓进来，mock 失真。"""
    return ITEM["icon"] if os.path.exists(ITEM["icon"]) else None


def _panel_base(w, h):
    im = bg_plain_at(w, h)
    frame_b2(im, w, h)
    return im


def bg_plain_at(w, h):
    """平铺 paper_tile 后取偏中一块。注意：必须铺到 S(w)+60 / S(h)+60，
    否则裁剪起点 (60,60) 会取到铺贴范围之外 → 右下出现黑块（mock 会失真）。"""
    tile = Image.open(os.path.join(UI, "paper_tile.png")).convert("RGB")
    t = tile.resize((S(300), S(300)), Image.LANCZOS)
    W, H = S(w) + 60, S(h) + 60
    im = Image.new("RGB", (W, H))
    for y in range(0, H, S(300)):
        for x in range(0, W, S(300)):
            im.paste(t, (x, y))
    return im.crop((60, 60, 60 + S(w), 60 + S(h)))


def _btn(d, x, y, w, h, label, f, fill=(238, 230, 210)):
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=S(6),
                        outline=BRASS, width=max(1, int(1.2 * SC)), fill=fill)
    d.text((S(x + w / 2.0) - text_w(d, label, f) / 2.0, S(y + 5)), label, font=f, fill=INK_TEXT)


def render_item() -> Image.Image:
    w, h = 580, 500
    im = _panel_base(w, h)
    d = ImageDraw.Draw(im)
    stroke = (252, 248, 238)
    lw = int(1.0 * SC)
    f_name, f_sub, f_body, f_lab = F(23, True), F(12), F(14), F(12, True)

    def t(x, y, s, f, col=INK_TEXT):
        d.text((S(x), S(y)), s, font=f, fill=col, stroke_width=lw, stroke_fill=stroke)

    ctext(d, w / 2.0, 28, ITEM["name"], f_name, INK_TEXT)
    ctext(d, w / 2.0, 62, ITEM["sub"], f_sub, SUB_TEXT)
    hrule(d, 30, w - 30, 86)

    icon = _pick_icon()
    if icon:
        ic = Image.open(icon).convert("RGBA")
        ic.thumbnail((S(176), S(176)), Image.LANCZOS)
        # 显式用 alpha 通道当 mask：直接把 RGBA 图当 mask 传在某些 Pillow 版本上不生效，
        # 会贴出一个白底方块（mock 失真，游戏里 TextureRect 是尊重 alpha 的，不存在此问题）。
        pos = (S(48) + (S(176) - ic.width) // 2, S(140) + (S(176) - ic.height) // 2)
        im.paste(ic.convert("RGB"), pos, ic.split()[-1])
    d.rectangle([S(48), S(140), S(224), S(316)], outline=(186, 164, 124), width=max(1, int(0.9 * SC)))

    xr = 254
    for i, (lab, val) in enumerate((("加成", ITEM["bonus"]), ("类别", ITEM["klass"]))):
        yy = 108 + i * 74
        t(xr, yy, lab, f_lab, INK)
        hrule(d, xr, w - 46, yy + 22)
        t(xr, yy + 34, val, f_body)
    yy = 108 + 2 * 74
    t(xr, yy, "标签", f_lab, INK)
    hrule(d, xr, w - 46, yy + 22)
    t(xr, yy + 34, ITEM["tags"], f_body)

    hrule(d, 30, w - 30, 336)
    for i, ln in enumerate(wrap(d, ITEM["desc"], f_body, S(w - 140))):
        ctext(d, w / 2.0, 352 + i * 20, ln, f_body, INK_TEXT)

    _btn(d, w - 116, h - 56, 82, 32, "关闭", f_body)
    return im


def render_result() -> Image.Image:
    w, h = 480, 300
    im = _panel_base(w, h)
    d = ImageDraw.Draw(im)
    stroke = (252, 248, 238)
    lw = int(1.0 * SC)
    f_t, f_body = F(19, True), F(14)

    def t(x, y, s, f, col=INK_TEXT):
        d.text((S(x), S(y)), s, font=f, fill=col, stroke_width=lw, stroke_fill=stroke)

    ctext(d, w / 2.0, 24, RESULT_TITLE, f_t, INK_TEXT)
    hrule(d, 30, w - 30, 64)
    y = 84
    for para in RESULT_TEXT.split("\n"):
        for ln in wrap(d, para, f_body, S(w - 90)):
            ctext(d, w / 2.0, y, ln, f_body, INK_TEXT)
            y += 22
    _btn(d, w - 116, h - 56, 82, 32, "确定", f_body)
    return im


def sheet_set_b():
    f_t, f_s = F(15, True), F(12)
    # 一律先降到 1x 再拼：拼板即"玩家实际看到的大小"，也避免 2x 超采样层的边缘瑕疵被当成设计问题。
    a = render(False).resize((PW, PH), Image.LANCZOS)
    b = render_item().resize((580, 500), Image.LANCZOS)
    c = render_result().resize((480, 300), Image.LANCZOS)
    W = max(PW, 580) + 68
    H = 74 + PH + 46 + 500 + 46 + 300 + 40
    sh = Image.new("RGB", (W, H), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 16), "三个面板 · B 细线羊皮纸语言（1:1 真实大小·同真实内容）",
           font=F(17, True), fill=(240, 232, 214))
    d.text((16, 44), "人物面板 634×432（尺寸按素材比重排，消除变形）｜道具卡详情 580×500｜行动结算 480×300（保持 IGNORE 无遮罩）",
           font=f_s, fill=(206, 186, 150))
    y = 74
    for img, tag in ((a, "人物面板 · 634×432"), (b, "道具卡详情 · 580×500"), (c, "行动结算 · 480×300")):
        d.text((34, y), tag, font=f_t, fill=(226, 210, 180))
        sh.paste(img, (34, y + 22))
        y += img.height + 46
    p = os.path.join(OUT, "面板整套_B细线羊皮纸.png")
    sh.save(p)
    print("写出", p, sh.size)
    for img, name in ((a, "人物面板_B"), (b, "道具卡详情_B"), (c, "行动结算_B")):
        q = os.path.join(OUT, "%s_1x.png" % name)
        img.save(q)
        print("  →", os.path.basename(q))


main()
sheet_set_b()
