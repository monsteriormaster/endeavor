# -*- coding: utf-8 -*-
"""R1 改 v6 —— 按用户两条口述：

  用户原话：**「好一点，没有的装备就空着，不要搞一个空卡牌，调整布局使其更美观」**

  ① **空槽什么都不画** —— 不再有「淡出空卡 / 类型名 / 淡菱形」。
     没装备就是没东西；槽位仍然**位置固定**（左→右 = 武器 / 防具 / 饰品），
     所以「缺哪一类」靠**空在哪一格**认，而不是靠一张假卡。
  ② **布局再调**（三处，都是为了「顺眼」）：
     · 卡与卡只压 14px → **10px**（步长 46 → 50）：三张卡基本各自完整可读，不再挤成一坨
     · 卡片组**居中于立绘上方**（`x380–540`，组心 460 ≈ 立绘心 458）—— 左右对称，不是歪在角上
     · 左栏垂直节奏**均分**：名字→金线 26 / 金线→属性 34 / 属性→描述 32 / 描述→标签 34
       （v5 的两段空档是 30 与 40，肉眼能看出不一样大）
  ③ 顺带加一个 **状态 C = 三槽全空** —— 让你确认「全空」的时候顶栏长什么样。

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_empty.py
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
W, H = 634, 490
DIV_X = 300
PX0, PY0, PX1, PY1 = 300, 120, 616, 462      # 立绘框（342 高）
BAND_Y0 = 8                # 装备带顶（比 v5 的 6 再让 2px，离面板上缘有点呼吸）
CW, CH, STEP = 60, 106, 50  # 真实卡面 60×106（卡面比例 0.566）；步长 50 = 相邻只压 10px
FAN_X1 = 540               # 右对齐 → 组 x380–540，组心 460 ≈ 立绘心 458
CLOSE_CX, CLOSE_CY, CLOSE_W, CLOSE_H = 584, 13.5, 54, 25   # 右移 6px：与卡片组（右缘 x540）拉开到 17px

# ---- 左栏垂直节奏（⚠️ 四个间距刻意取接近值：26 / 34 / 32 / 34）----
GOLD_Y = 104               # 名字下金线
ATTR_Y0, ATTR_DY = 138, 46  # 属性 4 行：138 / 184 / 230 / 276，块高 38 → 收在 314
DESC_RULE_Y, DESC_Y = 346, 358
TAGS_RULE_Y, TAGS_Y = 412, 424

CARD_TEX = os.path.join(R, "art", "card.png")
_cf = {}


def card_face(w, h):
    """card.png 缩到 w×h（1x）—— 直接用真卡面，不做任何淡化（空槽已经改成不画了）。"""
    if (w, h) not in _cf:
        _cf[(w, h)] = Image.open(CARD_TEX).convert("RGB").resize((S(w), S(h)), Image.LANCZOS)
    return _cf[(w, h)]


def draw_card_name(d, x, y, w, text, f, col):
    """卡面名字区：固定在 y..y+30，1–2 行居中（与 card_chip 的「名字在上」同规矩）。

    ⚠️ 顺序必须是「先折行、再截断」。反了的话 —— 先 ellipsize 会把「多功能军刀」
       直接砍成「多功能…」递进来，于是永远只显示 1 行半截名，名字区等于白写。
    ⚠️ 两个函数的 maxw **口径不同**：ellipsize 收 1x 宽（内部自己 S()），wrap 收 SC 倍宽。混用会溢出。
    """
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
    """一张**真实卡面缩小**的装备卡：card.png 打底 + 名字（上）+ 图标（下）。

    ⚠️ item=None 时**直接返回，什么都不画** —— 这是本轮用户明确要求的
    「没有的装备就空着，不要搞一个空卡牌」。原来那套「淡出卡面 + 类型名 + 淡菱形」
    读起来像一张「幽灵卡」，比留白更糟。
    """
    if item is None:
        return

    # 落影：让「叠着一摞卡」读得出来（画在下层卡之上）
    sh = Image.new("RGBA", (S(w), S(h)), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([0, 0, S(w) - 1, S(h) - 1], radius=S(4), fill=(92, 74, 52, 74))
    im.paste(sh.convert("RGB"), (S(x) + S(1.7), S(y) + S(2.6)), sh.split()[-1])

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
        f0 = F(20, True)                     # 无 icon 的装备 → 名字首字兜底，不画空白方块
        d.text((S(x + w / 2.0) - tw(d, item[0], f0) / 2.0, S(ccy) - 14),
               item[0], font=f0, fill=mix(BODY, INK_TEXT, 0.55))


def close_tab(d, cx, cy, w, h):
    """骑在边缘框上的关闭签：实底（面板底色提亮）+ 铜边，压住上边框线。"""
    x0, y0, x1, y1 = cx - w / 2.0, cy - h / 2.0, cx + w / 2.0, cy + h / 2.0
    d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(6),
                        fill=mix(BODY, BRASS_LT, 0.34), outline=BRASS, width=max(1, int(1.4 * pr.SC)))
    d.rounded_rectangle([S(x0 + 2), S(y0 + 2), S(x1 - 2), S(y1 - 2)], radius=S(5),
                        outline=mix(BODY, BRASS, 0.42), width=max(1, int(0.8 * pr.SC)))
    f = F(13)
    d.text((S(cx) - tw(d, "关闭", f) / 2.0, S(cy) - 9), "关闭", font=f, fill=INK_TEXT)


def r1_empty(state):
    im = base_bg(W, H)
    frame(im, W, H, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    f_name, f_val, f_attr, f_body = F(27, True), F(17, True), F(13), F(13)

    # ---- 左栏：名字 → 金线（无副标）----
    d.text((S(40), S(40)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 40, NAME, f_name)
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
    rule(d, DIV_X, 30, DIV_X, 462, a=0.5)

    # ---- 立绘：框 x300..616 / y120..462 → 194×342，框内居中 ----
    pt = portrait_fit(PX1 - PX0, PY1 - PY0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = PX0 + (PX1 - PX0 - pw) // 2, PY1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    # ---- 装备：槽位**位置固定**（左→右 = 武器/防具/饰品），空槽**什么都不画** ----
    n = len(SLOTS3)
    x0 = FAN_X1 - (CW + (n - 1) * STEP)          # 组左界（三槽都满时的位置）
    drawn = None
    for i, (cls, cn) in enumerate(SLOTS3):
        cx = x0 + i * STEP
        if state.get(cls) is None:
            continue                              # 空槽 → 不画（用户要求）
        equip_card(im, d, cx, BAND_Y0, CW, CH, state[cls])
        r = (cx, BAND_Y0, cx + CW, BAND_Y0 + CH)
        drawn = r if drawn is None else (min(drawn[0], r[0]), BAND_Y0,
                                         max(drawn[2], r[2]), BAND_Y0 + CH)
    # ⚠️ 只登记**真的画了卡**的那段（空槽不画 → 不能把整组位置都算成占位，
    #    否则断言是在为一个不存在的矩形背书）
    if drawn is not None:
        B["equip_fan"] = drawn

    # ---- 关闭签骑在上边框线上 ----
    close_tab(d, CLOSE_CX, CLOSE_CY, CLOSE_W, CLOSE_H)
    B["close"] = (CLOSE_CX - CLOSE_W / 2.0, CLOSE_CY - CLOSE_H / 2.0,
                  CLOSE_CX + CLOSE_W / 2.0, CLOSE_CY + CLOSE_H / 2.0)
    return im, B


STATE_C = {}                        # 三槽全空


def main():
    log, outs = [], []
    for tag, state, cap in (
        ("B", STATE_B, "★ 推荐 · 状态 B（三槽全满）· 三张真卡面 60×106，只压 10px，组居中于立绘上方"),
        ("A", STATE_A, "状态 A · 衫斯真实数据（只装饰品）· 武器/防具 两格什么都不画，空着"),
        ("C", STATE_C, "状态 C · 三槽全空 · 顶栏完全留白 —— 这是「没装备」时的样子"),
    ):
        im, B = r1_empty(state)
        n, rep = overlap_report("R1改v6-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    SW = W + 68
    H1 = 172 + (H + CAP_H + GAP) * 3 + 30
    sh = Image.new("RGB", (SW, H1), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "R1 改 v6 · 空槽什么都不画 + 布局再调（1:1）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 42), "① 空槽不再画「淡出空卡 / 类型名 / 淡菱形」—— 没装备就是没有东西，读起来不再像幽灵卡",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 60), "   槽位仍位置固定（左→右 = 武器 / 防具 / 饰品）→ 缺哪一类，看空在哪一格",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 78), "② 卡与卡只压 10px（步长 50，v5 是 14px）→ 三张卡基本各自完整可读，不再挤成一坨",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 96), "③ 卡片组居中于立绘上方：组 x380–540、组心 460 ≈ 立绘 x361–555 的组心 458 → 左右对称",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 114), "④ 左栏垂直节奏均分：名字→金线 26 / 金线→属性 34 / 属性→描述 32 / 描述→标签 34",
           font=f_s, fill=(226, 210, 180))
    d.text((16, 132), "   面板 634×490 · 立绘 194×342 · 关闭签 54×25 骑在上边框线（ins 8/11/13）上",
           font=f_s, fill=(206, 186, 150))
    y = 172
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((W, H), Image.LANCZOS), (34, y + CAP_H))
        y += H + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v6_空槽留白_三态.png")
    sh.save(p)
    print("写出", p, sh.size)

    # ---- 区块边界图 ----
    H2 = 136 + (H + 34) * 3 + 20
    sh2 = Image.new("RGB", (SW, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同三态 · 区块边界图（每个彩框 = 一个区块；两两不相交 = 零遮挡）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 4 个属性行 / 描述 / 标签 / 装备组 / 关闭签 / 立绘 —— 满装时 10 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "※ 空槽不画 → 装备组只登记真的画了卡的那一段（不画就不占位）",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 80), "重点：装备组下缘 y114 vs 立绘上缘 y120 → 差 6px，装备不压立绘",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 98), "关闭签与装备组在 x 上相隔 17px，与立绘在 x 上有 4px 交叠但 y 相距 94px → 不算重叠",
            font=f_s, fill=(206, 186, 150))
    y2 = 136
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((W, H), Image.LANCZOS), (34, y2))
        y2 += H + 34
    p2 = os.path.join(REF, "面板R1改v6_空槽留白_三态_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v6_状态%s_1x.png" % tag)
        im.resize((W, H), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 放大：装备卡 + 关闭签 + 左栏 ----
    imA, imB = outs[1][2], outs[0][2]
    Z = 3
    fanB = imB.crop((S(368), S(0), S(556), S(126))).resize((188 * Z, 126 * Z), Image.LANCZOS)
    fanA = imA.crop((S(368), S(0), S(556), S(126))).resize((188 * Z, 126 * Z), Image.LANCZOS)
    tab = imB.crop((S(544), S(0), S(616), S(34))).resize((72 * Z, 34 * Z), Image.LANCZOS)
    col = imB.crop((S(30), S(24), S(300), S(322))).resize((270 * 2, 298 * 2), Image.LANCZOS)
    W3 = max(fanB.width + tab.width + 34 * 3, col.width + 68)
    H3 = 112 + fanB.height + 26 + fanA.height + 40 + col.height + 30
    sh3 = Image.new("RGB", (W3, H3), (42, 39, 35))
    d3 = ImageDraw.Draw(sh3)
    d3.text((16, 16), "3x 放大：装备区（满装 / 只装饰品）+ 关闭签 + 左栏", font=Fs(17, True), fill=(240, 232, 214))
    d3.text((16, 44), "装备卡 60×106：卡面 art/card.png 打底 + 名字（10px，先折行再截断，最多 2 行）+ 图标（48×60 等比居中）",
            font=f_s, fill=(206, 186, 150))
    d3.text((16, 62), "相邻只压 10px（步长 50）→ 三张卡的名字都基本读得全；有卡的落影 1.7/2.6px → 读作一摞卡",
            font=f_s, fill=(206, 186, 150))
    y3 = 112
    d3.text((34, y3 - 18), "状态 B · 三槽全满", font=f_s, fill=(226, 210, 180))
    sh3.paste(fanB, (34, y3))
    sh3.paste(tab, (34 + fanB.width + 34, y3))
    y3 += fanB.height + 26
    d3.text((34, y3), "状态 A · 只装饰品 —— 武器/防具 两格不画任何东西（注意左侧就是空的纸面）",
            font=f_s, fill=(150, 200, 150))
    sh3.paste(fanA, (34, y3 + 20))
    y3 += fanA.height + 40
    d3.text((34, y3 - 20), "左栏（2x）：名字下没有副标；属性 4 行竖排；属性下没有装备名",
            font=f_s, fill=(206, 186, 150))
    sh3.paste(col, (34, y3))
    p3 = os.path.join(REF, "面板R1改v6_装备区_放大3x.png")
    sh3.save(p3)
    print("写出", p3, sh3.size)

    # ---- 与 v5 对照 ----
    prev = os.path.join(REF, "面板R1改v5_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        H5 = 168 + (H + CAP_H + 34) * 2 + 26
        sh5 = Image.new("RGB", (SW, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "v5 → v6（同一份数据：三槽全满）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "v5：卡压 14px；左栏空档 30 / 40 不等大",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "v6：卡只压 10px 且组居中于立绘上方；左栏节奏 26 / 34 / 32 / 34 均分",
                font=f_s, fill=(150, 200, 150))
        d5.text((16, 80), "v5 断言 10 块 0 对；v6 满装 10 块 0 对（空槽态更少：不画就不登记）",
                font=f_s, fill=(150, 172, 138))
        y5 = 168
        d5.text((34, y5), "v5（卡压 14px · 空槽画淡出空卡）", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += H + CAP_H + 34
        d5.text((34, y5), "v6（卡只压 10px · 空槽留白 · 组居中）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[0][2].resize((W, H), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v6_与v5对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_empty.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
