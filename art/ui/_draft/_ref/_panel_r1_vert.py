# -*- coding: utf-8 -*-
"""R1 改 v4 —— 按用户草图重排左栏：

  用户原话：**「左侧缩一点数值竖着放：属性名和数值放同一行如图所示，仅参考布局」**
  → ① 左栏收窄（竖分割线 x372 → **x300**）
     ② 属性从「一行四格（名在上、值在下 + 刻度条在下）」改成 **4 行竖排，每行「属性名 + 数值」同一行**
     ③ 刻度条跟在同一行右侧（草图没画，但它是既有元素且仍在待拍板 → **附一张「无刻度条」对照**让你挑）

  ⚠️ 左栏腾出的横向空间**不能把立绘放大** —— 立绘 1088×1920 是竖长图，在 340 高的框里
     **永远是高度受限**（宽最多 193）。所以立绘位置与尺寸**一个像素都没动**：
     框从 x392 起放宽到 x300 起，但立绘仍**右对齐**在 x423–616（`ax = px1 − pw` 保证）。

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_vert.py
"""
import os
import sys

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)
import _panel_redesign as pr      # noqa: E402
import _panel_r1_fan as pf        # noqa: E402  （v3 的扇形绘制与几何从这里复用）

from PIL import Image, ImageDraw  # noqa: E402

S, F, Fs, tw, wrap, mix = pr.S, pr.F, pr.Fs, pr.tw, pr.wrap, pr.mix
BODY, BRASS, BRASS_LT, INK_TEXT, SHADOW = (
    pr.BODY, pr.BRASS, pr.BRASS_LT, pr.INK_TEXT, pr.SHADOW)
SUB_TEXT = pr.SUB_TEXT
base_bg, frame, rule, gold_rule = pr.base_bg, pr.frame, pr.rule, pr.gold_rule
portrait_fit, place, close_btn = pr.portrait_fit, pr.place, pr.close_btn
overlap_report, draw_debug_rects = pr.overlap_report, pr.draw_debug_rects
PW, PH = pr.PW, pr.PH
NAME, SUB, DESC, ATTRS, TAGS = pr.NAME, pr.SUB, pr.DESC, pr.ATTRS, pr.TAGS
tier_col = pr.tier_col

SLOTS3 = pf.SLOTS3
draw_equip_fan = pf.draw_equip_fan
tbox = pf.tbox
STATE_A, STATE_B = pf.STATE_A, pf.STATE_B

DIV_X = 300          # 竖分割线（原 372 → 左移 72）
PX1 = 616            # 立绘框右界（不变）
ATTR_Y0, ATTR_DY = 110, 25   # 属性 4 行的首行 y 与行距


def r1_vert(state, meters=True):
    w, h = PW, PH
    im = base_bg(w, h)
    frame(im, w, h, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    # ---- 立绘：框左界跟分割线左移到 x300 ----
    # ⚠️ 左栏一缩，立绘若继续**贴右**，会在「分割线(x300) ↔ 立绘(原 x423)」之间留下
    #   123px 的空带（看上去像漏了东西）。所以立绘改为在右侧区域内**居中**：
    #   框 300..616（316 宽）→ 立绘 x361..554，左右各留 61px，与「右内缘 618」也基本等距。
    #   尺寸仍是 193×340（未变）—— 1088×1920 的竖长图在 340 高的框里永远高度受限。
    px0, py0, px1, py1 = DIV_X, 64, PX1, 404
    pt = portrait_fit(px1 - px0, py1 - py0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = px0 + (px1 - px0 - pw) // 2, py1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    f_name, f_sub, f_val, f_attr, f_body = F(27, True), F(12), F(17, True), F(13), F(13)
    f_eq_t, f_eq_n = F(10), F(11)

    # ---- 名字 / 副标 / 金线 ----
    d.text((S(40), S(24)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, 40, 24, NAME, f_name)
    d.text((S(42), S(66)), SUB, font=f_sub, fill=BRASS)
    B["sub"] = tbox(d, 42, 66, SUB, f_sub)
    gold_rule(d, 40, 288, 96)

    # ---- ★★ 属性：4 行竖排，**属性名 + 数值同一行**（本轮的改动点）----
    for i, (k, v) in enumerate(ATTRS):
        ry = ATTR_Y0 + i * ATTR_DY
        col = tier_col(v)
        d.text((S(40), S(ry + 3)), k, font=f_attr, fill=SUB_TEXT)     # 属性名
        d.text((S(76), S(ry)), str(v), font=f_val, fill=col)          # 数值
        if meters:
            pr.meter(d, 100, ry + 11, 140, v, col)                    # 刻度条（可选）
        B["attr_%d" % i] = (40, ry, 240 if meters else 90, ry + ATTR_DY)

    # ---- 装备名 3 行（卡片在立绘上方，名字留在左栏；与扇形同序）----
    emax = 40
    for i, (cls, cn) in enumerate(SLOTS3):
        ly = 232 + i * 17
        nm = state.get(cls)
        d.text((S(40), S(ly)), cn, font=f_eq_t, fill=(INK_TEXT if nm else mix(BODY, SHADOW, 0.9)))
        val = nm if nm else "— 空"
        d.text((S(68), S(ly - 1)), val, font=f_eq_n,
               fill=(INK_TEXT if nm else mix(BODY, SHADOW, 0.8)))
        emax = max(emax,
                   tbox(d, 40, ly, cn, f_eq_t)[2],
                   tbox(d, 68, ly - 1, val, f_eq_n)[2])
    B["equip_names"] = (40, 232, emax, 232 + 2 * 17 + 15)

    # ---- 描述（细线分隔，无板块标题）----
    rule(d, 40, 298, DIV_X - 14, 298, a=0.35)
    yy = 306
    dmax = 40
    for ln in wrap(d, DESC, f_body, S(252)):
        d.text((S(40), S(yy)), ln, font=f_body, fill=mix(BODY, INK_TEXT, 0.72))
        dmax = max(dmax, tbox(d, 40, yy, ln, f_body)[2])
        yy += 20
    B["desc"] = (40, 306, dmax, yy)

    # ---- 标签：贴最下方 ----
    rule(d, 40, 346, DIV_X - 14, 346, a=0.3)
    tx = 40
    for s in TAGS:
        bw = int(tw(d, s, f_body) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(352), S(tx + bw), S(378)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(356)), s, font=f_body, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (40, 352, tx, 378)

    # ---- 竖分割线（左移到 x300）----
    rule(d, DIV_X, 34, DIV_X, 400, a=0.5)

    # ---- 装备扇形（与 v3 完全同一套绘制与几何：x424–546 / y4–62，严格在立绘上方）----
    draw_equip_fan(im, d, state, B)

    close_btn(d, 556, 20, 602, 50)
    B["close"] = (556, 20, 602, 50)
    return im, B


def main():
    log, outs = [], []
    for tag, state, meters, cap in (
        ("B", STATE_B, False, "★ 推荐 · 状态 B（三槽全满）· 属性 4 行竖排 = 属性名 + 数值同一行，行内不加任何附加元素（最贴草图）"),
        ("A", STATE_A, False, "状态 A · 衫斯真实数据（只装饰品）· 武器 / 防具 是空槽，与扇形同序"),
        ("C", STATE_B, True, "对照 · 属性行加回刻度条 —— 多一层「10 = 人类极限 / 中位 5 = 正常人」的可读刻度，代价是左栏变重"),
    ):
        im, B = r1_vert(state, meters=meters)
        n, rep = overlap_report("R1改v4-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    W = PW + 68
    H = 172 + (PH + CAP_H + GAP) * 3 + 30
    sh = Image.new("RGB", (W, H), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "R1 改 v4 · 左栏收窄 + 属性竖排单行（属性名 + 数值同一行）（1:1）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 42), "① 竖分割线 x372 → 300，左栏内容区收成 x40–290（面板占比 58.7% → 47.3%）",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 60), "② 属性：原来一行四格（名在上、值在下、刻度条在下）→ 现在 4 行竖排，每行「智力 8」",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 78), "③ 属性行内不加附加元素（最贴草图）；强弱靠数值颜色分档（≥7 铜金 / 4-6 深墨 / ≤3 灰褐）· 第 3 张是对照、试加回刻度条",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 96), "★ 立绘：框左界跟分割线放宽到 x300；左栏变窄后贴右会留 123px 空带 → 立绘改为「右侧区域内居中」",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 114), "   立绘 x361–554（左右各 61px）、尺寸仍 193×340 —— 1088×1920 竖长图在 340 高的框里永远高度受限，放不大",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 130), "装备扇形也不动：x424–546 / y4–62，完整落在立绘 x361–554 之内、且 y 方向差 2px → 不压立绘",
           font=f_s, fill=(206, 186, 150))
    d.text((16, 146), "※ 名字 / 副标 / 金线 / 装备名 3 行 / 描述 / 标签贴底 全部保留，信息一个没少",
           font=f_s, fill=(206, 186, 150))
    y = 172
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((PW, PH), Image.LANCZOS), (34, y + CAP_H))
        y += PH + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v4_左栏收窄_属性竖排.png")
    sh.save(p)
    print("写出", p, sh.size)

    # ---- 区块边界图 ----
    H2 = 118 + (PH + 34) * 3 + 20
    sh2 = Image.new("RGB", (W, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同三态 · 区块边界图（每个彩框 = 一个区块；两两不相交 = 零遮挡）",
            font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 副标 / 4 个属性行 / 装备名 3 行 / 描述 / 标签 / 装备扇形组 / 关闭 = 12 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "属性 4 行相邻只「相接」不「相交」（差 0px）→ 断言不算重叠；文本仍用实测 bbox（tbox）登记",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 80), "重点：扇形组 x424–546 完整落在立绘 x361–554 之内，且 y 方向差 2px → 装备不压立绘",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 98), "※ 若把属性行登记成「手填矩形」而不是实测 bbox，数值那种窄文本会被算宽 → 断言就失效（v7 踩过）",
            font=f_s, fill=(206, 186, 150))
    y2 = 118
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((PW, PH), Image.LANCZOS), (34, y2))
        y2 += PH + 34
    p2 = os.path.join(REF, "面板R1改v4_左栏收窄_属性竖排_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v4_状态%s_1x.png" % tag)
        im.resize((PW, PH), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 放大验左栏（3x）----
    imB = outs[0][2]
    Z = 3
    col = imB.crop((S(30), S(90), S(300), S(390))).resize((270 * Z, 300 * Z), Image.LANCZOS)
    band = imB.crop((S(392), S(0), S(616), S(70))).resize((224 * 3, 70 * 3), Image.LANCZOS)
    W3 = col.width + band.width + 34 * 3
    H3 = 92 + max(col.height, band.height) + 30
    sh3 = Image.new("RGB", (W3, H3), (42, 39, 35))
    d3 = ImageDraw.Draw(sh3)
    d3.text((16, 16), "左栏 3x 放大（状态 B · 属性竖排单行）", font=Fs(17, True), fill=(240, 232, 214))
    d3.text((16, 44), "每行 = 属性名 + 数值（同一行）；强弱靠数值颜色分档 —— 智力 8 铜金 / 魅力 5·体魄 4 深墨 / 力量 3 灰褐",
            font=f_s, fill=(206, 186, 150))
    d3.text((16, 62), "右侧为装备扇形 3x 放大（与 v3 一致，未改动）",
            font=f_s, fill=(206, 186, 150))
    sh3.paste(col, (34, 92))
    sh3.paste(band, (34 + col.width + 34, 92))
    p3 = os.path.join(REF, "面板R1改v4_左栏_放大3x.png")
    sh3.save(p3)
    print("写出", p3, sh3.size)

    # ---- 与 v3 对照 ----
    prev = os.path.join(REF, "面板R1改v3_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        H5 = 150 + (PH + CAP_H + 34) * 2 + 26
        sh5 = Image.new("RGB", (W, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "v3 → v4（同一份数据：三槽全满）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "v3：属性一行四格横排（名在上、值在下、刻度条在下），左栏占 58.7% 宽", font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "v4：属性 4 行竖排、每行「属性名 + 数值」，左栏收成 47.3% 宽、分割线左移 72px，立绘由贴右改居中", font=f_s, fill=(206, 186, 150))
        d5.text((16, 80), "装备扇形 / 装备名 / 描述 / 标签贴底 两版一致（只动左栏属性块排法 + 立绘水平位置）", font=f_s, fill=(206, 186, 150))
        d5.text((16, 98), "v3 断言 12 块 0 对；v4 断言 12 块 0 对", font=f_s, fill=(150, 172, 138))
        y5 = 150
        d5.text((34, y5), "v3（上一版 · 属性一行四格横排）", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += PH + CAP_H + 34
        d5.text((34, y5), "v4（本轮 · 属性竖排单行）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[0][2].resize((PW, PH), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v4_与v3对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_vert.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
