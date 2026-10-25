# -*- coding: utf-8 -*-
"""R1 改 v8 —— 按「苏丹为什么自然」的**实测诊断**重做。

诊断来自 `_sudan_rows.py`（量化）+ `sudan_放大_人物面板3.png`（3x 目读），
全部有据可查，不凭印象：

  A. 苏丹属性行的横向元素只剩 x430–571（图标框 / 名称 / 数字），
     而它的左栏宽约 1050px → **内容只占左 18%，右边全是空**。
     ⚠ 反直觉：**「没排满」不是病根**。本作其实已经是「苏丹式左靠」。
  B. 真正的病根是三条：
     B1「分区名 + 通栏细线」把留白**框住了**（属性 —— / 标签 ——）
        本作你已明确要求不写这三个板块标题 → 改用**金色装饰分隔线**（菱形收尾）替代，
        只保留"框住"的语法，不留字。
     B2 一区一行、行距极大（苏丹一个属性独享 ~310px 区块，行本身才 38px）
        本作 4 行挤在 184px（每行 46px）→ 疏密差 6.7 倍。收到 3.4 倍。
     B3 底色是**材质**（深皮革）不是纯色米面
        本作加**零均值纸纹**（细颗粒 + 低频斑 + 纸纤维），空白读作"纸"而不是"没画"。
  C. 立绘占面板高约 80% 且出血到边；本作 67% → 加大到 204×360、底边贴 y500。

⚠ 本版**故意没做**的两件事（等拍板，不擅自加）：
  · 属性刻度条（meter）—— 老待办「属性刻度条要不要」还没定
  · 立绘贴右出血 —— 现仍居中，贴右会让左侧空出 112px 反而更空

本脚本只读素材 + 出图，**不碰任何游戏文件**。
  C:/Users/26464/miniconda3/python.exe art/ui/_draft/_ref/_panel_r1_v8.py
"""
import os
import sys

import numpy as np

R = r"C:\Users\26464\IdeaProjects\endeavor"
REF = os.path.join(R, "art", "ui", "_draft", "_ref")
sys.path.insert(0, REF)
import _panel_redesign as pr      # noqa: E402
import _panel_r1_fan as pf        # noqa: E402

from PIL import Image, ImageDraw  # noqa: E402

S, F, Fs, tw, wrap, mix = pr.S, pr.F, pr.Fs, pr.tw, pr.wrap, pr.mix
BODY, BRASS, BRASS2, BRASS_LT, INK, INK_TEXT, SHADOW = (
    pr.BODY, pr.BRASS, pr.BRASS2, pr.BRASS_LT, pr.INK, pr.INK_TEXT, pr.SHADOW)
SUB_TEXT = pr.SUB_TEXT
frame, rule, gold_rule = pr.frame, pr.rule, pr.gold_rule
portrait_fit, place = pr.portrait_fit, pr.place
overlap_report, draw_debug_rects = pr.overlap_report, pr.draw_debug_rects
NAME, DESC, ATTRS, TAGS = pr.NAME, pr.DESC, pr.ATTRS, pr.TAGS
tier_col = pr.tier_col
icon, ellipsize, tbox = pf.icon, pf.ellipsize, pf.tbox
SLOTS3, STATE_A, STATE_B = pf.SLOTS3, pf.STATE_A, pf.STATE_B
diamond = pf.diamond

# ============ 几何（全部 1x px） ============
W, H = 634, 520
DIV_X = 300
PX0, PY0, PX1, PY1 = 300, 140, 616, 500      # 立绘框 316×360 → 立绘 204×360（C：底边贴 y500）

BAND_Y0 = 28                                 # 装备卡顶（离最外框线 9px，v7 定的）
CW, CH, STEP = 60, 106, 56
FAN_X1 = 540
CLOSE = (558, 30, 610, 56)                   # 关闭在面板内部
CLOSE_FILL = 0.20
NAME_STRIP = STEP                            # 卡上文字只能占用「露出来的那一条」

NAME_Y = 30
GOLD_Y = 96                                  # B1：名字区结束的金色装饰线

ATTR_C0, ATTR_PITCH = 136, 66                # B2：行距 52 → 66；4 行中心 136/202/268/334
ATTR_BOX = 26                                # 属性铭牌边长（苏丹是 22px；32 太大读成"空盒"）
ATTR_BX = 40                                 # 左轴（和苏丹一样：所有东西挂同一条左轴）
ATTR_NAME_X = 76
ATTR_VAL_X = 142                             # 数值列固定 x（苏丹也是固定 x 的数值列）
ATTR_R = 286                                 # 左栏内容右缘（DIV_X 300 − 14）

DESC_RULE_Y, DESC_Y = 374, 386               # B1：属性区结束的金色装饰线
TAGS_RULE_Y, TAGS_Y = 440, 452               # 描述/标签之间只留极淡细线（次要分区）

CARD_TEX = os.path.join(R, "art", "card.png")
_cf = {}


# ============================================================
#  B3 —— 零均值纸纹
# ============================================================
def bg_base(w, h):
    """干净骨面 + 纵向渐变。

    ⚠ 不复用 `pr.base_bg`：它只在**偶数行**画渐变（`if y % 2 == 0`），
    SC=2 下会在 1x 缩图后留下**细横条**（3x 放大一眼看到），读作"线噪"而不是"纸"。
    """
    im = Image.new("RGB", (S(w), S(h)), pr.BODY)
    d = ImageDraw.Draw(im)
    for y in range(S(h)):
        d.line([(0, y), (S(w), y)], fill=mix(pr.BODY_HI, pr.BODY_LO, y / float(S(h) - 1)))
    return im


def paper_grain(im, seed=7):
    """细颗粒 + 低频斑 + 纸纤维。**零均值** → 不改我们已经量定的纸色均值 242.9。

    ⚠ 坑：`np.asarray(Image.resize(...))` 拿到的是**只读视图**，`*=` 会报
    "output array is read-only"（本版第一次跑就死在这）→ 必须 `np.array()` 复制。
    """
    a = np.asarray(im).astype(np.float32)                     # astype 已复制 → 可写
    h, w = a.shape[:2]
    rng = np.random.default_rng(seed)
    fine = rng.normal(0.0, 7.0, (h, w))                       # 细颗粒（1x 下 ≈ ±3.5）
    ch, cw = h // 28 + 2, w // 28 + 2
    coarse = rng.normal(0.0, 1.0, (ch, cw)).astype(np.float32)
    coarse = np.array(Image.fromarray(coarse, mode="F").resize((w, h), Image.BICUBIC))
    coarse *= 2.2                                             # 低频斑（纸的厚薄不均）
    a = np.clip(a + (fine + coarse)[..., None], 0, 255).astype(np.uint8)
    out = Image.fromarray(a, "RGB")
    # 纸纤维：极淡短斜线。⚠ 不能太亮、不能太密 —— 亮/密了就变"划痕"，不是"纸"（3x 一眼看穿）
    dd = ImageDraw.Draw(out)
    fr = np.random.default_rng(seed + 1)
    for _ in range(int(w * h / 2600)):
        x = int(fr.integers(0, w))
        y = int(fr.integers(0, h))
        L = int(fr.integers(14, 46))
        ang = float(fr.uniform(-0.5, 0.5))
        dd.line([x, y, int(x + L * np.cos(ang)), int(y + L * np.sin(ang))],
                fill=(237, 229, 210) if fr.integers(0, 2) else (225, 216, 196), width=1)
    return out


# ============================================================
#  装备卡（真实卡面缩小；空槽不画）
# ============================================================
def card_face(w, h):
    if (w, h) not in _cf:
        _cf[(w, h)] = Image.open(CARD_TEX).convert("RGB").resize((S(w), S(h)), Image.LANCZOS)
    return _cf[(w, h)]


def draw_card_name(d, x, y, w, text, f, col):
    """卡上名字。

    ⚠ 两个坑（v5~v8 前几版全踩过）：
      1. 顺序必须是 **先折行、再逐行截断** —— 反了会把 5 字名先砍成「多功能…」再折行。
      2. 名字的可用宽度 = **露出来的那一条**（STEP），不是整张卡的宽 —— 卡是扇形重叠的，
         右邻卡会盖住右边的 (CW - STEP) px。按整卡宽居中 → 最后一个字被邻卡压掉（实测到了）。
         而且要对齐到「可见条」的中心，不然三张卡的名字左右不对齐。
    3. 折行是贪心的，会给出「多功能军 / 刀」这种 4+1 —— 只要超过 1 行就**手动对半劈**。
    """
    maxw = NAME_STRIP - 12
    lines = wrap(d, text, f, S(maxw))
    if len(lines) > 1:
        if len(lines) == 2:
            c = (len(text) + 1) // 2
            lines = [text[:c], text[c:]]
        else:
            lines = lines[:2]
            lines[-1] = ellipsize(d, lines[-1] + "…", f, maxw)
    lines = [ellipsize(d, ln, f, maxw) for ln in lines]
    lh = 13
    cx = x + NAME_STRIP / 2.0
    for i, ln in enumerate(lines):            # 顶对齐：三张卡的名字起于同一 y
        d.text((S(cx) - tw(d, ln, f) / 2.0, S(y + 9 + i * lh)), ln, font=f, fill=col)


def equip_card(im, d, x, y, w, h, item):
    """item is None → 一个像素都不画（用户：没有的装备就空着，不搞空卡牌）。"""
    if item is None:
        return
    sh = Image.new("RGBA", (S(w), S(h)), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([0, 0, S(w) - 1, S(h) - 1], radius=S(4),
                                         fill=(92, 74, 52, 66))
    im.paste(sh.convert("RGB"), (S(x) + S(1.6), S(y) + S(2.4)), sh.split()[-1])
    im.paste(card_face(w, h), (S(x), S(y)))
    draw_card_name(d, x, y + 5, w, item, F(10), INK_TEXT)
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


def close_btn_in(d, x0, y0, x1, y1, label="关闭"):
    """淡底 + 单道细铜边（v7 定的：双道铜边太强调，会突兀）。"""
    d.rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(6),
                        outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                        fill=mix(BODY, BRASS_LT, CLOSE_FILL))
    f = F(13)
    d.text((S((x0 + x1) / 2.0) - tw(d, label, f) / 2.0, S((y0 + y1) / 2.0) - 9),
           label, font=f, fill=INK_TEXT)


def attr_row(im, d, cy, k, v, with_meter=True):
    """一行属性 = [铜边属性铭牌] + [属性名] + [数值列 x178] +（可选）[刻度条]。

    对齐苏丹的行骨架 `[图标框]+[名称]+[数字]`，并且**全部左靠**（苏丹内容也只占栏宽 18%）。
    铭牌里放品级色菱形 —— 沿用本作既有的品级语言（tier_col：≥7 铜金 / 4-6 深墨 / ≤3 灰褐）。
    刻度条是**本作既有**的东西（原 R1/R2/R3 就有，5=常人 / 10=人类极限），这里把它放回行内，
    让右半段 x206–286 不再是空的 —— 不想要的话，一个开关就删（见板子上的 A/B 对照）。
    """
    col = tier_col(v)
    b = ATTR_BOX
    bx0, by0 = ATTR_BX, cy - b / 2.0
    d.rounded_rectangle([S(bx0), S(by0), S(bx0 + b), S(by0 + b)], radius=S(6),
                        fill=mix(BODY, BRASS_LT, 0.26), outline=col,
                        width=max(1, int(1.3 * pr.SC)))
    diamond(d, bx0 + b / 2.0, by0 + b / 2.0, 5.0, fill=mix(col, BODY, 0.16))
    f_a, f_v = F(14), F(22, True)
    d.text((S(ATTR_NAME_X), S(cy - 9)), k, font=f_a, fill=SUB_TEXT)
    d.text((S(ATTR_VAL_X), S(cy - 15)), str(v), font=f_v, fill=col)
    if with_meter:
        pr.meter(d, 176, cy - 2.5, 110, v, col)


# ============================================================
def r1_v8(state, with_meter=True, base=None, frame_on=True):
    """base = 给一张已经做好的底（SC 倍分辨率）；传了就**不再自造纸纹、也不画程序化边框**
    —— 用来把布局叠到游戏真实底图 `art/character_panel_bg.png` 上做验收。"""
    if base is None:
        bg = paper_grain(bg_base(W, H), seed=7)
    else:
        bg = base
    im = bg.copy()
    if frame_on:
        frame(im, W, H, crest=False)
    d = ImageDraw.Draw(im)
    B = {}

    f_name, f_desc, f_tag = F(27, True), F(12), F(13)

    # ---- 名字 + 金色装饰线（B1：用"线"框住留白，但**不写字**）----
    d.text((S(ATTR_BX), S(NAME_Y)), NAME, font=f_name, fill=INK_TEXT)
    B["name"] = tbox(d, ATTR_BX, NAME_Y, NAME, f_name)
    gold_rule(d, ATTR_BX, ATTR_R, GOLD_Y)

    # ---- 属性：4 行，行距 66（B2：疏密差 6.7x → 3.4x）----
    #      本版**故意不加行间细线**：加了会读成表格；靠"行骨架 + 留白 + 纸纹"替代。
    for i, (k, v) in enumerate(ATTRS):
        cy = ATTR_C0 + i * ATTR_PITCH
        attr_row(im, d, cy, k, v, with_meter)
        B["attr_%d" % i] = (ATTR_BX - 2, cy - 22, ATTR_R + 2, cy + 22)

    # ---- 描述（B1：属性区与描述区之间再来一道金色装饰线）----
    gold_rule(d, ATTR_BX, ATTR_R, DESC_RULE_Y)
    yy = DESC_Y
    dmax = ATTR_BX
    for ln in wrap(d, DESC, f_desc, S(ATTR_R - ATTR_BX)):
        d.text((S(ATTR_BX), S(yy)), ln, font=f_desc, fill=mix(BODY, INK_TEXT, 0.74))
        dmax = max(dmax, tbox(d, ATTR_BX, yy, ln, f_desc)[2])
        yy += 19
    B["desc"] = (ATTR_BX, DESC_Y, dmax, yy)

    # ---- 标签（次要分区 → 只留极淡细线，不用金色装饰）----
    rule(d, ATTR_BX, TAGS_RULE_Y, ATTR_R, TAGS_RULE_Y, a=0.30)
    tx = ATTR_BX
    tmax = TAGS_Y
    for s in TAGS:
        bw = int(tw(d, s, f_tag) / pr.SC) + 20
        d.rounded_rectangle([S(tx), S(TAGS_Y), S(tx + bw), S(TAGS_Y + 26)], radius=S(7),
                            outline=BRASS, width=max(1, int(1.2 * pr.SC)),
                            fill=mix(BODY, BRASS_LT, 0.22))
        d.text((S(tx + 10), S(TAGS_Y + 4)), s, font=f_tag, fill=INK_TEXT)
        tx += bw + 8
    B["tags"] = (ATTR_BX, TAGS_Y, tx, TAGS_Y + 26)

    rule(d, DIV_X, 30, DIV_X, PY1, a=0.5)

    # ---- 立绘：204×360，底边贴 y500（C：出血到内框线，右半不再留一圈空纸）----
    pt = portrait_fit(PX1 - PX0, PY1 - PY0, fade=("left", 26))
    pw, ph = pt.width // pr.SC, pt.height // pr.SC
    ax, ay = PX0 + (PX1 - PX0 - pw) // 2, PY1 - ph
    place(im, pt, S(ax), S(ay))
    B["portrait"] = (ax, ay, ax + pw, ay + ph)

    # ---- 装备：3 张真实卡面缩小的迷你卡，只在立绘上方；空槽不画 ----
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
    if drawn is not None:                 # 全空时**不登记**（不画的东西不能算区块）
        B["equip_fan"] = drawn

    close_btn_in(d, CLOSE[0], CLOSE[1], CLOSE[2], CLOSE[3])
    B["close"] = CLOSE
    return im, B


STATE_C = {}


def main():
    log, outs = [], []
    for tag, state, cap in (
        ("B", STATE_B, "★ 状态 B（三槽全满）—— 行距 66 + 金色装饰线分区 + 零均值纸纹 + 立绘 204×360"),
        ("A", STATE_A, "状态 A（只装饰品）"),
        ("C", STATE_C, "状态 C（三槽全空）"),
    ):
        im, B = r1_v8(state)
        n, rep = overlap_report("R1改v8-%s" % tag, B, ())
        log.append(rep)
        outs.append((tag, cap, im, B))

    # 纸纹是否改了均值（必须零均值）
    a0 = np.asarray(bg_base(W, H)).astype(np.float32)
    a1 = np.asarray(paper_grain(bg_base(W, H), 7)).astype(np.float32)
    log.append("纸纹校验：底色均值 %.2f → %.2f（Δ%+.2f，须≈0）；1x 局部 std ≈ %.2f（颗粒可见但不脏）"
               % (a0.mean(), a1.mean(), a1.mean() - a0.mean(), a1.std() / (2 * pr.SC)))

    f_t, f_s = Fs(15, True), Fs(12)
    CAP_H, GAP = 28, 30
    SW = W + 68
    H1 = 210 + (H + CAP_H + GAP) * 3 + 30
    sh = Image.new("RGB", (SW, H1), (42, 39, 35))
    d = ImageDraw.Draw(sh)
    d.text((16, 14), "R1 改 v8 · 按「苏丹为什么自然」的实测诊断重做（1:1）",
           font=Fs(17, True), fill=(240, 232, 214))
    d.text((16, 44), "先纠一条反直觉的实测：苏丹属性行内容也全缩在左边（x430–571 = 栏宽 18%），右边全是空",
           font=f_s, fill=(226, 160, 120))
    d.text((16, 62), "→ 所以「没排满」不是病根。本作一直是苏丹式的左靠，方向没错。",
           font=f_s, fill=(226, 160, 120))
    d.text((16, 86), "【B1】苏丹靠「分区名 + 通栏细线」把留白框住；你明确要求不写「属性/标签/装备」这三个词",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 104), "       → 本作改用金色装饰线（两端菱形收尾）替代，只留「框住」的语法，不留字",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 122), "【B2】苏丹一区一行、行距极大（一个属性独享 ~310px，行本身 38px）；本作 4 行只挤 184px",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 140), "       → 行距 52 → 66，疏密差从 6.7 倍收到 3.4 倍",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 158), "【B3】苏丹底是材质（深皮革）；本作是纯色米面 → 加零均值纸纹（细颗粒 + 低频斑 + 纸纤维）",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 176), "【C】 立绘占面板高：苏丹约 80% / 本作 67% → 194×342 加大到 204×360，底边贴 y500",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 198), "【D】 行内把「数值列 x178 + 刻度条 x206–286」补齐 —— 右半段不再是空的（5 = 常人 / 10 = 人类极限）",
           font=f_s, fill=(150, 200, 150))
    d.text((16, 216), "      刻度条是本作原有的东西（原 R1/R2/R3 就有），不想要的话一句话删掉 —— 见对照板",
           font=f_s, fill=(226, 160, 120))
    y = 242
    for tag, cap, im, B in outs:
        d.text((34, y), cap, font=f_t, fill=(226, 210, 180))
        sh.paste(im.resize((W, H), Image.LANCZOS), (34, y + CAP_H))
        y += H + CAP_H + GAP
    p = os.path.join(REF, "面板R1改v8_按苏丹诊断重做_三态.png")
    sh.save(p)
    print("写出", p, sh.size)

    # ---- 行内细节 A/B：带刻度条 / 不带刻度条（一个开关就能删）----
    im_no = r1_v8(STATE_B, with_meter=False)[0]
    box = (S(26), S(104), S(312), S(368))
    cw_, ch_ = box[2] - box[0], box[3] - box[1]
    Z = 3
    za = outs[0][2].crop(box).resize((cw_ * Z, ch_ * Z), Image.LANCZOS)
    zb = im_no.crop(box).resize((cw_ * Z, ch_ * Z), Image.LANCZOS)
    SH_W = cw_ * Z + 68
    H6 = 106 + (ch_ * Z + 34) * 2 + 24
    sh6 = Image.new("RGB", (SH_W, H6), (42, 39, 35))
    d6 = ImageDraw.Draw(sh6)
    d6.text((16, 14), "行内细节 A/B（同一栏 3x 放大）：刻度条要不要", font=Fs(17, True), fill=(240, 232, 214))
    d6.text((16, 42), "上面 A = 带刻度条（本版默认）｜下面 B = 不带刻度条，删掉后 x206–286 这一段是空的",
            font=f_s, fill=(206, 186, 150))
    d6.text((16, 60), "刻度条不是新发明：原 R1/R2/R3 就有，5 = 常人 / 10 = 人类极限，底槽 + 中位刻度线都给标度感",
            font=f_s, fill=(206, 186, 150))
    d6.text((16, 78), "两种都是「铭牌 + 名称 + 数值列」同一套骨架，只差右边那一段",
            font=f_s, fill=(150, 200, 150))
    y6 = 106
    d6.text((34, y6), "A · 带刻度条", font=f_t, fill=(226, 210, 180))
    sh6.paste(za, (34, y6 + 26))
    y6 += ch_ * Z + 34
    d6.text((34, y6), "B · 不带刻度条", font=f_t, fill=(226, 210, 180))
    sh6.paste(zb, (34, y6 + 26))
    p6 = os.path.join(REF, "面板R1改v8_行内细节_刻度条AB.png")
    sh6.save(p6)
    print("写出", p6, sh6.size)

    H2 = 150 + (H + 34) * 3 + 20
    sh2 = Image.new("RGB", (SW, H2), (42, 39, 35))
    d2 = ImageDraw.Draw(sh2)
    d2.text((16, 16), "同三态 · 区块边界图（两两不相交 = 零遮挡）", font=Fs(17, True), fill=(240, 232, 214))
    d2.text((16, 44), "区块：名字 / 4 个属性行 / 描述 / 标签 / 装备组 / 关闭 / 立绘 —— 满装 10 块，三槽全空 9 块",
            font=f_s, fill=(206, 186, 150))
    d2.text((16, 62), "装备组下缘 y134 vs 立绘上缘 y140（差 6px）；装备组右缘 x540 vs 关闭左缘 x558（差 18px）",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 80), "关闭矩形 x558–610 落在右内框线（约 x615）之内 —— 不再骑边框",
            font=f_s, fill=(150, 200, 150))
    d2.text((16, 98), "文本一律用实测 bbox（tbox）登记，不手填矩形（手填会漏判越界）",
            font=f_s, fill=(206, 186, 150))
    y2 = 150
    for tag, cap, im, B in outs:
        sh2.paste(draw_debug_rects(im, B).resize((W, H), Image.LANCZOS), (34, y2))
        y2 += H + 34
    p2 = os.path.join(REF, "面板R1改v8_按苏丹诊断重做_三态_区块边界.png")
    sh2.save(p2)
    print("写出", p2, sh2.size)

    for tag, cap, im, B in outs:
        q = os.path.join(REF, "面板R1改v8_状态%s_1x.png" % tag)
        im.resize((W, H), Image.LANCZOS).save(q)
        print("写出", q)

    # ---- 放大：左栏属性区 3x（看行骨架、金色装饰线、纸纹）----
    imB = outs[0][2]
    Z = 3
    col = imB.crop((S(26), S(86), S(306), S(392))).resize((280 * Z, 306 * Z), Image.LANCZOS)
    d3 = ImageDraw.Draw(col)
    d3.rectangle([0, 0, col.width, 34], fill=(52, 46, 38))
    d3.text((10, 8), "v8 左栏 3x：铭牌行骨架 + 金色装饰线分区 + 零均值纸纹",
            font=Fs(15, True), fill=(255, 236, 176))
    p3 = os.path.join(REF, "面板R1改v8_左栏_放大3x.png")
    col.save(p3)
    print("写出", p3, col.size)

    # ---- 放大：右半顶部（装备卡 + 立绘起头）2x ----
    top = imB.crop((S(290), S(14), S(626), S(268))).resize((336 * 2, 254 * 2), Image.LANCZOS)
    d4 = ImageDraw.Draw(top)
    d4.rectangle([0, 0, top.width, 34], fill=(52, 46, 38))
    d4.text((10, 8), "v8 右半顶部 2x：3 张真实卡面迷你卡 + 关闭 + 立绘（贴 y500 出血）",
            font=Fs(15, True), fill=(255, 236, 176))
    p4 = os.path.join(REF, "面板R1改v8_右半顶部_放大2x.png")
    top.save(p4)
    print("写出", p4, top.size)

    # ---- 与 v7 对照（同宽竖排）----
    prev = os.path.join(REF, "面板R1改v7_状态B_1x.png")
    if os.path.exists(prev):
        pv = Image.open(prev).convert("RGB")
        H5 = 172 + (pv.height + CAP_H + 34) + (H + CAP_H + 34) + 26
        sh5 = Image.new("RGB", (SW, H5), (42, 39, 35))
        d5 = ImageDraw.Draw(sh5)
        d5.text((16, 16), "v7 → v8（同一份数据 · 都过零重叠断言）", font=Fs(17, True), fill=(240, 232, 214))
        d5.text((16, 44), "v7：属性 4 行纯文本、行距 52、无分区线、四周平涂米色；立绘 194×342（占面板高 67%）",
                font=f_s, fill=(206, 186, 150))
        d5.text((16, 62), "v8：每行有骨架（铜边铭牌 + 名称 + 数值列）、行距 66、两道金色装饰线分区；",
                font=f_s, fill=(150, 200, 150))
        d5.text((16, 80), "       纸面加零均值纸纹；立绘 204×360（69%）、底边贴 y500",
                font=f_s, fill=(150, 200, 150))
        d5.text((16, 98), "※ 本版故意不加「行间细线」—— 加了会读成表格；分区靠两道金色装饰线 + 留白 + 材质",
                font=f_s, fill=(226, 160, 120))
        y5 = 172
        d5.text((34, y5), "v7（面板 510 高）", font=f_t, fill=(226, 210, 180))
        sh5.paste(pv, (34, y5 + CAP_H))
        y5 += pv.height + CAP_H + 34
        d5.text((34, y5), "v8（面板 520 高）", font=f_t, fill=(226, 210, 180))
        sh5.paste(outs[0][2].resize((W, H), Image.LANCZOS), (34, y5 + CAP_H))
        p5 = os.path.join(REF, "面板R1改v8_与v7对照.png")
        sh5.save(p5)
        print("写出", p5, sh5.size)

    print("\n".join(log))
    with open(os.path.join(REF, "_panel_r1_v8.log"), "w", encoding="utf-8") as f:
        f.write("\n".join(log) + "\n")


if __name__ == "__main__":
    main()
