# -*- coding: utf-8 -*-
"""R1 改 v5 —— 按用户四条口述：

  用户原话：**「不需要在属性下放装备描述，名字下不需要人物男，可以更高一点点面板
            关闭应该在边缘框上，装备卡就是实际卡片缩小叠在上方」**

  ① 去掉左栏「装备名 3 行」          → 装备信息改由**卡片本身**承载
  ② 去掉名字下的「人物 · 男」副标     → 名字后直接是金线
  ③ 面板加高                        → 634×432 → **634×490**（立绘拿到 194×342，比 v4 的 193×340 略大）
  ④ 关闭钮挪到**边缘框上**           → 骑在上边框线（ins 8/11/13）上，读作一张「贴在框上的签」
  ⑤ 装备卡 = **真实卡面 `art/card.png` 缩小**，上面照卡面规则排「名字（上）+ 图标（下）」，
     三张**叠**着放在立绘上方（右对齐 x540，相邻压 14px）

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_cardfan.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)
import _panel_redesign as pr      # noqa: E402
import _panel_r1_fan as pf        # noqa: E402   （复用 icon / ellipsize / tbox / SLOTS3 / 状态数据）

from PIL import Image, ImageDraw  # noqa: E402

S, F, Fs, tw, wrap, mix = pr.S, pr.F, pr.Fs, pr.tw, pr.wrap, pr.mix
BODY, BRASS, BRASS_LT, INK_TEXT, SHADOW = (
    pr.BODY, pr.BRASS, pr.BRASS_LT, pr.INK_TEXT, pr.SHADOW)
SUB_TEXT = pr.SUB_TEXT
base_bg, frame, rule, gold_rule = pr.base_bg, pr.frame, pr.rule, pr.gold_rule
portrait_fit, place = pr.portrait_fit, pr.place
overlap_report, draw_debug_rects = pr.overlap_report, pr.draw_debug_rects
NAME, DESC, ATTRS, TAGS = pr.NAME, pr.DESC, pr.ATTRS, pr.TAGS
tier_col = pr.tier_col
icon, ellipsize, tbox = pf.icon, pf.ellipsize, pf.tbox
SLOTS3, STATE_A, STATE_B = pf.SLOTS3, pf.STATE_A, pf.STATE_B

# ============ 几何（全部 1x px）============
W, H = 634, 490            # ← ③ 面板加高（原 432）
DIV_X = 300                # 竖分割线
PX0, PY0, PX1, PY1 = 300, 120, 616, 462      # 立绘框（342 高）
ATTR_Y0, ATTR_DY = 140, 44  # 属性 4 行的首行 y 与行距（44 摊平「属性 → 描述」的空档）
BAND_Y0 = 6                # 装备带顶
CW, CH, STEP = 60, 106, 46  # ← ⑤ 真实卡面 60×106（0.566 = 卡面比例 360:636）；步长 46 = 相邻压 14px
FAN_X1 = 540               # 右对齐（关闭签左缘 551 再留 11px）
CLOSE_CX, CLOSE_CY, CLOSE_W, CLOSE_H = 578, 13.5, 54, 25   # ← ④ 骑在上边框线上

CARD_TEX = os.path.join(R, "art", "card.png")
_cf = {}


def card_face(w, h, faded=False):
    """card.png 缩到 w×h（1x）。faded=True → 往面板底色淡出，读作「一张空卡」。"""
    key = (w, h)
    if key not in _cf:
        _cf[key] = Image.open(CARD_TEX).convert("RGBA").resize((S(w), S(h)), Image.LANCZOS)
    face = _cf[key]
    if not faded:
        return face.convert("RGB")
    flat = Image.new("RGB", face.size, BODY)
    return Image.blend(face.convert("RGB"), flat, 0.66)


def draw_card_name(d, x, y, w, text, f, col):
    """卡面名字区：固定在 y..y+30，1–2 行居中（与 card_chip 的「名字在上」同规矩）。

    ⚠️ 顺序必须是「**先折行、再截断**」。反了的话 —— 先 ellipsize 会把「多功能军刀」
       直接砍成「多功能…」递进来，于是永远只显示 1 行半截名，名字区等于白写。
    5 字名 10px = 50px、卡内可用宽 52px → 一行放得下；7 字名折成 5+2 两行，也是全名。
    """
    maxw = w - 8                                   # ⚠️ 1x 宽（ellipsize 内部自己 S()；wrap 的 maxw 却是 SC 倍）
    lines = wrap(d, text, f, S(maxw))
    if len(lines) > 2:
        lines = lines[:2]
        lines[-1] = ellipsize(d, lines[-1] + "…", f, maxw)
    lines = [ellipsize(d, ln, f, maxw) for ln in lines]
    lh, n = 15, len(lines)
    sy = y + (30 - n * lh) / 2.0
    for i, ln in enumerate(lines):
        d.text((S(x + w / 2.0) - tw(d, ln, f) / 2.0, S(sy + i * lh)), ln, font=f, fill=col)


def equip_card(im, d, x, y, w, h, item, cn):
    """⑤ 一张**真实卡面缩小**的装备卡：card.png 打底 + 名字（上）+ 图标（下）。
    item=None → 淡出的空卡 + 名字区写类型名 + 图标区一枚淡菱形。"""
    filled = item is not None
    # 落影：让「叠着一摞卡」读得出来
    if filled:
        sh = Image.new("RGBA", (S(w), S(h)), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle([0, 0, S(w) - 1, S(h) - 1], radius=S(4), fill=(92, 74, 52, 74))
        im.paste(sh.convert("RGB"), (S(x) + S(1.7), S(y) + S(2.6)), sh.split()[-1])
    im.paste(card_face(w, h, faded=not filled), (S(x), S(y)))

    f_nm = F(10)
    draw_card_name(d, x, y + 5, w, item if filled else cn, f_nm,
                   INK_TEXT if filled else mix(BODY, SHADOW, 0.85))

    iy0, iy1 = y + 38, y + h - 6
    ccy = (iy0 + iy1) / 2.0
    if filled:
        ic = icon(item, w - 12, (iy1 - iy0) - 2)
        if ic is not None:
            im.paste(ic.convert("RGB"),
                     (S(x + w / 2.0) - ic.width // 2, S(ccy) - ic.height // 2),
                     ic.split()[-1])
        else:
            f0 = F(20, True)
            d.text((S(x + w / 2.0) - tw(d, item[0], f0) / 2.0, S(ccy) - 14),
                   item[0], font=f0, fill=mix(BODY, INK_TEXT, 0.55))
    else:
        pf.diamond(d, x + w / 2.0, ccy, 9.0, outline=mix(BODY, SHADOW, 0.45), ow=1.0)


def close_tab(d, cx, cy, w, h):
    """④ 骑在边缘框上的关闭签：实底（颜色 = 面板底色提亮）+ 铜边，压住上边框线。"""
    x0, y0, x1, y1 = cx - w / 2.0, cy - h / 2.0, cx + w / 2.0, cy + h / 2.0
    d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(6),
                        fill=mix(BODY, BRASS_LT, 0.34), outline=BRASS, width=max(1, int(1.4 * pr.SC)))
    d.rounded_rectangle([S(x0 + 2), S(y0 + 2), S(x1 - 2), S(y1 - 2)], radius=S(5),
                        outline=mix(BODY, BRASS, 0.42), width=max(1, int(0.8 * pr.SC)))
    f = F(13)
    d.text((S(cx) - tw(d, "关闭", f) / 2.0, S(cy) - 9), "关闭", font=f, fill=INK_TEXT)


def r1_cardfan(state):
    im = base_bg(W, H)
    frame(im, W, H, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    f_name, f_val, f_attr, f_body = F(27, True), F(17, True), F(13), F(13)

    # ---- 左栏：名字（② 名字下直接是金线，没有「人物 · 男」）----
    d.text((S(40), S(40)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 40, NAME, f_name)
    gold_rule(d, 40, 288, 110)

    # ---- 属性：4 行竖排，属性名 + 数值同一行（v4 已定）----
    # 行距 38 → 44：面板加高后 38 会在「体魄」与描述之间留出 ~64px 空档，44 把空档摊平
    for i, (k, v) in enumerate(ATTRS):
        ry = ATTR_Y0 + i * ATTR_DY
        d.text((S(40), S(ry + 4)), k, font=f_attr, fill=SUB_TEXT)
        d.text((S(76), S(ry + 1)), str(v), font=f_val, fill=tier_col(v))
        rgt = max(tbox(d, 40, ry + 4, k, f_attr)[2], tbox(d, 76, ry + 1, str(v), f_val)[2])
        B["attr_%d" % i] = (40, ry, rgt, ry + 38)

    # ---- ① 属性下**不再**放装备名：装备信息由卡片承载 ----
    rule(d, 40, 340, 286, 340, a=0.35)
    yy = 356
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(252)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 20
    B["desc"] = (40, 356, dmax, yy)

    # ---- 标签：仍贴最下方 ----
    rule(d, 40, 416, 286, 416, a=0.3)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(428), S(tx + bw), S(454)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(432)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 428, tx, 454)

    # ---- 竖分割线 ----
    rule(d, DIV_X, 30, DIV_X, 462, a=0.5)

    # ---- 立绘：框 x300..616 / y120..462 → 194×342，在框内居中 ----
    pt = portrait_fit(PX1 - PX0, PY1 - PY0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = PX0 + (PX1 - PX0 - pw) // 2, PY1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    # ---- ⑤ 装备：三张真实卡面缩小的卡，叠在立绘上方 ----
    n = len(SLOTS3)
    x0 = FAN_X1 - (CW + (n - 1) * STEP)
    for i, (cls, cn) in enumerate(SLOTS3):
        equip_card(im, d, x0 + i * STEP, BAND_Y0, CW, CH, state.get(cls), cn)
    B["equip_fan"] = (x0, BAND_Y0, FAN_X1, BAND_Y0 + CH)

    # ---- ④ 关闭签骑在上边框线上 ----
    close_tab(d, CLOSE_CX, CLOSE_CY, CLOSE_W, CLOSE_H)
    B["close"] = (CLOSE_CX - CLOSE_W / 2.0, CLOSE_CY - CLOSE_H / 2.0,
                  CLOSE_CX + CLOSE_W / 2.0, CLOSE_CY + CLOSE_H / 2.0)
    return im, B


def main():
    log, outs = [], []
    for tag, state, cap in (
        ("B", STATE_B, "★ 推荐 · 状态 B（武器/防具/饰品 三张卡全满）· 卡面 = 真实 card.png 缩小，名字在上、图标在下"),
        ("A", STATE_A, "状态 A · 衫斯真实数据（只装饰品）· 武器/防具 是淡出的空卡，名字区写类型名"),
    ):
        im, B = r1_cardfan(state)
        n, rep = overlap_report("R1改v5-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    SW = W + 68
    H1 = 190 + (H + CAP_H + GAP) * 2 + 30
    sh = Image.new("RGB", (SW, H1), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "R1 改 v5 · 面板加高 + 关闭骑边框 + 装备用真实卡面缩小叠在上方（1:1）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 42), "① 去掉左栏「装备名 3 行」—— 装备信息改由卡片本身承载（卡上有名字）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 60), "② 去掉名字下的「人物 · 男」副标 —— 名字下直接是金线",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 78), "③ 面板 634×432 → 634×490（+58）；立绘 193×340 → 194×342（略大一点）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 96), "④ 关闭钮骑在上边框线上：54×25 的签，纵向中心 y13.5 压住 ins 8/11/13 三道线",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 114), "⑤ 装备卡 = 真实卡面 art/card.png 缩到 60×106（卡面比例 0.566）；三张右对齐叠放 x388–540",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 132), "   相邻压 14px（步长 46）；名字 10px 先折行再截断（最多 2 行）→ 长名折成两行，全名不丢",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 150), "※ 卡大小是被「只在立绘上方」这条硬约束定的：带高 106px → 卡宽只能 60px",
           font=f_s, fill=(226, 160, 120))
    d.text((16, 168), "※ 空槽 = 同一张卡面往面板底色淡出 66%（读作「一张空卡」），名字区写类型名",
           font=f_s, fill=(206, 186, 150))
    y = 190
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((W, H), Image.LANCZOS), (34, y + CAP_H))
        y += H + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v5_真实卡面装备_两态.png")
    sh.save(p)
    print("写出", p, sh.size)

    # ---- 区块边界图 ----
    H2 = 118 + (H + 34) * 2 + 20
    sh2 = Image.new("RGB", (SW, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同两态 · 区块边界图（每个彩框 = 一个区块；两两不相交 = 零遮挡）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 4 个属性行 / 描述 / 标签 / 装备扇形组 / 关闭签 / 立绘 = 10 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "扇形组仍只登记整组外框（组内三张卡的叠是设计要求，不算重叠）；组与外部的相交照查",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 80), "关闭签与立绘在 x 上有 4px 交叠，但 y 相距 94px → 不算重叠（断言按矩形相交判）",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 98), "重点：扇形组下缘 y112 vs 立绘上缘 y120 —— 装备不压立绘",
            font=f_s, fill=(150, 200, 150))
    y2 = 118
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((W, H), Image.LANCZOS), (34, y2))
        y2 += H + 34
    p2 = os.path.join(REF, "面板R1改v5_真实卡面装备_两态_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v5_状态%s_1x.png" % tag)
        im.resize((W, H), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 放大：装备卡 + 关闭签（3x）----
    imB = outs[0][2]
    Z = 3
    fan = imB.crop((S(380), S(0), S(548), S(120))).resize((168 * Z, 120 * Z), Image.LANCZOS)
    tab = imB.crop((S(542), S(0), S(616), S(34))).resize((74 * Z, 34 * Z), Image.LANCZOS)
    col = imB.crop((S(30), S(24), S(300), S(322))).resize((270 * 2, 298 * 2), Image.LANCZOS)
    W3 = max(fan.width + tab.width + 34 * 3, col.width + 68)
    H3 = 92 + fan.height + 34 + col.height + 30
    sh3 = Image.new("RGB", (W3, H3), (42, 39, 35))
    d3 = ImageDraw.Draw(sh3)
    d3.text((16, 16), "3x 放大：装备卡（真实卡面缩小）+ 关闭签 + 左栏", font=Fs(17, True), fill=(240, 232, 214))
    d3.text((16, 44), "装备卡 60×106：卡面 art/card.png 打底 + 名字（10px，先折行再截断，最多 2 行）+ 图标（48×60 等比居中）",
            font=f_s, fill=(206, 186, 150))
    d3.text((16, 62), "三张卡右对齐、相邻压 14px（后画的压在前画的上方）；有卡的落影 1.7/2.6px → 读作一摞卡",
            font=f_s, fill=(206, 186, 150))
    sh3.paste(fan, (34, 92))
    sh3.paste(tab, (34 + fan.width + 34, 92))
    y3 = 92 + fan.height + 20
    d3.text((34, y3), "左栏（2x）：名字下没有副标；属性 4 行竖排；属性下没有装备名", font=f_s, fill=(206, 186, 150))
    sh3.paste(col, (34, y3 + 20))
    p3 = os.path.join(REF, "面板R1改v5_装备卡_放大3x.png")
    sh3.save(p3)
    print("写出", p3, sh3.size)

    # ---- 与 v4 对照 ----
    prev = os.path.join(REF, "面板R1改v4_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        PV_H = 432                              # v4 的面板高（= _panel_redesign.PH）；⚠️ 别硬编码 440，会切掉 v5 底部 2px
        H5 = 168 + (PV_H + CAP_H + 34) + (H + CAP_H + 34) + 26
        sh5 = Image.new("RGB", (SW, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "v4 → v5（同一份数据：三槽全满）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "v4：面板 634×432；左栏有「人物 · 男」副标与 3 行装备名；关闭在面板内部；装备是自绘方卡+类型字",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "v5：面板 634×490；副标与装备名全删；关闭骑在边缘框上；装备改用真实卡面缩小（卡上有名字）",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 80), "立绘 193×340 → 194×342（面板加高换来的）；扇形位置与「不压立绘」约束两版都成立",
                font=f_s, fill=(150, 200, 150))
        d5.text((16, 98), "v4 断言 12 块 0 对；v5 断言 10 块 0 对（区块变少是因为左栏删了两块 + 关闭签单列）",
                font=f_s, fill=(150, 172, 138))
        y5 = 168
        d5.text((34, y5), "v4（面板 432 高）", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += PV_H + CAP_H + 34
        d5.text((34, y5), "v5（面板 490 高）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[0][2].resize((W, H), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v5_与v4对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_cardfan.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
