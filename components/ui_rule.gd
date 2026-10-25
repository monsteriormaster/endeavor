extends Control
## A 套装饰线（「彩铅画在纸上」）：一根铜色细线 + 可选的两端小菱形 / 中点菱形徽记。
##
## 为什么要单独一个组件：这四件（纸身 / 铜双线 / 内缘细线 / 顶中菱形 + 两端菱形线段）
## 是卡面 B2 定下的「框语言」，此前散在三处各写一份：
##   - `components/dialogue_ui.tscn` 的纸面板（烤进 `dlg_panel.png`）
##   - `components/character_panel_deco.gd::_gold_rule()`（运行时 draw）
##   - `design/_tools/make_trig_assets.py`（烤进 `trig_panel.png`）
## 这里抽成**节点级**组件，供本面板与 check_ui / result_popup 等尚未收口的弹窗复用。
##
## ⚠️ 只画形状，不画文字：`draw_string()` 拿不到主题默认字体
## （`ThemeDB.fallback_font` 没有中文字形），文字一律交给 Label —— 与
## `character_panel_deco.gd` 同一条结论（那边也是「只画形状」）。
##
## 用法：
##   ① 作为装饰分隔线放进容器：`show_line=true, show_ends=true`（默认）。
##   ② 作为一枚菱形徽记：`show_line=false, show_ends=false, show_mid=true`
##      （比如面板顶边正中那枚「顶中铜徽记」）。

## 画不画那根横线。
@export var show_line: bool = true
## 两端各一枚小菱形（与人物面板的金饰分隔线同一构件）。
@export var show_ends: bool = true
## 中点一枚稍大的菱形徽记。
@export var show_mid: bool = false
## 线宽（1x 像素，本工程逻辑分辨率恒 1920x1080，不随窗口缩放）。
@export var line_w: float = 1.4
## 两端菱形距左右边的留白。
@export var end_pad: float = 1.0
@export var end_r: float = 2.6
@export var mid_r: float = 3.6
@export var line_color: Color = Color(0.451, 0.333, 0.145, 0.45)
@export var mark_color: Color = Color(0.451, 0.333, 0.145, 0.80)


func _ready() -> void:
	# 容器排完版之后 size 才是真的。Control 的 rect 变化本来就会触发重绘，
	# 但显式接一下更稳（初版曾出现「第一帧 size=0 → 什么都没画」）。
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var cy: float = size.y * 0.5
	if show_line:
		var pad: float = (end_r + end_pad) if show_ends else 0.0
		draw_rect(Rect2(pad, cy - line_w * 0.5, maxf(0.0, size.x - pad * 2.0), line_w), line_color)
	if show_ends:
		_diamond(Vector2(end_r + end_pad, cy), end_r, mark_color)
		_diamond(Vector2(size.x - end_r - end_pad, cy), end_r, mark_color)
	if show_mid:
		_diamond(Vector2(size.x * 0.5, cy), mid_r, mark_color)


func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -r), c + Vector2(r, 0.0),
		c + Vector2(0.0, r), c + Vector2(-r, 0.0)]), col)
