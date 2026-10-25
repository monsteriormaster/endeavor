class_name Newspaper
extends Control

const TextVars := preload("res://script/text_vars.gd")

## 报纸/布告弹窗组件（简化 4 栏版）。
## 以去背报纸图为底，2×2 叠加四个大小相近的新闻位：
##   News1(左上) News2(右上) News3(左下) News4(右下=随机效果位)
## 顶部有报头（title）与日期行（date）。内容由字典或 JSON 文件驱动。
##
## 用法（调用方实例化并加入当前场景，推荐经 OverlayRoot 模态托管）：
##   var paper := load("res://components/newspaper.tscn").instantiate() as Newspaper
##   OverlayRoot.push_overlay(paper, {"modal":true, "esc_closes":true, "close_method":"close", "persist":true})
##   paper.closed.connect(_on_paper_closed)   # 可选
##   paper.show_newspaper(data)
##
## 数据字段（Dictionary，兼容从 JSON 解析）：
##   title:   String   报头标题（经 TextVars 解析 {player.*} 等占位符）
##   date:    String   日期/期号行（为空隐藏）
##   columns: Array    最多 4 条新闻，按下标填入 News1..News4：
##                     [0]=左上 [1]=右上 [2]=左下 [3]=右下（随机效果位）
##                     每条 {headline: String, body: String, kind?: "effect"}
##                     kind=="effect" 时该条以琥珀红高亮显示（随机效果位专用）。

signal closed

const PAPER_WIDTH: float = 1080.0
const PAPER_HEIGHT: float = 972.0

## 普通新闻用纯黑墨色（落到淡米色报纸底图上就是"黑字"，避免
## 走 Godot 默认主题"近白"字色在浅底上"消失"）；随机效果位仍用
## 琥珀红高亮（设计约定，见 design/报纸内容JSON配置.md §4）。
const HIGHLIGHT_COLOR := Color(0.62, 0.13, 0.05, 1)
const NORMAL_COLOR := Color(0, 0, 0, 1)

@onready var masthead: Label = $PaperFrame/Overlay/Masthead
@onready var date_label: Label = $PaperFrame/Overlay/DateLabel
@onready var close_button: Button = $PaperFrame/Overlay/CloseButton

@onready var news_headlines: Array = [
	$PaperFrame/Overlay/News1Headline, $PaperFrame/Overlay/News2Headline,
	$PaperFrame/Overlay/News3Headline, $PaperFrame/Overlay/News4Headline,
]
@onready var news_bodies: Array = [
	$PaperFrame/Overlay/News1Body, $PaperFrame/Overlay/News2Body,
	$PaperFrame/Overlay/News3Body, $PaperFrame/Overlay/News4Body,
]

const COL_COUNT := 4


func _ready() -> void:
	visible = false


## 用调用方提供的字典渲染报纸。
func show_newspaper(data: Dictionary) -> void:
	var ctx := {}
	masthead.text = TextVars.resolve(str(data.get("title", "")), ctx)

	var date_text: String = TextVars.resolve(str(data.get("date", "")), ctx)
	date_label.text = date_text
	date_label.visible = date_text != ""

	var columns: Array = data.get("columns", [])
	if columns.is_empty() and data.has("body"):
		# 旧格式兼容：单条正文落入 News1
		_render_legacy(data, ctx)
		visible = true
		return

	for i in range(COL_COUNT):
		if i >= columns.size():
			_hide_col(i)
			continue
		var col: Dictionary = columns[i]
		var headline: String = TextVars.resolve(str(col.get("headline", "")), ctx)
		var body: String = TextVars.resolve(str(col.get("body", "")), ctx)
		var is_effect: bool = str(col.get("kind", "")) == "effect"
		_show_col(i, headline, body, is_effect)

	visible = true


## 从 JSON 文件加载并渲染。
func show_from_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("Newspaper: 找不到报纸文件 %s" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Newspaper: 无法读取 %s" % path)
		return
	var text: String = file.get_as_text()
	var data: Variant = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		push_error("Newspaper: JSON 解析失败 %s" % path)
		return
	show_newspaper(data)


# ------------------------------------------------------------------ 内部

func _hide_col(i: int) -> void:
	news_headlines[i].visible = false
	news_bodies[i].visible = false


func _show_col(i: int, headline: String, body: String, is_effect: bool) -> void:
	var h: Label = news_headlines[i]
	var b: RichTextLabel = news_bodies[i]
	h.visible = true
	b.visible = true
	h.text = headline
	b.text = body
	if is_effect:
		h.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
		b.add_theme_color_override("default_color", HIGHLIGHT_COLOR)
	else:
		# 显式覆写为黑色（不调 remove_theme_color_override，避免落到
		# Godot 默认主题的近白字色，在淡米色报纸底上读不出）。
		h.add_theme_color_override("font_color", NORMAL_COLOR)
		b.add_theme_color_override("default_color", NORMAL_COLOR)


func _render_legacy(data: Dictionary, ctx: Dictionary) -> void:
	for i in range(COL_COUNT):
		_hide_col(i)
	var body: String = TextVars.resolve(str(data.get("body", "")), ctx)
	_show_col(0, "", body, false)


# ------------------------------------------------------------------ 关闭

func _on_background_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()
			get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ENTER:
			close()
			get_viewport().set_input_as_handled()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
	OverlayRoot.close_overlay(self)
