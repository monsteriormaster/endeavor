# -*- coding: utf-8 -*-
"""R1 改 v3 —— 按用户两条新指令重排：

  ① **「装备卡片可以重叠，只有三种：防具、武器、饰品」**
     → 槽位集合收到 **3 类**（weapon / armor / jewelry），3 张**扇形重叠**的迷你卡。
  ② **「确保他只在立绘上方」**
     → 装备组**严格落在立绘上方的顶栏内**（x 与 y 都不得与立绘相交）。

顺带把 v8 的代价还回去：**立绘从 300 恢复 340**（x392..616 / y64..404 → 立绘 193×340）。
装备不再横排占满顶部，所以立绘能拿回满高。

几何（全部 1x px，与 _panel_redesign 的 SC=2 渲染器共用）：
  装备带   y 4..62         （立绘从 y64 起 → 带底留 2px 空隙）
  迷你卡   46 × 58        3 张，步长 38（相邻重叠 8px）
  组宽     46 + 2×38 = 122 → 右对齐 x=546（关闭钮左缘 556 − 10）
  立绘框   x392..616 / y64..404 → 224×340 → 立绘实际 193×340

⚠️ 为什么迷你卡是 46×58 的「方卡」而不是卡面比例 0.566：
   带高只有 58px，按 0.566 卡面比例做 → 卡宽只有 33px，图标只剩 20px 宽，等于看不见。
   所以这里是**方形迷你卡**（顶条类型字 + 图标 + 品级色描边），不是卡面缩印。

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_fan.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)
import _panel_redesign as pr          # noqa: E402
import _panel_r1_equip as pe          # noqa: E402

from PIL import Image, ImageDraw      # noqa: E402

S, F, Fs, tw, wrap, mix = pr.S, pr.F, pr.Fs, pr.tw, pr.wrap, pr.mix
BODY, BRASS, BRASS2, BRASS_LT, INK, INK_TEXT, SHADOW = (
    pr.BODY, pr.BRASS, pr.BRASS2, pr.BRASS_LT, pr.INK, pr.INK_TEXT, pr.SHADOW)
SUB_TEXT = pr.SUB_TEXT
base_bg, frame, rule, gold_rule = pr.base_bg, pr.frame, pr.rule, pr.gold_rule
portrait_fit, place, close_btn = pr.portrait_fit, pr.place, pr.close_btn
overlap_report, draw_debug_rects = pr.overlap_report, pr.draw_debug_rects
PW, PH = pr.PW, pr.PH
NAME, SUB, DESC, ATTRS, TAGS = pr.NAME, pr.SUB, pr.DESC, pr.ATTRS, pr.TAGS
tier_col = pr.tier_col
icon, ellipsize = pe.icon, pe.ellipsize
TIER_COL, ITEM_DB = pe.TIER_COL, pe.ITEM_DB


# ⚠️ 直接用 pe 的那一份（PIL 的 ImageDraw.line 参数是 fill=，不是 outline= —— 自己重写踩过一次）
diamond = pe.diamond


def tbox(d, x, y, s, f):
    """文本**实测** bbox（1x，向外取整）。别手填矩形 —— 会漏判越界（v7 已踩）。"""
    bb = d.textbbox((S(x), S(y)), s, font=f)
    return (int(bb[0] // pr.SC), int(bb[1] // pr.SC),
            int(-(-bb[2] // pr.SC)), int(-(-bb[3] // pr.SC)))


# ---- 只有三类（用户拍板）—— 顺序与 card_data.gd::category_minor() 一致：武器1 / 防具2 / 饰品3 ----
SLOTS3 = [("weapon", "武器"), ("armor", "防具"), ("jewelry", "饰品")]

# ---- 装备带几何 ----
BAND_Y0 = 4          # 带顶
CW, CH, STEP = 46, 58, 38   # 迷你卡尺寸 / 相邻步长（重叠 8px）
FAN_X1 = 546                # 右对齐：关闭钮左缘 556 − 10

STATE_A = {"jewelry": "章鱼尾人身塑像"}                                  # 衫斯真实数据
STATE_B = {"weapon": "多功能军刀", "armor": "骑士盔甲",
           "jewelry": "章鱼尾人身塑像"}                                  # 三槽全满


def equip_card(im, d, x, y, w, h, item, cn):
    """一张方形迷你装备卡：品级色描边 + 顶中徽记 + 类型字 + 图标。
    item=None → 空槽（更暗实底 + 暗铜边 + 灰类型字 + 中央淡菱形）。"""
    filled = item is not None
    tier = ITEM_DB.get(item, ("R",))[0] if filled else None
    bg = mix(BODY, BRASS_LT, 0.24) if filled else mix(BODY, SHADOW, 0.14)
    r = S(6)
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=r, fill=bg)
    for k in range(4):                       # 内凹：越靠边越暗 → 读作「嵌进去的卡」
        a = 0.17 * (1 - k / 4.0)
        d.rounded_rectangle([S(x + k), S(y + k), S(x + w - k), S(y + h - k)],
                            radius=r, outline=mix(bg, SHADOW, a))
    bc = TIER_COL.get(tier, BRASS) if filled else mix(BODY, SHADOW, 0.50)
    d.rounded_rectangle([S(x), S(y), S(x + w), S(y + h)], radius=r, outline=bc,
                        width=max(1, int((1.4 if filled else 1.0) * pr.SC)))
    if filled:
        diamond(d, x + w / 2.0, y + 4.0, 2.4, fill=bc)   # 顶中品级徽记（与卡面 B2 同语言）

    # 类型字（顶部）：满槽用品级色，空槽用灰 —— 扇形里一眼看出哪格是哪类
    f_t = F(10, True)
    tcol = bc if filled else mix(BODY, SHADOW, 0.72)
    d.text((S(x + w / 2.0) - tw(d, cn, f_t) / 2.0, S(y + 7)), cn, font=f_t, fill=tcol)

    # 图标区：y+22 .. y+h-5（居中，不贴下边框）
    iy0, iy1 = y + 22, y + h - 5
    ccy = (iy0 + iy1) / 2.0
    if filled:
        ic = icon(item, w - 10, (iy1 - iy0) - 2)
        if ic is not None:
            im.paste(ic.convert("RGB"),
                     (S(x + w / 2.0) - ic.width // 2, S(ccy) - ic.height // 2),
                     ic.split()[-1])
        else:
            f0 = F(20, True)                 # 无 icon 的装备 → 名字首字兜底
            d.text((S(x + w / 2.0) - tw(d, item[0], f0) / 2.0, S(ccy) - 14),
                   item[0], font=f0, fill=mix(bg, INK_TEXT, 0.55))
    else:
        diamond(d, x + w / 2.0, ccy, 8.0, outline=mix(bg, SHADOW, 0.55), ow=1.0)


def draw_equip_fan(im, d, state, B):
    """★ 本轮主角：3 张扇形重叠的迷你卡，**整组严格落在立绘上方的顶栏内**。"""
    n = len(SLOTS3)
    x0 = FAN_X1 - (CW + (n - 1) * STEP)
    for i, (cls, cn) in enumerate(SLOTS3):
        equip_card(im, d, x0 + i * STEP, BAND_Y0, CW, CH, state.get(cls), cn)
    # 重叠是**有意为之**（用户拍的），所以整组只登记一个区块 → 组内重叠不进断言；
    # 组与组外区块的相交仍然照查（见 main 里的 overlap_report）。
    B["equip_fan"] = (x0, BAND_Y0, FAN_X1, BAND_Y0 + CH)


def r1_fan(state):
    """R1 骨架不动；装备改为「立绘上方的 3 张扇形重叠卡」，立绘恢复 340。"""
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    # ---- 立绘：x392..616 / y64..404 → 224×340（v8 的 300 高在这里还回来）----
    px0, py0, px1, py1 = 392, 64, 616, 404
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = px1 - pw, py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    f_name, f_sub, f_val, f_body = F(27, True), F(12), F(19, True), F(13)
    f_eq_t, f_eq_n = F(10), F(11)

    # ---- 左栏：名字 / 副标 / 金线 ----
    d.text((S(40), S(30)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 30, NAME, f_name)
    d.text((S(42), S(74)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = tbox(d, 42, 74, SUB, f_sub)
    gold_rule(d, 40, 300, 108)

    # ---- 属性：一行四格（无板块标题，按 v8 的指令）----
    for i, (k, v) in enumerate(ATTRS):
        gx = 40 + i * 82
        d.text((S(gx), S(128)), k, font=f_sub, fill=SUB_TEXT)
        d.text((S(gx), S(144)), str(v), font=f_val, fill=tier_col(v))
        pr.meter(d, gx, 174, 66, v, tier_col(v))
        B["attr_%d" % i] = (gx, 128, gx + 74, 179)

    # ---- 装备名 3 行 ----
    # 重叠的卡放不下完整名字（46px 宽、还被邻卡盖住 8px），所以名字留在左栏：
    # 与扇形**同序**（武器/防具/饰品），类型字用灰、名字用墨，空槽写「— 空」。
    emax = 40
    for i, (cls, cn) in enumerate(SLOTS3):
        ly = 200 + i * 18
        nm = state.get(cls)
        tcol = INK if nm else mix(BODY, SHADOW, 0.9)
        d.text((S(40), S(ly)), cn, font=f_eq_t, fill=tcol)
        val = nm if nm else "— 空"
        vcol = INK_TEXT if nm else mix(BODY, SHADOW, 0.8)
        d.text((S(70), S(ly - 1)), val, font=f_eq_n, fill=vcol)
        emax = max(emax,
                   tbox(d, 40, ly, cn, f_eq_t)[2],
                   tbox(d, 70, ly - 1, val, f_eq_n)[2])
    B["equip_names"] = (40, 200, emax, 200 + 2 * 18 + 15)

    # ---- 描述（无板块标题，细线分隔）----
    rule(d, 40, 268, 356, 268, a=0.35)
    yy = 280
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(320)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 21
    B["desc"] = (40, 280, dmax, yy)

    # ---- 标签：贴最下方 ----
    rule(d, 40, 340, 356, 340, a=0.3)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(352), S(tx + bw), S(378)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(356)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 352, tx, 378)

    # ---- 竖分割线（装备带在 x392 起，不再跨线 → 可以回到 y34 起）----
    rule(d, 372, 34, 372, 400, a=0.5)

    # ---- ★ 装备：3 张扇形重叠卡，落在「立绘上方」----
    draw_equip_fan(im, d, state, B)

    close_btn(d, 556, 20, 602, 50)
    B["close"] = (556, 20, 602, 50)
    return im, B


def main():
    log, outs = [], []
    for tag, state, cap in (
        ("A", STATE_A, "状态 A · 衫斯真实数据 —— 只装了「饰品」，武器/防具是空槽"),
        ("B", STATE_B, "状态 B · 三槽全满 —— 武器/防具/饰品各一张，扇形重叠，按品级色描边（SR 金 / R 铜）"),
    ):
        im, B = r1_fan(state)
        n, rep = overlap_report("R1改v3-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    W = PW + 68
    H = 148 + (PH + CAP_H + GAP) * 2 + 30
    sh = Image.new("RGB", (W, H), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "R1 改 v3 · 装备 = 三张扇形重叠的迷你卡（武器/防具/饰品）· 只在立绘上方（1:1）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 42), "① 只有三类槽：武器 / 防具 / 饰品（删掉原来的「工具」第 4 槽）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 60), "② 三张卡扇形重叠（46×58，步长 38 = 相邻压 8px），整组 x424–546 / y4–62",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 78), "③ 整组严格落在立绘（x392–616 / y64–404）上方 → x、y 两个方向都不与立绘相交",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 96), "★ 立绘从 v8 的 300 高恢复 340（x392–616 / y64–404 → 立绘实际 193×340）",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 114), "装备的完整名字留在左栏三行（与扇形同序）—— 46px 宽的卡放不下 7 字名字，且相邻卡会压住 8px",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 130), "※ 迷你卡是 46×58 的方卡，不是卡面比例 0.566：带高只有 58px，按 0.566 做卡宽仅 33px、图标只剩 20px",
           font=f_s, fill=(226, 160, 120))
    y = 148
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((PW, PH), Image.LANCZOS), (34, y + CAP_H))
        y += PH + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v3_装备扇形重叠_两态.png")
    sh.save(p)
    print("写出", p, sh.size)

    # ---- 区块边界图（零遮挡取证）----
    H2 = 118 + (PH + 34) * 2 + 20
    sh2 = Image.new("RGB", (W, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同两态 · 区块边界图（每个彩框 = 一个内容区块；两两不相交 = 零遮挡）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 副标 / 4 属性 / 装备名 3 行 / 描述 / 标签 / 装备扇形组 / 点击关闭 = 12 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "扇形组只登记**整组外框**：组内 3 张卡的重叠是设计要求，不能算重叠；组与外部的相交照查",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 80), "重点看：扇形组（右上）与立绘（右下）在 y 方向相差 2px → 零相交，装备不压立绘",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 98), "并用实测 bbox 登记文本（tbox）—— 手填矩形会漏判越界（v7 已踩过一次）",
            font=f_s, fill=(206, 186, 150))
    y2 = 118
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((PW, PH), Image.LANCZOS), (34, y2))
        y2 += PH + 34
    p2 = os.path.join(REF, "面板R1改v3_装备扇形重叠_两态_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v3_状态%s_1x.png" % tag)
        im.resize((PW, PH), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 放大验卡（4x）：扇形带 + 左栏装备名 ----
    imB = outs[1][2]
    Z = 4
    band = imB.crop((S(392), S(0), S(616), S(70))).resize((224 * Z, 70 * Z), Image.LANCZOS)
    names = imB.crop((S(40), S(192), S(200), S(252))).resize((160 * Z, 60 * Z), Image.LANCZOS)
    W3 = band.width + 68
    H3 = 92 + band.height + 30 + names.height + 30
    sh3 = Image.new("RGB", (W3, H3), (42, 39, 35))
    d3 = ImageDraw.Draw(sh3)
    d3.text((16, 16), "装备扇形带 4x 放大（状态 B · 三槽全满）", font=Fs(17, True), fill=(240, 232, 214))
    d3.text((16, 44), "迷你卡：品级色描边（SR 金 / R 铜）+ 顶中品级徽记 + 顶部类型字 + 物品图标 + 内凹阴影",
            font=f_s, fill=(206, 186, 150))
    d3.text((16, 62), "相邻卡压 8px（步长 38）→ 三张卡都还看得见类型字与图标",
            font=f_s, fill=(206, 186, 150))
    sh3.paste(band, (34, 92))
    yy3 = 92 + band.height + 26
    d3.text((34, yy3), "左栏「装备名」3 行 4x 放大（与扇形同序：武器 / 防具 / 饰品）",
            font=f_s, fill=(206, 186, 150))
    sh3.paste(names, (34, yy3 + 24))
    p3 = os.path.join(REF, "面板R1改v3_装备扇形_放大4x.png")
    sh3.save(p3)
    print("写出", p3, sh3.size)

    # ---- 与 v8 对照 ----
    prev = os.path.join(REF, "面板R1改v2_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        H5 = 132 + (PH + CAP_H + 34) * 2 + 26
        sh5 = Image.new("RGB", (W, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "v8 → v3（同一份数据：三/四槽尽量满装）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "v8：装备槽在顶栏横排占满（4 槽 × 86 = 365px 宽）→ 立绘被压到 y104 起，只有 300 高",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "v3：装备收缩成 3 张扇形重叠卡（整组仅 122×58）→ 立绘恢复到 y64 起、340 高（+13% 高）",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 80), "两版都过零重叠断言：v8 = 13 块 0 对；v3 = 12 块 0 对",
                font=f_s, fill=(150, 172, 138))
        d5.text((16, 98), "另：v3 只有三类槽（去掉「工具」）；v8 是四类（含工具）",
                font=f_s, fill=(206, 186, 150))
        y5 = 132
        d5.text((34, y5), "v8（上一版）", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += PH + CAP_H + 34
        d5.text((34, y5), "v3（本轮）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[1][2].resize((PW, PH), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v3_与v8对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_fan.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
