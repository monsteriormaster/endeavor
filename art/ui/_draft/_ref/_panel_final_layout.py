# -*- coding: utf-8 -*-
"""⚠️ **已被取代（2026-10-13），仅作历史留存，不要再按它改面板。**

    本脚本描述的是「850×700 + `art/character_panel_bg.png` 整张纸底图」那一版版面。
    2026-10-13 用户把面板改成「卡牌版」（1344×700：立绘装进一张放大的卡牌、
    装备三张叠在主卡左后方、属性 2×2 网格、弱边界只罩右栏），旧底线框与刻度条全部撤掉。

    ★ 现役唯一规格来源 =
        `design/_tools/make_panel_card.py`（版面与配色 + 自检）
        `design/_tools/make_panel_card_bg.py`（把静态层烤成 `art/ui/character_panel_card_bg.png`）
      实装数字写在 `components/character_panel.gd` 的「规格表」段。

    ⚠️ `art/character_panel_bg.png`（旧的整张纸底图）**现在没有任何场景引用**，
      但本目录的几个设计脚本还在读它 —— 所以文件留着，别当垃圾删。

--------------------------------------------------------------------------------
v8 布局的「真机版」—— 面板 850×700，铺**游戏真实底图**，内容整体平移进内框。

为什么不是 634×520：
  `art/character_panel_bg.png` 是 1370×933，内框（细金线）在原生
      x 110..1225（宽 81.4%）、y 133..787（高 70.1%）
  四角还有成片的**金色卷草**，内向包络实测（原生→面板占比）：
      y 4.3%  → x 25.6%      左上角饰沿顶边向右伸到面板宽 26% 处
      y 8.6%  → x 16.4%
      y 12.9% → x 12.4%
      y 17.1% → x 18.5%（卷草尾巴往下勾）
      y 21.4% → 归零
  所以「内容区」只有面板的 81% × 70%。mock 的 634×520 是拿自己画的**细铜线框**当边界的，
  内容铺到 x40/y30 —— 真实底图下会压在卷草上（已渲染确认，名字/关闭/标签全中）。
  要保住 v8 的 1:1 尺寸（字不能缩），面板必须放到 850×700：
      内容区 = 850×81.4% ≈ 692 ... 实际用内框 x126..724 / y112..599 → 598×487
      v8 内容 = 576×472  →  正正好，**1:1 平移**：所有 mock 坐标 + (95, 90)

本脚本只读素材 + 出图。坐标表就是给（当时的）`character_panel.tscn` 的规格来源。

  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_final_layout.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)

import _panel_redesign as pr      # noqa: E402
import _panel_r1_fan as pf        # noqa: E402

from PIL import Image, ImageDraw  # noqa: E402

S, F, Fs, tw, wrap, mix = pr.S, pr.F, pr.Fs, pr.tw, pr.wrap, pr.mix
BODY, BRASS, BRASS2, BRASS_LT, INK, INK_TEXT, SUB_TEXT, SHADOW = (
    pr.BODY, pr.BRASS, pr.BRASS2, pr.BRASS_LT, pr.INK, pr.INK_TEXT, pr.SUB_TEXT, pr.SHADOW)
rule, gold_rule = pr.rule, pr.gold_rule
portrait_fit, place = pr.portrait_fit, pr.place
overlap_report, draw_debug_rects = pr.overlap_report, pr.draw_debug_rects
NAME, DESC, ATTRS, TAGS = pr.NAME, pr.DESC, pr.ATTRS, pr.TAGS
tier_col = pr.tier_col
icon, ellipsize, tbox = pf.icon, pf.ellipsize, pf.tbox
SLOTS3, STATE_A, STATE_B = pf.SLOTS3, pf.STATE_A, pf.STATE_B
diamond = pf.diamond

BG = os.path.join(R, "art", "character_panel_bg.png")
CARD_TEX = os.path.join(R, "art", "card.png")

# ============================================================
#  ★ 规格表（= mock 坐标 + (95, 90)）—— 这就是要写进 .tscn 的数字
# ============================================================
PANEL_W, PANEL_H = 850, 700

NAME_X, NAME_Y = 130, 120                  # mock (40,30)
RULE_X0, RULE_X1 = 130, 376                # 左栏内容左右缘
GOLD1_Y = 186                              # mock 96  —— 名字区结束的装饰线
ATTR_C0, ATTR_PITCH = 226, 66              # mock 136/66 —— 4 行中心 226/292/358/424
ATTR_BOX = 26
ATTR_BX = 130                              # 左轴（= 铭牌左缘）
ATTR_NAME_X = 166
ATTR_VAL_X = 232
METER_X, METER_W = 266, 110
GOLD2_Y = 464                              # mock 374 —— 属性区结束的装饰线
DESC_X, DESC_Y = 130, 476                  # mock (40,386)
FAINT_Y = 530                              # mock 440 —— 描述/标签之间的极淡细线
TAG_X, TAG_Y = 130, 542                    # mock (40,452)
DIV_X = 390                                # mock 300 —— 竖分割线
PORT = (390, 230, 706, 590)                # mock (300,140,616,500) —— 立绘框
CARD_X1 = 630                              # mock 540
CARD_Y0 = 118                              # mock 28
CARD_W, CARD_H, CARD_STEP = 60, 106, 56
CLOSE = (648, 120, 700, 146)               # mock (558,30,610,56)

_cf = {}


def real_bg(w, h):
    return Image.open(BG).convert("RGB").resize((S(w), S(h)), Image.LANCZOS)


def card_face(w, h):
    if (w, h) not in _cf:
        _cf[(w, h)] = Image.open(CARD_TEX).convert("RGB").resize((S(w), S(h)), Image.LANCZOS)
    return _cf[(w, h)]


def draw_card_name(d, x, y, text, f, col, strip):
    maxw = strip - 12
    lines = wrap(d, text, f, S(maxw))
    if len(lines) > 1:
        if len(lines) == 2:
            c = (len(text) + 1) // 2
            lines = [text[:c], text[c:]]
        else:
            lines = lines[:2]
            lines[-1] = ellipsize(d, lines[-1] + "…", f, maxw)
    lines = [ellipsize(d, ln, f, maxw) for ln in lines]
    lh, cx = 13, x + strip / 2.0
    for i, ln in enumerate(lines):
        d.text((S(cx) - tw(d, ln, f) / 2.0, S(y + 9 + i * lh)), ln, font=f, fill=col)


def equip_card(im, d, x, y, item):
    if item is None:
        return
    w, h = CARD_W, CARD_H
    sh = Image.new("RGBA", (S(w), S(h)), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([0, 0, S(w) - 1, S(h) - 1], radius=S(4),
                                         fill=(92, 74, 52, 66))
    im.paste(sh.convert("RGB"), (S(x) + S(1.6), S(y) + S(2.4)), sh.split()[-1])
    im.paste(card_face(w, h), (S(x), S(y)))
    draw_card_name(d, x, y + 5, item, F(10), INK_TEXT, CARD_STEP)
    iy0, iy1 = y + 38, y + h - 6
    ccy = (iy0 + iy1) / 2.0
    ic = icon(item, w - 12, (iy1 - iy0) - 2)
    if ic is not None:
        im.paste(ic.convert("RGB"),
                 (S(x + w / 2.0) - ic.width // 2, S(ccy) - ic.height // 2), ic.split()[-1])
    else:
        f0 = F(20, True)
        d.text((S(x + w / 2.0) - tw(d, item[0], f0) / 2.0, S(ccy) - 14),
               item[0], font=f0, fill=mix(BODY, INK_TEXT, 0.55))


def close_btn(d, x0, y0, x1, y1, label="关闭"):
    d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(6), outline=BRASS,
                        width=max(1, int(1.2 * pr.SC)), fill=mix(BODY, BRASS_LT, 0.20))
    f = F(13)
    d.text((S((x0 + x1) / 2.0) - tw(d, label, f) / 2.0, S((y0 + y1) / 2.0) - 9),
           label, font=f, fill=INK_TEXT)


def attr_row(im, d, cy, k, v, with_meter=True):
    col = tier_col(v)
    b = ATTR_BOX
    bx0, by0 = ATTR_BX, cy - b / 2.0
    d.rounded_rectangle([S(bx0), S(by0), S(bx0 + b), S(by0 + b)], radius=S(6),
                        fill=mix(BODY, BRASS_LT, 0.26), outline=col,
                        width=max(1, int(1.3 * pr.SC)))
    diamond(d, bx0 + b / 2.0, by0 + b / 2.0, 5.0, fill=mix(col, BODY, 0.16))
    d.text((S(ATTR_NAME_X), S(cy - 9)), k, font=F(14), fill=SUB_TEXT)
    d.text((S(ATTR_VAL_X), S(cy - 15)), str(v), font=F(22, True), fill=col)
    if with_meter:
        pr.meter(d, METER_X, cy - 2.5, METER_W, v, col)


def layout(state, with_meter=True, base=None, title=False):
    im = (base or real_bg(PANEL_W, PANEL_H)).copy()
    d = ImageDraw.Draw(im)
    B = {}

    d.text((S(NAME_X), S(NAME_Y)), NAME, font=F(27, True), fill=INK_TEXT)
    B["name"] = tbox(d, NAME_X, NAME_Y, NAME, F(27, True))
    gold_rule(d, RULE_X0, RULE_X1, GOLD1_Y)

    for i, (k, v) in enumerate(ATTRS):
        cy = ATTR_C0 + i * ATTR_PITCH
        attr_row(im, d, cy, k, v, with_meter)
        B["attr_%d" % i] = (RULE_X0, cy - 22, RULE_X1, cy + 22)

    gold_rule(d, RULE_X0, RULE_X1, GOLD2_Y)
    yy, dmax = DESC_Y, RULE_X0
    for ln in wrap(d, DESC, F(12), S(RULE_X1 - RULE_X0)):
        d.text((S(DESC_X), S(yy)), ln, font=F(12), fill=mix(BODY, INK_TEXT, 0.74))
        dmax = max(dmax, tbox(d, DESC_X, yy, ln, F(12))[2])
        yy += 19
    B["desc"] = (RULE_X0, DESC_Y, dmax, yy)

    rule(d, RULE_X0, FAINT_Y, RULE_X1, FAINT_Y, a=0.30)
    tx = TAG_X
    for s in TAGS:
        bw = int(tw(d, s, F(13)) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(TAG_Y), S(tx + bw), S(TAG_Y + 26)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(TAG_Y + 4)), s, font=F(13), fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (TAG_X, TAG_Y, tx, TAG_Y + 26)

    rule(d, DIV_X, NAME_Y, DIV_X, PORT[3], a=0.45)

    px0, py0, px1, py1 = PORT
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = px0 + (px1 - px0 - pw) // 2, py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    n = len(SLOTS3)
    x0 = CARD_X1 - (CARD_W + (n - 1) * CARD_STEP)
    drawn = None
    for i, (cls, cn) in enumerate(SLOTS3):
        cx = x0 + i * CARD_STEP
        if state.get(cls) is None:
            continue
        equip_card(im, d, cx, CARD_Y0, state[cls])
        r = (cx, CARD_Y0, cx + CARD_W, CARD_Y0 + CARD_H)
        drawn = r if drawn is None else (min(drawn[0], r[0]), CARD_Y0,
                                         max(drawn[2], r[2]), CARD_Y0 + CARD_H)
    if drawn is not None:
        B["equip"] = drawn

    close_btn(d, CLOSE[0], CLOSE[1], CLOSE[2], CLOSE[3])
    B["close"] = CLOSE
    if title:
        d.text((S(NAME_X), S(NAME_Y - 40)), "真机版 850×700（内容 = mock 坐标 +(90,90)）",
               font=F(15, True), fill=(150, 120, 80))
    return im, B


STATE_C = {}


def main():
    log = []
    outs = []
    for tag, st, cap in (("B", STATE_B, "状态 B · 三槽全满"),
                         ("A", STATE_A, "状态 A · 只装饰品"),
                         ("C", STATE_C, "状态 C · 三槽全空")):
        im, B = layout(st)
        n, rep = overlap_report("真机版-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_s = Fs(12)
    SW = PANEL_W + 68
    CAP_H, GAP = 28, 30
    H1 = 210 + (PANEL_H + CAP_H + GAP) * 3 + 30
    sh = Image.new("RGB", (SW, H1), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "v8 布局铺真实底图 · 850×700（1:1，内容坐标 = mock +(95,90)）",
           font=Fs(17, True), fill=(240, 232, 214))
    for i, tx in enumerate([
        "底图 1370×933 的内框（细金线）实测在 x110..1225 / y133..787 → 内容区只占面板 81% × 70%",
        "四角还有成片金色卷草：左上沿顶边向右伸到面板宽 26%、往下到面板高 21%",
        "mock 的 634×520 是拿自己画的细铜线当边界，内容铺到 x40/y30 → 真实底图下会压在卷草上",
        "要保住 v8 的 1:1 尺寸（字号不能缩），面板必须放到 850×700 —— 内容正好 1:1 平移进去（+90,+90）",
        "本图不带 mock 的程序化边框与纸纹：真实底图自带框与旧纸",
    ]):
        d.text((16, 44 + i * 18), tx, font=f_s, fill=(150, 200, 150) if i < 4 else (206, 186, 150))
    y = 210
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=Fs(15, True), fill=(226, 210, 180))
        sh.paste(im.resize((PANEL_W, PANEL_H), Image.LANCZOS), (34, y + CAP_H))
        y += PANEL_H + CAP_H + GAP
    p = os.path.join(REF, "面板_真机版850x700_三态_真实底图.png")
    sh.save(p)
    print("写出", p, sh.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板_真机版850x700_状态%s.png" % tag)
        im.resize((PANEL_W, PANEL_H), Image.LANCZOS).save(q)
        print("写出", q)

    imB = outs[0][2]
    dbg = draw_debug_rects(imB, outs[0][3]).resize((PANEL_W, PANEL_H), Image.LANCZOS)
    p2 = os.path.join(REF, "面板_真机版850x700_状态B_区块边界.png")
    dbg.save(p2)
    print("写出", p2)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_final_layout.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
