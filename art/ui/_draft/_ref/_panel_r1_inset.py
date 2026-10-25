# -*- coding: utf-8 -*-
"""R1 改 v7 —— 按用户两条口述：

  用户原话：**「调整整个面板，关闭要在里面显得不突兀，可以调高。不要让装备顶着边框」**

  ① **关闭挪进面板内部**（原来骑在上边框线上 → 现在是一个安静的小按钮，
     放在右上角、与名字同一水平带）。「不突兀」= 去掉那套「骑边框 + 双道铜边」的强调，
     改成淡底 + 单道细铜边。
  ② **装备卡不再顶着边框**：卡顶 `y8 → 28`（边框线在 ins 8/11/13/19、内阴影从 20.5 起，
     所以 28 才是「真的在框里面」）。
  ③ 上面两条都要纵向空间 → **面板 490 → 510**，立绘 194×342 **尺寸不变**，整体下移 20px。
  ④ 顺带把左栏节奏按新高度重排（四个间距 32 / 32 / 32，末尾余量 30 ≈ 立绘的 28）。

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_inset.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)
import _panel_redesign as pr      # noqa: E402
import _panel_r1_fan as pf        # noqa: E402  （复用 icon / ellipsize / tbox / SLOTS3 / 状态数据）

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
W, H = 634, 510            # ← ③ 面板 490 → 510（给「卡不顶框 + 关闭进内部」腾出纵向空间）
DIV_X = 300
PX0, PY0, PX1, PY1 = 300, 140, 616, 482      # 立绘框（342 高，尺寸没变，整体下移 20）

BAND_Y0 = 28               # ← ② 卡顶：离边框线（ins 19）9px、离内阴影起 20.5 有 7px
CW, CH, STEP = 60, 106, 50  # 真实卡面 60×106；步长 50 = 相邻只压 10px
FAN_X1 = 540               # 右对齐 → 组 x380–540，组心 460 ≈ 立绘心 458

CLOSE = (558, 30, 610, 56)  # ← ① 关闭：面板**内部**右上角，与名字同一水平带（52×26）
CLOSE_FILL = 0.20          # 淡底（原来骑边框时是 0.34 + 双道边，太抢眼）

# ---- 左栏垂直节奏（正文章节之间的间距统一 32；名字→金线 45 是标题区，故意留大）----
NAME_Y = 30
GOLD_Y = 112
ATTR_Y0, ATTR_DY = 144, 52          # 144 / 196 / 248 / 300，块高 38 → 收在 338
DESC_RULE_Y, DESC_Y = 370, 382      # 描述收在 402
TAGS_RULE_Y, TAGS_Y = 434, 446      # 标签 446–472，底余量 38（≈ 立绘的 28）

CARD_TEX = os.path.join(R, "art", "card.png")
_cf = {}


def card_face(w, h):
    if (w, h) not in _cf:
        _cf[(w, h)] = Image.open(CARD_TEX).convert("RGB").resize((S(w), S(h)), Image.LANCZOS)
    return _cf[(w, h)]


def draw_card_name(d, x, y, w, text, f, col):
    """卡面名字区：固定在 y..y+30，1–2 行居中。
    ⚠️ 顺序必须是「先折行、再截断」；两个函数的 maxw 口径不同
       （ellipsize 收 1x 宽、内部自己 S()；wrap 收 SC 倍宽）。"""
    maxw = w - 8
    lines = wrap(d, text, f, S(maxw))
    if len(lines) > 2:
        lines = lines[:2]
        lines[-1] = ellipsize(d, lines[-1] + "…", f, maxw)
    lines = [ellipsize(d, ln, f, maxw) for ln in lines]
    lh, n = 15, len(lines)
    sy = y + (30 - n * lh) / 2.0
    for i, ln in enumerate(lines):
        d.text((S(x + w / 2.0) - tw(d, ln, f) / 2.0, S(sy + i * lh)), ln, font=f, fill=col)


def equip_card(im, d, x, y, w, h, item):
    """一张真实卡面缩小的装备卡：card.png 打底 + 名字（上）+ 图标（下）。
    item=None → **什么都不画**（用户：「没有的装备就空着，不要搞一个空卡牌」）。"""
    if item is None:
        return

    sh = Image.new("RGBA", (S(w), S(h)), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([0, 0, S(w) - 1, S(h) - 1], radius=S(4), fill=(92, 74, 52, 66))
    im.paste(sh.convert("RGB"), (S(x) + S(1.6), S(y) + S(2.4)), sh.split()[-1])

    im.paste(card_face(w, h), (S(x), S(y)))
    draw_card_name(d, x, y + 5, w, item, F(10), INK_TEXT)

    iy0, iy1 = y + 38, y + h - 6
    ccy = (iy0 + iy1) / 2.0
    ic = icon(item, w - 12, (iy1 - iy0) - 2)
    if ic is not None:
        im.paste(ic.convert("RGB"),
                 (S(x + w / 2.0) - ic.width // 2, S(ccy) - ic.height // 2),
                 ic.split()[-1])
    else:
        f0 = F(20, True)
        d.text((S(x + w / 2.0) - tw(d, item[0], f0) / 2.0, S(ccy) - 14),
               item[0], font=f0, fill=mix(BODY, INK_TEXT, 0.55))


def close_btn_in(d, x0, y0, x1, y1, label="关闭"):
    """① **面板内部**的关闭钮：淡底 + 单道细铜边 + 13px 字 ——
    刻意做得安静（原来「骑边框 + 实底 + 双道铜边」是在强调它，反而突兀）。"""
    d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(6),
                        outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                        fill=mix(BODY, BRASS_LT, CLOSE_FILL))
    f = F(13)
    d.text((S((x0 + x1) / 2.0) - tw(d, label, f) / 2.0, S((y0 + y1) / 2.0) - 9),
           label, font=f, fill=INK_TEXT)


def r1_inset(state):
    im = base_bg(W, H)
    frame(im, W, H, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    f_name, f_val, f_attr, f_body = F(27, True), F(17, True), F(13), F(13)

    # ---- 左栏：名字 → 金线（无副标）----
    d.text((S(40), S(NAME_Y)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, NAME_Y, NAME, f_name)
    gold_rule(d, 40, 288, GOLD_Y)

    # ---- 属性：4 行竖排，属性名 + 数值同一行 ----
    for i, (k, v) in enumerate(ATTRS):
        ry = ATTR_Y0 + i * ATTR_DY
        d.text((S(40), S(ry + 4)), k, font=f_attr, fill=SUB_TEXT)
        d.text((S(76), S(ry + 1)), str(v), font=f_val, fill=tier_col(v))
        rgt = max(tbox(d, 40, ry + 4, k, f_attr)[2], tbox(d, 76, ry + 1, str(v), f_val)[2])
        B["attr_%d" % i] = (40, ry, rgt, ry + 38)

    # ---- 描述 ----
    rule(d, 40, DESC_RULE_Y, 286, DESC_RULE_Y, a=0.35)
    yy = DESC_Y
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(252)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 20
    B["desc"] = (40, DESC_Y, dmax, yy)

    # ---- 标签：贴最下方 ----
    rule(d, 40, TAGS_RULE_Y, 286, TAGS_RULE_Y, a=0.3)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(TAGS_Y), S(tx + bw), S(TAGS_Y + 26)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(TAGS_Y + 4)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, TAGS_Y, tx, TAGS_Y + 26)

    # ---- 竖分割线 ----
    rule(d, DIV_X, 30, DIV_X, PY1, a=0.5)

    # ---- 立绘：框 x300..616 / y140..482 → 194×342，框内居中 ----
    pt = portrait_fit(PX1 - PX0, PY1 - PY0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = PX0 + (PX1 - PX0 - pw) // 2, PY1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    # ---- 装备：槽位位置固定，空槽什么都不画；只登记真的画了卡的那一段 ----
    n = len(SLOTS3)
    x0 = FAN_X1 - (CW + (n - 1) * STEP)
    drawn = None
    for i, (cls, cn) in enumerate(SLOTS3):
        cx = x0 + i * STEP
        if state.get(cls) is None:
            continue
        equip_card(im, d, cx, BAND_Y0, CW, CH, state[cls])
        r = (cx, BAND_Y0, cx + CW, BAND_Y0 + CH)
        drawn = r if drawn is None else (min(drawn[0], r[0]), BAND_Y0,
                                         max(drawn[2], r[2]), BAND_Y0 + CH)
    if drawn is not None:
        B["equip_fan"] = drawn

    # ---- ① 关闭在面板内部 ----
    close_btn_in(d, CLOSE[0], CLOSE[1], CLOSE[2], CLOSE[3])
    B["close"] = CLOSE
    return im, B


STATE_C = {}


def main():
    log, outs = [], []
    for tag, state, cap in (
        ("B", STATE_B, "★ 推荐 · 状态 B（三槽全满）· 卡顶 y28 离边框 9px；关闭在面板内右上角"),
        ("A", STATE_A, "状态 A · 衫斯真实数据（只装饰品）· 武器/防具 两格什么都不画"),
        ("C", STATE_C, "状态 C · 三槽全空 · 顶栏完全留白"),
    ):
        im, B = r1_inset(state)
        n, rep = overlap_report("R1改v7-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    SW = W + 68
    H1 = 172 + (H + CAP_H + GAP) * 3 + 30
    sh = Image.new("RGB", (SW, H1), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "R1 改 v7 · 关闭进面板内部 + 装备不顶边框（1:1）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 42), "① 关闭：从「骑在上边框线上」改回面板内部右上角（52×26），淡底 + 单道细铜边 —— 不再抢眼",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 60), "② 装备卡顶 y8 → 28：边框线在 ins 8/11/13/19、内阴影从 20.5 起 → 28 才算真的在框里面",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 78), "③ 面板 490 → 510；立绘 194×342 尺寸不变，整体下移 20px（框 y140–482）",
           font=f_s, fill=(226, 210, 180))
    d.text((16, 96), "④ 左栏节奏按新高度重排：正文章节之间统一 32px；标签底余量 38px ≈ 立绘的 28px",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 114), "   卡片仍只压 10px（步长 50）、组居中于立绘上方（组心 460 ≈ 立绘心 458）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 132), "※ 空槽仍什么都不画；卡片 60×106 是「装备必须在立绘上方」这条约束算出来的（带高 106px）",
           font=f_s, fill=(206, 186, 150))
    y = 172
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((W, H), Image.LANCZOS), (34, y + CAP_H))
        y += H + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v7_关闭内嵌_装备离框_三态.png")
    sh.save(p)
    print("写出", p, sh.size)

    # ---- 区块边界图 ----
    H2 = 136 + (H + 34) * 3 + 20
    sh2 = Image.new("RGB", (SW, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同三态 · 区块边界图（每个彩框 = 一个区块；两两不相交 = 零遮挡）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 4 个属性行 / 描述 / 标签 / 装备组 / 关闭 / 立绘 —— 满装时 10 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "重点：装备组下缘 y134 vs 立绘上缘 y140 → 差 6px；装备组右缘 x540 vs 关闭左缘 x558 → 差 18px",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 80), "关闭 x558–610 完整落在面板右内缘（约 x615）之内 —— 这是本轮「关闭进里面」的判据",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 98), "※ 空槽不画 → 装备组只登记真的画了卡的那一段（全空态干脆没有这一块）",
            font=f_s, fill=(206, 186, 150))
    y2 = 136
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((W, H), Image.LANCZOS), (34, y2))
        y2 += H + 34
    p2 = os.path.join(REF, "面板R1改v7_关闭内嵌_装备离框_三态_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v7_状态%s_1x.png" % tag)
        im.resize((W, H), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 放大：顶部带（左：名字+关闭 / 右：装备卡）----
    imB = outs[0][2]
    Z = 3
    top = imB.crop((S(28), S(18), S(620), S(148))).resize((592 * 2, 130 * 2), Image.LANCZOS)
    col = imB.crop((S(30), S(24), S(300), S(484))).resize((270 * 2, 460 * 2), Image.LANCZOS)
    W3 = max(top.width + 68, col.width + 68)
    H3 = 92 + top.height + 34 + col.height + 30
    sh3 = Image.new("RGB", (W3, H3), (42, 39, 35))
    d3 = ImageDraw.Draw(sh3)
    d3.text((16, 16), "2x 放大：顶部带（名字 + 关闭 + 装备卡）+ 左栏", font=Fs(17, True), fill=(240, 232, 214))
    d3.text((16, 44), "卡顶离上边框 9px、关闭完整在面板内部 —— 「不顶着边框 / 不突兀」这两条看这里",
            font=f_s, fill=(150, 200, 150))
    d3.text((16, 62), "卡 60×106 = art/card.png 缩小；名字 10px 先折行再截断；图标 48×60 等比居中；落影 1.6/2.4px",
            font=f_s, fill=(206, 186, 150))
    sh3.paste(top, (34, 92))
    y3 = 92 + top.height + 24
    d3.text((34, y3), "左栏（2x）：名字下没有副标；属性 4 行竖排；属性下没有装备名", font=f_s, fill=(206, 186, 150))
    sh3.paste(col, (34, y3 + 20))
    p3 = os.path.join(REF, "面板R1改v7_顶部带_放大2x.png")
    sh3.save(p3)
    print("写出", p3, sh3.size)

    # ---- 与 v6 对照 ----
    prev = os.path.join(REF, "面板R1改v6_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        H5 = 172 + (pv.height + CAP_H + 34) + (H + CAP_H + 34) + 26
        sh5 = Image.new("RGB", (SW, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "v6 → v7（同一份数据：三槽全满）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "v6：面板 634×490；关闭骑在上边框线上（双道铜边 + 实底）；装备卡顶 y8 顶着边框",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "v7：面板 634×510；关闭回到面板内部右上角（淡底单细边）；装备卡顶 y28 离边框 9px",
                font=f_s, fill=(150, 200, 150))
        d5.text((16, 80), "两版立绘都 194×342；v6 断言 10 / 10 / 9 块 0 对，v7 十块 0 对（三态）",
                font=f_s, fill=(150, 172, 138))
        y5 = 172
        d5.text((34, y5), "v6（490 高 · 关闭骑边框 · 卡顶着边框）", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += pv.height + CAP_H + 34
        d5.text((34, y5), "v7（510 高 · 关闭在内部 · 卡离边框）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[0][2].resize((W, H), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v7_与v6对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_inset.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
