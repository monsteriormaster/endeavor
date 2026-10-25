extends Control
## ⚠️ **本脚本已被取代（2026-10-13），目前没有被任何场景挂载 —— 留档，不要照它改。**
##
## 它画的是旧版（850×700 + 整张纸底图）的装饰：金饰分隔线 / 竖分割线 /
## 属性行铭牌·菱形·刻度条。2026-10-13 面板改成「卡牌版」后：
##   · 金线、竖线、刻度条、铭牌**全部撤销**（用户口径：「把不明所以的线条去掉」）；
##   · 属性图标改为**烤进** `art/ui/character_panel_card_bg.png` 的印章；
##   · 品级色函数 `tier_col()` 已复制到 `components/character_panel.gd::_val_col()`
##     （那边还按「金=高 / 褐=中 / 灰=低」保留色相，只把亮度压到纸上能读的区间）。
## 旧规格脚本 `art/ui/_draft/_ref/_panel_final_layout.py` 同样已标注为历史留存。
##
## 现状：`components/character_panel.tscn` 里**没有** `deco` 节点。
## 将来若要重新启用运行时绘制的装饰层，再把它挂回去。
##
## ---------------------------------------------------------------------------
## 人物面板的**装饰层**：只画形状 —— 金饰分隔线 / 竖分割线 / 属性行铭牌·菱形·刻度条。
##
## 为什么不在这里画文字：
##   2026-10-01 起全局主题有字体了（`theme/font_cute.tres` = `SystemFont` 幼圆），
##   但 `draw_string()` **必须显式传 Font 参数**，拿不到主题默认字体会退到
##   `ThemeDB.fallback_font`（`Open Sans SemiBold`，**没有中文字形**）→ 中文不受控。
##   要用得写 `get_theme_default_font()`，比 Label 多一层易错点。
##   所以文字一律交给 Label（沿用现役面板已验证可用的那条路）。
##   （此决定在「主题还没字体」时就成立，加字体后**结论不变**，故代码不动。）
##
## 坐标来源 = `art/ui/_draft/_ref/_panel_final_layout.py` 的规格表（1:1）。
## **面板尺寸若再变，必须同步改那边**，不要只改这里。
##
## 设计口径（与 v8 mock 一致）：
##   苏丹的「自然」不是因为排得满，而是 **留白被命名 + 通栏细线框住**，且行有骨架
##   `[铭牌]+[名称]+[数字]+[刻度]`。本层负责的就是那几根线与骨架，不负责文字与内容。

# —— 配色（与卡面 B2 同一骨色，取自 _panel_redesign.py）——
const BODY := Color8(231, 222, 202)       # 纸面骨色
const BRASS := Color8(170, 140, 70)       # 主铜色（≥7 的品级色）
const BRASS2 := Color8(206, 176, 104)     # 亮铜（分隔线）
const BRASS_LT := Color8(222, 199, 140)   # 浅铜（填充）
const INK := Color8(104, 74, 44)          # 深墨（4-6 的品级色）
const SHADOW := Color8(128, 112, 84)      # 阴影（刻度条凹槽）
const GREY_TIER := Color8(150, 134, 112)  # 灰褐（≤3 的品级色）

# —— 规格表（1x，与 _panel_final_layout.py 一一对应）——
const NAME_X := 130.0
const NAME_Y := 120.0
const RULE_X0 := 130.0
const RULE_X1 := 376.0
const GOLD1_Y := 186.0
const ATTR_C0 := 226.0
const ATTR_PITCH := 66.0
const ATTR_BOX := 26.0
const ATTR_BX := 130.0
const METER_X := 266.0
const METER_W := 110.0
const METER_H := 5.0
const GOLD2_Y := 464.0
const FAINT_Y := 530.0
const DIV_X := 390.0
const PORT_BOTTOM := 590.0

## 由 character_panel.gd 灌入的**生效值**（4 行，顺序 = int/app/str/bod）。
var values: Array[int] = [0, 0, 0, 0]


## 灌入生效值并重绘。空数组安全（全部归零）。
func configure(vals: Array) -> void:
	for i in values.size():
		values[i] = int(vals[i]) if i < vals.size() else 0
	queue_redraw()


func _draw() -> void:
	# ① 名字区结束 / 属性区结束：两条金饰分隔线（两端各一枚菱形，比纯直线「贵」）
	_gold_rule(RULE_X0, RULE_X1, GOLD1_Y)
	for i in values.size():
		_attr_row(ATTR_C0 + i * ATTR_PITCH, values[i])
	_gold_rule(RULE_X0, RULE_X1, GOLD2_Y)

	# ② 描述 / 标签之间：一根极淡的细线
	_hline(RULE_X0, RULE_X1, FAINT_Y, BODY.lerp(BRASS, 0.30), 1.0)

	# ③ 左栏 / 立绘之间的竖分割线
	draw_rect(Rect2(DIV_X, NAME_Y, 1.0, PORT_BOTTOM - NAME_Y), BODY.lerp(BRASS, 0.45))


# ============================================================
#  基础图元
# ============================================================

func _hline(x0: float, x1: float, y: float, col: Color, th: float) -> void:
	draw_rect(Rect2(x0, y, x1 - x0, maxf(1.0, th)), col)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


func _round_sb(col: Color, radius: float, border: Color = Color(0, 0, 0, 0),
		border_w: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(round(radius)))
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.anti_aliasing = true
	return sb


func _gold_rule(x0: float, x1: float, y: float) -> void:
	draw_rect(Rect2(x0, y, x1 - x0, 1.4), BRASS2)
	var r := 2.6
	_diamond(Vector2(x0, y), r, BRASS2)
	_diamond(Vector2(x1, y), r, BRASS2)


## 品级色（与卡面 / mock 的 tier_col 同一口径）：≥7 铜金 / 4-6 深墨 / ≤3 灰褐。
## 刻意不做 static / class_name：面板脚本用 `$margin/deco.tier_col(v)` 动态调用，
## 免得依赖 global_script_class_cache（CLI 直跑场景时那份缓存可能没刷新）。
func tier_col(v: int) -> Color:
	if v >= 7:
		return BRASS
	if v >= 4:
		return INK
	return GREY_TIER


# ============================================================
#  属性行骨架：[铭牌(含菱形)] + [名称与数字留给 Label] + [刻度条]
# ============================================================

func _attr_row(cy: float, v: int) -> void:
	var col := tier_col(v)
	var by := cy - ATTR_BOX * 0.5

	# 铭牌：浅铜实底 + 品级色描边
	draw_style_box(_round_sb(BODY.lerp(BRASS_LT, 0.26), 6.0, col, 1),
			Rect2(ATTR_BX, by, ATTR_BOX, ATTR_BOX))
	# 中央菱形（同色提亮，读作「一枚徽记」而不是「一个空盒子」）
	_diamond(Vector2(ATTR_BX + ATTR_BOX * 0.5, cy), 5.0, col.lerp(BODY, 0.16))

	_meter(METER_X, cy - METER_H * 0.5, METER_W, v, col)


## 刻度条：10 = 人类极限（项目标度）。细、低对比底槽 + 品级色填充，
## 中位（5 = 正常人）一根很淡的竖线给「标度感」，不做成光面游戏血条。
func _meter(x: float, y: float, w: float, v: int, col: Color) -> void:
	var h := METER_H
	draw_style_box(_round_sb(BODY.lerp(SHADOW, 0.16), h * 0.5), Rect2(x, y, w, h))
	var fw := w * clampf(float(v) / 10.0, 0.0, 1.0)
	if fw >= 1.0:
		draw_style_box(_round_sb(col, h * 0.5), Rect2(x, y, fw, h))
	var mx := x + w * 0.5
	draw_rect(Rect2(mx, y - 1.0, 1.0, h + 2.0), BODY.lerp(INK, 0.28))
