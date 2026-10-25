## 卡牌详情弹窗 —— **道具卡专用**（人物卡走 CharacterPanel，见 main_ui 的分流）。
##
## 底图 = `art/ui/item_panel.png`（680×600 手绘纸框），由
## `art/ui/_draft/make_item_panel_bg.py` 烤制：纸纹取 `paper_tile.png`、线色取样 `check_panel.png`，
## 所以与鉴定/确认面板是同一套画风。**本文件只摆节点，不画框** —— 换皮只换图，
## 改版面则下面的锚点表与 py 里的常量表必须一起改（否则文字会压到框线上）。
##
## 用法：CardDetailPopup.open(card) —— 自动交给 OverlayRoot 托管，点遮罩 / 右上 X / Esc 关闭。
class_name CardDetailPopup
extends Control

const PANEL_TEX_PATH := "res://art/ui/item_panel.png"
const PANEL_SIZE := Vector2(680, 540)

# ============================================================
#  版面锚点（逐项对应 make_item_panel_bg.py 的常量表）
# ============================================================
const BOX := Rect2(52, 72, 170, 236)      # 图位框（底图已画框，这里只放图）170×236 = 物品竖图 0.72
const COL_X0 := 258.0                     # 右栏左缘
const COL_X1 := 636.0                     # 右栏右缘
const NAME_Y := 60.0                      # 名称行顶
const SUB_Y := 110.0                      # 品质 · 类别 行顶
const BONUS_Y := 160.0                    # 加成行顶
const TAG_Y := 208.0                      # 标签行顶
const TAG_H := 28.0
const IDENT_Y := 246.0                    # id / 售价 行顶
const DESC_TITLE_Y := 326.0               # 「描述」标题顶（底图竖笔在 y 328..347）
const BODY_Y := 354.0                     # 描述正文顶
const BODY_BOTTOM := 494.0                # 描述正文可用底
const CLOSE_C := Vector2(632, 56)          # = 底图上那个 X 的中心
const CLOSE_HIT := 22.0                   # 关闭钮热区半径

const NAME_FONT := 30
const SUB_FONT := 15
const BONUS_FONT := 17
const TAG_FONT := 14
const IDENT_FONT := 12
const BODY_FONT := 16
const BODY_LINE_H := 26

# ============================================================
#  配色（取样自 panel 系列 / character_panel.tscn，不另起一套）
# ============================================================
const INK := Color(0.18, 0.13, 0.09)       # 主文字
const SUB_INK := Color(0.37, 0.31, 0.23)   # 正文
const GOLD := Color(0.60, 0.42, 0.14)      # 金色小标题
const FADE := Color(0.45, 0.39, 0.31)      # 极淡（id）
const PAPER := Color(0.949, 0.929, 0.890)  # 底图加载失败时的兜底底色

const ATTR_CN := {
	"int": "智力",
	"app": "魅力",
	"str": "力量",
	"bod": "体魄",
}

## 物品类别 → 中文。取值来自 resoures/items/*.json 的 class 字段（已穷举）。
const CLASS_CN := {
	"weapon": "武器",
	"armor": "防具",
	"jewelry": "饰品",
	"book": "书",
	"tool": "工具",
	"clue": "线索",
	"good": "货物",
	"未知": "未知",
}

## 品质 → 徽章颜色（低饱和，避免抢纸面）。键外一律不画徽章。
const LEVEL_COL := {
	"SSR": Color(0.62, 0.44, 0.14),
	"SR": Color(0.38, 0.33, 0.52),
	"S": Color(0.26, 0.40, 0.36),
	"R": Color(0.46, 0.40, 0.33),
}

## 全屏遮罩（点它 = 点面板外）。落点换算要用它的 global_position，故留引用。
var _bg: ColorRect = null
var _panel: Control = null


## 打开一张卡的详情弹窗。统一交给 OverlayRoot 托管（D-UI6）：
## 它会压在触发器弹窗之上，Esc 只关它、不会连带把底下的触发器窗一起关掉。
static func open(card: CardData) -> CardDetailPopup:
	var popup := CardDetailPopup.new()
	popup.name = "CardDetailPopup"
	# 「点外收起时点到的是不是同一张卡」靠这条 meta 判（见 OverlayRoot.close_with_click_through）。
	popup.set_meta("card_panel_key", card.id if card.id != "" else card.display_name)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return popup
	var overlay_root: Node = tree.root.get_node_or_null("OverlayRoot")
	if overlay_root != null:
		overlay_root.push_overlay(popup, {
			"modal": true,
			"esc_closes": true,
			"close_method": "close",
		})
	else:
		tree.root.add_child(popup)
	popup._build(card, Vector2(tree.root.size))
	return popup


## 关闭详情弹窗。Esc / 关闭按钮 / 点遮罩共用。
func close() -> void:
	if not OverlayRoot.close_overlay(self):
		queue_free()


# ============================================================
#  构建
# ============================================================
func _build(card: CardData, viewport_size: Vector2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 遮罩
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.65)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_gui_input)
	add_child(bg)
	_bg = bg

	# 纸面（固定尺寸，居中）。mobile 小窗口下会被裁，但游戏锁 1280×720 起步，够。
	var panel := Control.new()
	panel.name = "panel"
	panel.size = PANEL_SIZE
	panel.position = ((viewport_size - PANEL_SIZE) / 2.0).floor()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	add_child(panel)
	_panel = panel

	_put_paper(panel)
	_put_art(panel, card)
	_put_texts(panel, card)
	_put_close(panel)


## 纸面底图。加载不到就退回一块纯纸色面板 —— 绝不出现"默认灰框"那种掉画风的情况。
func _put_paper(panel: Control) -> void:
	if ResourceLoader.exists(PANEL_TEX_PATH, "Texture2D"):
		var tex := TextureRect.new()
		tex.name = "paper"
		tex.texture = load(PANEL_TEX_PATH)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tex.size = PANEL_SIZE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(tex)
		return
	push_warning("[CardDetailPopup] 缺底图 %s，退回纯色面板" % PANEL_TEX_PATH)
	var fb := Panel.new()
	fb.name = "paper_fallback"
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color(0.49, 0.38, 0.18)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	fb.add_theme_stylebox_override("panel", sb)
	fb.size = PANEL_SIZE
	fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(fb)


## 图位：物品竖图按比例居中塞进 BOX。没图就留空 —— 框上的四角 L 角标本身就是"这里放图"。
func _put_art(panel: Control, card: CardData) -> void:
	var art := TextureRect.new()
	art.name = "art"
	art.texture = _try_load_icon(card)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.position = BOX.position + Vector2(5, 5)
	art.size = BOX.size - Vector2(10, 10)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	# 没图时给一句极淡的占位 —— 空框会让人以为资源没加载成功。
	if art.texture == null:
		var ph := _mk_label("暂无图像", 13, Color(0.45, 0.39, 0.31, 0.55))
		ph.name = "art_placeholder"
		ph.position = BOX.position
		ph.size = BOX.size
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(ph)


func _put_texts(panel: Control, card: CardData) -> void:
	var col_w: float = COL_X1 - COL_X0

	# ---- 名称 ----
	var name_l := _mk_label(card.display_name, NAME_FONT, INK)
	name_l.name = "cardname"
	name_l.position = Vector2(COL_X0, NAME_Y)
	name_l.size = Vector2(col_w, 44)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	panel.add_child(name_l)

	# ---- 品质 · 类别 ----
	var sub := HBoxContainer.new()
	sub.name = "subline"
	sub.position = Vector2(COL_X0, SUB_Y)
	sub.size = Vector2(col_w, 26)
	sub.add_theme_constant_override("separation", 9)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sub)

	var lv := String(card.level).to_upper()
	if LEVEL_COL.has(lv):
		sub.add_child(_mk_level_badge(lv, LEVEL_COL[lv]))
		var dot := _mk_label("·", SUB_FONT, FADE)
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sub.add_child(dot)
	var cls_parts: Array = []
	for c in card.card_class:
		cls_parts.append(String(CLASS_CN.get(c, c)))
	var cls_l := _mk_label(_join_str(cls_parts, " / "), SUB_FONT, SUB_INK)
	cls_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.add_child(cls_l)

	# ---- 加成 / 属性 ----
	var bonus_l := _mk_label(_attr_line(card), BONUS_FONT, INK)
	bonus_l.name = "bonus"
	bonus_l.position = Vector2(COL_X0, BONUS_Y)
	# 四属性全写时单行装不下：autowrap 必须开（关着时 Label 的 min_width = 整行文本宽，
	# 会把 size 撑破右栏，clip_text 也救不回来 —— 探针实测「体魄 +1」被切在面板外）。
	bonus_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus_l.size = Vector2(col_w, 48)
	panel.add_child(bonus_l)

	# ---- 标签 ----
	var tags := HBoxContainer.new()
	tags.name = "tags"
	tags.position = Vector2(COL_X0, TAG_Y)
	tags.size = Vector2(col_w, TAG_H)
	tags.add_theme_constant_override("separation", 7)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tags.clip_contents = true
	panel.add_child(tags)
	for t in card.tags:
		tags.add_child(_mk_tag_chip(String(t)))

	# ---- id / 售价（策划对账用，做到最小最淡）----
	var ident := "id: %s" % (card.id if card.id != "" else "—")
	if card.price > 0:
		ident += "　售价 %d 金" % card.price
	var ident_l := _mk_label(ident, IDENT_FONT, FADE)
	ident_l.name = "ident"
	ident_l.position = Vector2(COL_X0, IDENT_Y)
	ident_l.size = Vector2(col_w, 18)
	ident_l.clip_text = true
	panel.add_child(ident_l)

	# ---- 描述 ----
	var dt := _mk_label("描述", BODY_FONT, GOLD)
	dt.name = "desc_title"
	dt.position = Vector2(BOX.position.x + 14, DESC_TITLE_Y)
	dt.size = Vector2(col_w, 22)
	dt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(dt)

	var body := _mk_label(card.description, BODY_FONT, SUB_INK)
	body.name = "desc"
	# 🔴 autowrap 必须**先于** size 设置：Label 的 minimum_size 在 autowrap 关闭时等于
	# 整行文本宽度，先设 size 会被 min 撑回去 → 正文单行冲出面板（探针截图实测过）。
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.position = Vector2(BOX.position.x + 14, BODY_Y)
	body.size = Vector2(COL_X1 - BOX.position.x - 14, BODY_BOTTOM - BODY_Y)
	body.custom_minimum_size = Vector2(COL_X1 - BOX.position.x - 14, 0)
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	# Label 没有 line_spacing 属性，只能按「目标行高 - 字体自然高」算 override。
	var font := body.get_theme_font("font")
	if font != null:
		body.add_theme_constant_override(
			"line_spacing", int(round(BODY_LINE_H - float(font.get_height(BODY_FONT)))))
	panel.add_child(body)


## 右上 X。底图上已经烤了图形，这里只放一个 flat 热区，hover 时给纸面一点提亮反馈。
func _put_close(panel: Control) -> void:
	var btn := Button.new()
	btn.name = "close"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.position = CLOSE_C - Vector2(CLOSE_HIT, CLOSE_HIT)
	btn.size = Vector2(CLOSE_HIT * 2.0, CLOSE_HIT * 2.0)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.modulate = Color(1, 1, 1, 0.9)
	btn.mouse_entered.connect(func(): btn.modulate = Color(1, 1, 1, 1.0))
	btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1, 0.9))
	btn.pressed.connect(close)
	panel.add_child(btn)


# ============================================================
#  内部
# ============================================================

## 品质徽章：细边框小印章，比纯文字更"藏品感"，又不至于抢名称。
func _mk_level_badge(lv: String, col: Color) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.10)
	sb.border_color = Color(col.r, col.g, col.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _mk_label(lv, 14, col)
	box.add_child(l)
	return box


## 标签 chip：纸色底 + 褐线，与纸面同族。
func _mk_tag_chip(text: String) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.94, 0.91, 0.84, 0.85)
	sb.border_color = Color(0.62, 0.50, 0.32, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(9)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _mk_label(text, TAG_FONT, INK)
	box.add_child(l)
	return box


## 加成行文本。道具卡读 bonus/check_bonus，人物卡（理论上不走这里）读四维。
func _attr_line(card: CardData) -> String:
	if card.card_type == "character":
		return "属性　智力 %d　魅力 %d　力量 %d　体魄 %d" % [
			int(card.attrs.get("int", 0)), int(card.attrs.get("app", 0)),
			int(card.attrs.get("str", 0)), int(card.attrs.get("bod", 0)),
		]
	var parts: Array = []
	for key in ["int", "app", "str", "bod"]:
		if int(card.bonus.get(key, 0)) != 0:
			parts.append("%s %+d" % [String(ATTR_CN[key]), int(card.bonus[key])])
	if card.check_bonus != 0:
		parts.append("鉴定 %+d" % card.check_bonus)
	if card.is_consumable():
		parts.append("消耗品")
	return "加成　%s" % _join_str(parts, "  ·  ") if parts.size() > 0 else "加成　—"


func _on_bg_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# 点面板外 → 收起；若落点正好是另一张手牌，顺手把那一下转给那张卡
		# （一次点击完成「关掉本详情 + 打开另一张卡的详情」，见 OverlayRoot.close_with_click_through）。
		# 🔴 落点由事件算，不要用 get_global_mouse_position()：那个读的是系统光标的实时位置，
		# 与这条事件的位置不是一回事（探针实测差到 1000px 开外，点击就会落空）。
		var mb := event as InputEventMouseButton
		OverlayRoot.close_with_click_through(self, _bg.global_position + mb.position)


## 图像区贴图：路径解析统一走 `CardChip.resolve_icon_path`（单一来源）。
## 原先这里自己写「icon_path 为空就返回 null」，把人物卡的 gender 回落短路了 ——
## 与 card_chip 曾经的 bug 同源（见那边的注释）。
func _try_load_icon(card: CardData) -> Texture2D:
	var path := CardChip.resolve_icon_path(card)
	if path == "":
		return null
	# load() 返回 Variant，显式标注 Texture2D，与函数返回类型一致。
	var t: Texture2D = load(path)
	if t is Texture2D:
		return t
	return null


func _mk_label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _join_str(parts: Array, sep: String) -> String:
	var out := ""
	for i in parts.size():
		if i > 0:
			out += sep
		out += String(parts[i])
	return out
