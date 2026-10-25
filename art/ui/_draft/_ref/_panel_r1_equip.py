# -*- coding: utf-8 -*-
"""R1 改版 —— 装备区从「一行文字」改成《苏丹的游戏》式**装备槽**。

依据（真实来源，非想象）：
  · 苏丹人物/卡牌面板里，装备按**类型固定占槽**：武器 / 服装 / 饰品（部分角色另有驯兽槽），
    **每类只能装一件**，把装备卡拖进对应槽即完成装备（游侠网/游戏狂/玩一玩 三篇攻略
    + bwiki 新手指南口径一致：「人物面板右上角标注可装备的装备类型」）。
  · 苏丹面板的行样式 = [带细金属边的小方框图标] + [名称] + [数值]；框用**品级色**描边。
  · 本作装备大类（`card_data.gd::category_minor()` 的排序口径）= weapon / armor / jewelry / tool
    → 槽位集合取这 4 个，与苏丹 3 槽同构（多一个「工具」）。

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_equip.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)
import _panel_redesign as pr  # noqa: E402  （已加 __main__ 守卫，import 不会重跑出图）

from PIL import Image, ImageDraw  # noqa: E402

S, F, Fs, tw, wrap, mix = pr.S, pr.F, pr.Fs, pr.tw, pr.wrap, pr.mix
BODY, BRASS, BRASS2, BRASS_LT, INK, INK_TEXT, SUB_TEXT, SHADOW = (
    pr.BODY, pr.BRASS, pr.BRASS2, pr.BRASS_LT, pr.INK, pr.INK_TEXT, pr.SUB_TEXT, pr.SHADOW)
base_bg, frame, rule, gold_rule = pr.base_bg, pr.frame, pr.rule, pr.gold_rule
portrait_fit, place, close_btn = pr.portrait_fit, pr.place, pr.close_btn
overlap_report, draw_debug_rects = pr.overlap_report, pr.draw_debug_rects

PW, PH = pr.PW, pr.PH
NAME, SUB, DESC = pr.NAME, pr.SUB, pr.DESC
ATTRS, TAGS = pr.ATTRS, pr.TAGS
tier_col = pr.tier_col

# ---- 槽位集合：与 category_minor() 的排序口径一致（weapon/armor/jewelry/tool）----
SLOTS = [("weapon", "武器"), ("armor", "防具"), ("jewelry", "饰品"), ("tool", "工具")]

# 品级色（描边）—— 苏丹的卡框按品级换色，这里沿用同一手法
TIER_COL = {"SSR": (188, 142, 62), "SR": BRASS2, "S": (166, 164, 158), "R": (178, 130, 88)}

# 真实数据（全部来自 resoures/items/*.json 的 name / level / icon 字段，路径不猜）
ITEM_DB = {
    "多功能军刀":     ("R",  os.path.join(R, "art", "items", "多功能军刀.png"),     "str+1"),
    "骑士盔甲":       ("R",  os.path.join(R, "art", "items", "骑士盔甲.png"),       "bod+1"),
    "章鱼尾人身塑像": ("SR", os.path.join(R, "art", "items", "章鱼尾人身塑像.png"), "app+1"),
    "越狱工具":       ("R",  os.path.join(R, "art", "items", "越狱工具.png"),       "bod+1"),
}

# 状态 A = 衫斯在 characters.json 里的**真实装备**：只有 {jewelry: ...}
STATE_A = {"jewelry": "章鱼尾人身塑像"}
# 状态 B = 四槽全满（看满装观感；同时验证长名字截断）
STATE_B = {"weapon": "多功能军刀", "armor": "骑士盔甲",
           "jewelry": "章鱼尾人身塑像", "tool": "越狱工具"}

_ic = {}


def icon(name, box_w, box_h):
    if name not in ITEM_DB:
        return None
    path = ITEM_DB[name][1]
    if not os.path.exists(path):
        return None
    if (name, box_w, box_h) not in _ic:
        im = Image.open(path).convert("RGBA")
        im.thumbnail((S(box_w), S(box_h)), Image.LANCZOS)
        _ic[(name, box_w, box_h)] = im
    return _ic[(name, box_w, box_h)]


def ellipsize(d, s, f, maxw):
    """按 1x 宽度 maxw 截断，超出加 …（面板里放不下就得截，不能溢出槽）。"""
    if tw(d, s, f) <= S(maxw):
        return s
    while s and tw(d, s + "…", f) > S(maxw):
        s = s[:-1]
    return s + "…"


def tbox(d, x, y, s, f):
    """文本的**实测** bbox（1x，向外取整）。

    别用「拍脑袋的矩形」登记区块：槽下小字可以比槽宽 6px，登记成槽宽就会
    **少算 3px**，把「其实已经越界」判成零重叠 —— 断言就失去意义了。
    """
    bb = d.textbbox((S(x), S(y)), s, font=f)
    return (int(bb[0] // pr.SC), int(bb[1] // pr.SC),
            int(-(-bb[2] // pr.SC)), int(-(-bb[3] // pr.SC)))


def diamond(d, cx, cy, r, fill=None, outline=None, ow=1.2):
    pts = [(S(cx), S(cy - r)), (S(cx + r), S(cy)), (S(cx), S(cy + r)), (S(cx - r), S(cy))]
    if fill is not None:
        d.polygon(pts, fill=fill)
    if outline is not None:
        d.line(pts + [pts[0]], fill=outline, width=max(1, int(ow * pr.SC)), joint="curve")


def slot(im, d, x, y, w, h, item):
    """一个装备槽。item=None → 空槽（内凹实底 + 中央淡菱形）。"""
    filled = item is not None
    bg = mix(BODY, BRASS_LT, 0.20) if filled else mix(BODY, SHADOW, 0.14)
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=S(6), fill=bg)
    # 内凹：越靠边越暗，读作「嵌进去的槽」而不是「贴上去的卡」
    for k in range(4):
        a = 0.17 * (1 - k / 4.0)
        d.rounded_rectangle([S(x + k), S(y + k), S(x + w - k), S(y + h - k)],
                            radius=S(6), outline=mix(bg, SHADOW, a))
    # 边框：满槽按品级色（细 + 金属感），空槽是暗铜虚线感的淡边
    if filled:
        bc = TIER_COL.get(ITEM_DB.get(item, ("R",))[0], BRASS)
    else:
        bc = mix(BODY, SHADOW, 0.52)
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=S(6),
                        outline=bc, width=max(1, int((1.4 if filled else 1.0) * pr.SC)))
    if filled:
        diamond(d, x + w / 2.0, y + 4.0, 2.6, fill=bc)          # 顶中品级徽记
        ic = icon(item, w - 18, h - 18)
        if ic is not None:
            im.paste(ic.convert("RGB"),
                     (S((x + w / 2.0)) - ic.width // 2, S(y + h / 2.0) - ic.height // 2 + 2),
                     ic.split()[-1])
        else:
            # 无 icon 的装备（如「年少的欢喜」）→ 用名字首字兜底，不画空白方块
            f = F(24, True)
            d.text((S(x + w / 2.0) - tw(d, item[0], f) / 2.0, S(y + h / 2.0) - 16),
                   item[0], font=f, fill=mix(bg, INK_TEXT, 0.55))
    else:
        diamond(d, x + w / 2.0, y + h / 2.0, 8.5, outline=mix(bg, SHADOW, 0.60), ow=1.0)


def r1_equip(state, tag="A"):
    """R1 骨架不动，只把「装 备」块换成 4 个槽 + 描述下移 20px。"""
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    # ---- 立绘 / 分割线：与 R1 完全一致 ----
    px0, py0, px1, py1 = 392, 64, 616, 404
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = px1 - pw, py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)
    rule(d, 372, 34, 372, 400, a=0.5)

    f_name, f_sub, f_lab, f_val, f_body = F(27, True), F(12), F(12, True), F(19, True), F(13)
    f_slot = F(11)

    # ---- 名字 / 副标 / 金线 ----
    d.text((S(40), S(30)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 30, NAME, f_name)
    d.text((S(42), S(70)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = tbox(d, 42, 70, SUB, f_sub)
    gold_rule(d, 40, 300, 92)

    # ---- 属性：一行四格 ----
    d.text((S(40), S(104)), "属 性", font=f_lab, fill=INK)
    B["attr_label"] = tbox(d, 40, 104, "属 性", f_lab)
    for i, (k, v) in enumerate(ATTRS):
        gx = 40 + i * 82
        d.text((S(gx), S(122)), k, font=f_sub, fill=SUB_TEXT)
        d.text((S(gx), S(138)), str(v), font=f_val, fill=tier_col(v))
        pr.meter(d, gx, 168, 66, v, tier_col(v))
        B["attr_%d" % i] = (gx, 122, gx + 74, 173)

    # ---- 标签 ----
    d.text((S(40), S(186)), "标 签", font=f_lab, fill=INK)
    B["tag_label"] = tbox(d, 40, 186, "标 签", f_lab)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(204), S(tx + bw), S(230)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(208)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 204, tx, 230)

    # ---- 装备：4 个类型槽（本轮改的就是这里）----
    d.text((S(40), S(242)), "装 备", font=f_lab, fill=INK)
    B["eq_label"] = tbox(d, 40, 242, "装 备", f_lab)
    SW, SH, GAP = 73, 66, 8
    for i, (cls, cn) in enumerate(SLOTS):
        sx = 40 + i * (SW + GAP)
        nm = state.get(cls)
        slot(im, d, sx, 258, SW, SH, nm)
        B["slot_%s" % cls] = (sx, 258, sx + SW, 258 + SH)
        lab = ellipsize(d, nm, f_slot, SW + 6) if nm else cn
        col = INK_TEXT if nm else mix(BODY, SHADOW, 0.85)
        lx = sx + SW / 2.0 - tw(d, lab, f_slot) / pr.SC / 2.0
        d.text((S(lx), S(328)), lab, font=f_slot, fill=col)
        B["slotlab_%s" % cls] = tbox(d, lx, 328, lab, f_slot)

    # ---- 描述（R1 是 y338；装备槽吃掉 20px，顺延到 y358）----
    rule(d, 40, 350, 356, 350, a=0.35)
    yy = 358
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(320)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 20
    B["desc"] = (40, 358, dmax, yy)

    close_btn(d, 556, 20, 602, 50)
    B["close"] = (556, 20, 602, 50)
    return im, B


def r1_equip_rows(state):
    """对照变体：装备不用「槽」，改用苏丹面板的**属性行**样式 ——
    一行一件：[带细金属边的小方框图标] + 类型名 + 装备名。空槽显示「— 空」。
    代价：4 行需要 4×34=136px，432 装不下 → 面板加高到 478。
    """
    w, h = PW, 500
    im = base_bg(w, h)
    frame(im, w, h, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    px0, py0, px1, py1 = 392, 64, 616, 472
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = px1 - pw, py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)
    rule(d, 372, 34, 372, 468, a=0.5)

    f_name, f_sub, f_lab, f_val, f_body = F(27, True), F(12), F(12, True), F(19, True), F(13)
    f_slot = F(11)

    d.text((S(40), S(30)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 30, NAME, f_name)
    d.text((S(42), S(70)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = tbox(d, 42, 70, SUB, f_sub)
    gold_rule(d, 40, 300, 92)

    d.text((S(40), S(104)), "属 性", font=f_lab, fill=INK)
    B["attr_label"] = tbox(d, 40, 104, "属 性", f_lab)
    for i, (k, v) in enumerate(ATTRS):
        gx = 40 + i * 82
        d.text((S(gx), S(122)), k, font=f_sub, fill=SUB_TEXT)
        d.text((S(gx), S(138)), str(v), font=f_val, fill=tier_col(v))
        pr.meter(d, gx, 168, 66, v, tier_col(v))
        B["attr_%d" % i] = (gx, 122, gx + 74, 173)

    d.text((S(40), S(186)), "标 签", font=f_lab, fill=INK)
    B["tag_label"] = tbox(d, 40, 186, "标 签", f_lab)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(204), S(tx + bw), S(230)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(208)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 204, tx, 230)

    # 装备：4 行
    d.text((S(40), S(242)), "装 备", font=f_lab, fill=INK)
    B["eq_label"] = tbox(d, 40, 242, "装 备", f_lab)
    BS = 34
    for i, (cls, cn) in enumerate(SLOTS):
        ry = 258 + i * 38
        nm = state.get(cls)
        bg = mix(BODY, BRASS_LT, 0.18) if nm else mix(BODY, SHADOW, 0.12)
        bc = TIER_COL.get(ITEM_DB.get(nm, ("R",))[0], BRASS) if nm else mix(BODY, SHADOW, 0.5)
        d.rounded_rectangle([S(40), S(ry), S(40 + BS), S(ry + BS)], radius=S(6), fill=bg)
        d.rounded_rectangle([S(40), S(ry), S(40 + BS), S(ry + BS)], radius=S(6),
                            outline=bc, width=max(1, int((1.3 if nm else 1.0) * pr.SC)))
        if nm:
            ic = icon(nm, BS - 8, BS - 8)
            if ic is not None:
                im.paste(ic.convert("RGB"), (S(40 + BS / 2.0) - ic.width // 2,
                                             S(ry + BS / 2.0) - ic.height // 2),
                         ic.split()[-1])
            else:
                f0 = F(20, True)
                d.text((S(40 + BS / 2.0) - tw(d, nm[0], f0) / 2.0, S(ry + 7)), nm[0],
                       font=f0, fill=mix(bg, INK_TEXT, 0.55))
        else:
            diamond(d, 40 + BS / 2.0, ry + BS / 2.0, 6.5,
                    outline=mix(bg, SHADOW, 0.55), ow=1.0)
        B["box_%s" % cls] = (40, ry, 40 + BS, ry + BS)
        # 类型名（固定）
        d.text((S(86), S(ry + 10)), cn, font=f_slot, fill=mix(BODY, SHADOW, 0.95))
        B["type_%s" % cls] = tbox(d, 86, ry + 10, cn, f_slot)
        # 装备名 / 空
        val = nm if nm else "— 空"
        vcol = INK_TEXT if nm else mix(BODY, SHADOW, 0.8)
        d.text((S(128), S(ry + 7)), val, font=f_body, fill=vcol)
        B["val_%s" % cls] = tbox(d, 128, ry + 7, val, f_body)

    rule(d, 40, 424, 356, 424, a=0.35)
    yy = 434
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(320)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 20
    B["desc"] = (40, 434, dmax, yy)

    close_btn(d, 556, 20, 602, 50)
    B["close"] = (556, 20, 602, 50)
    return im, B


def r1_equip_top(state):
    """R1 改 v2 —— 按用户三条指令重排：
      ① 装备槽**移到「关闭」左边**（顶部一条，横排 4 槽）
      ② **不写「属性 / 标签 / 装备」三个板块标题**
      ③ **标签贴最下方**
    代价（必须说明）：槽横排要 4×81+3×7=345px 宽、70px 高，必须占满顶部 →
    立绘只能从 y100 起（340 → 304 高，缩 ~11%），否则 x392–546 那段会撞在一起。
    """
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    # ---- 立绘：从 y104 起（顶部让给装备槽）----
    px0, py0, px1, py1 = 392, 104, 616, 404
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = px1 - pw, py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    f_name, f_sub, f_val, f_body = F(27, True), F(12), F(19, True), F(13)

    # ---- 顶部左：名字 / 副标 ----
    d.text((S(40), S(18)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 18, NAME, f_name)
    d.text((S(42), S(60)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = tbox(d, 42, 60, SUB, f_sub)

    # ---- 顶部右：装备槽 ×4，紧贴「关闭」左边 ----
    SW, SH, GAP, TOP = 86, 84, 7, 10
    x_end = 546                       # 关闭钮左缘 556 - 10 间距
    x0 = x_end - (len(SLOTS) * SW + (len(SLOTS) - 1) * GAP)   # = 181
    for i, (cls, cn) in enumerate(SLOTS):
        sx = x0 + i * (SW + GAP)
        nm = state.get(cls)
        slot_top(im, d, sx, TOP, SW, SH, nm, cn)
        B["slot_%s" % cls] = (sx, TOP, sx + SW, TOP + SH)

    # ---- 金线 + 竖分割线（分割线必须在槽下方才开始，否则会穿过槽）----
    gold_rule(d, 40, 300, 100)
    rule(d, 372, 108, 372, 400, a=0.5)

    # ---- 属性：一行四格，**无板块标题** ----
    for i, (k, v) in enumerate(ATTRS):
        gx = 40 + i * 82
        d.text((S(gx), S(160)), k, font=f_sub, fill=SUB_TEXT)
        d.text((S(gx), S(176)), str(v), font=f_val, fill=tier_col(v))
        pr.meter(d, gx, 204, 66, v, tier_col(v))
        B["attr_%d" % i] = (gx, 160, gx + 74, 209)

    # ---- 描述（**无板块标题**，用一条细线分隔）----
    rule(d, 40, 268, 356, 268, a=0.35)
    yy = 280
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(320)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 21
    B["desc"] = (40, 280, dmax, yy)

    # ---- 标签：**贴最下方**，**无板块标题** ----
    rule(d, 40, 348, 356, 348, a=0.3)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(360), S(tx + bw), S(386)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(364)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 360, tx, 386)

    close_btn(d, 556, 20, 602, 50)
    B["close"] = (556, 20, 602, 50)
    return im, B


def slot_top(im, d, x, y, w, h, item, cn):
    """顶部横排用的槽：**迷你卡面** —— 顶条写名字（满=装备名 / 空=类型名）+ 细线 + 下方图标。

    名字进槽内而不是放槽下：槽下那一条会被立绘（x392 起）吃掉，放槽下必然压立绘。
    槽做 78×84 的竖方形（不是横长条）→ 图标能到 64×58，名字条 10px 也正好放下「章鱼尾人身塑像」7 字。
    """
    filled = item is not None
    bg = mix(BODY, BRASS_LT, 0.20) if filled else mix(BODY, SHADOW, 0.14)
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=S(6), fill=bg)
    for k in range(4):
        a = 0.17 * (1 - k / 4.0)
        d.rounded_rectangle([S(x + k), S(y + k), S(x + w - k), S(y + h - k)],
                            radius=S(6), outline=mix(bg, SHADOW, a))
    bc = TIER_COL.get(ITEM_DB.get(item, ("R",))[0], BRASS) if filled else mix(BODY, SHADOW, 0.52)
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=S(6),
                        outline=bc, width=max(1, int((1.4 if filled else 1.0) * pr.SC)))
    if filled:
        diamond(d, x + w / 2.0, y + 4.0, 2.6, fill=bc)

    # 名字条：满槽 = 装备名（10px，超宽截断）；空槽 = 类型名（暗）
    # ⚠️ 「章鱼尾人身塑像」7 字 @10px 实测正好 70.0px —— 槽内可用宽必须 > 70（w-8），
    #    按 78 宽的槽做时是「正好等于」，左右零边距贴死，所以槽宽提到 86。
    f_nm = F(10)
    lab = ellipsize(d, item, f_nm, w - 10) if filled else cn
    lcol = INK_TEXT if filled else mix(BODY, SHADOW, 0.9)
    d.text((S(x + w / 2.0) - tw(d, lab, f_nm) / 2.0, S(y + 8)), lab, font=f_nm, fill=lcol)
    d.rectangle([S(x + 9), S(y + 23), S(x + w - 9), S(y + 23) + max(1, int(0.9 * pr.SC))],
                fill=mix(bg, BRASS, 0.38))

    # 图标区：y+25 .. y+h-6（居中；别贴着下边框）
    ic_y0, ic_h = y + 25, (h - 6) - (y + 25)
    ccy = ic_y0 + ic_h / 2.0
    if filled:
        ic = icon(item, w - 16, ic_h - 6)
        if ic is not None:
            im.paste(ic.convert("RGB"),
                     (S(x + w / 2.0) - ic.width // 2, S(ccy) - ic.height // 2),
                     ic.split()[-1])
        else:
            f0 = F(22, True)
            d.text((S(x + w / 2.0) - tw(d, item[0], f0) / 2.0, S(ccy) - 15),
                   item[0], font=f0, fill=mix(bg, INK_TEXT, 0.55))
    else:
        diamond(d, x + w / 2.0, ccy, 10.0, outline=mix(bg, SHADOW, 0.55), ow=1.0)


def main():
    log = []
    outs = []
    for tag, state, cap in (
        ("A", STATE_A, "状态 A · 衫斯真实数据 —— 只装了「饰品」，另 3 槽空着（槽内写类型名，一眼看出缺哪格）"),
        ("B", STATE_B, "状态 B · 四槽全满 —— 每槽一件、按品级色描边（SR 金 / R 铜）；槽就是个迷你卡面：名字条 + 细线 + 图标"),
    ):
        im, B = r1_equip_top(state)
        n, rep = overlap_report("R1改v2-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    W = PW + 68

    # 拼板（1x 真实大小 → 一律用 Fs）
    H = 132 + (PH + CAP_H + GAP) * 2 + 30
    sh = Image.new("RGB", (W, H), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 16), "R1 改 v2 · 装备槽移到「关闭」左边 · 去掉三个板块标题 · 标签贴最下方（1:1 真实大小）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 44), "① 顶部右：装备槽 ×4 紧贴关闭钮左缘（x181–546，86×84 竖方形；关闭 556–602 留 10px 间距）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 62), "② 不写「属性 / 标签 / 装备」三个字，改用细线分区  ③ 标签贴到面板最下方（胶囊 y360–386，底内缘线 y413）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 80), "槽 = 迷你卡面：名字条（满=装备名 / 空=类型名）+ 细线 + 图标，形制与卡面 B2 同源；名字放槽内是因为槽下那一条会被立绘吃掉",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 98), "⚠️ 代价：槽横排需 365×84px，必须占满顶部 → 立绘从 y104 起（340 → 300 高，缩 ~12%），否则 x392–546 会撞",
           font=f_s, fill=(226, 160, 120))
    y = 132
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((PW, PH), Image.LANCZOS), (34, y + CAP_H))
        y += PH + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v2_顶栏装备槽_两态.png")
    sh.save(p)
    print("写出", p, sh.size)

    # 区块边界图
    H2 = 100 + (PH + 34) * 2 + 20
    sh2 = Image.new("RGB", (W, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同上两态 · 区块边界图（每个彩框 = 一个内容区块，两两不相交 = 零遮挡）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 副标 / 4 槽 / 4 属性 / 描述 / 标签 / 关闭 = 13 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "槽横跨 x372 竖分割线之上 → 竖分割线已下移到 y104 才开始，避免穿过槽",
            font=f_s, fill=(206, 186, 150))
    y2 = 100
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((PW, PH), Image.LANCZOS), (34, y2))
        y2 += PH + 34
    p2 = os.path.join(REF, "面板R1改v2_顶栏装备槽_两态_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v2_状态%s_1x.png" % tag)
        im.resize((PW, PH), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 与上一版（装备在左栏、带三个板块标题）对照 ----
    prev = os.path.join(REF, "面板R1改_装备槽_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        H5 = 118 + (PH + CAP_H + 34) * 2 + 26
        sh5 = Image.new("RGB", (W, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "上一版 → 这一版（同一份数据：四槽全满）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "上一版：装备槽在左栏（y258）、左栏顶部有「属 性 / 标 签 / 装 备」三个标题、标签在中间、立绘满高 340",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "这一版：槽上提到顶栏、「关闭」左边｜三个标题全部去掉，改用细线｜标签贴最下方｜立绘让位到 304",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 80), "两版都经零重叠断言（上一版 21 块 / 这一版 13 块，均 0 对重叠）",
                font=f_s, fill=(150, 172, 138))
        y5 = 118
        d5.text((34, y5), "上一版", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += PH + CAP_H + 34
        d5.text((34, y5), "这一版（本轮）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[1][2].resize((PW, PH), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v2_与上一版对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_equip.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
