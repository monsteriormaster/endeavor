## 地图人物卡牌 —— 地图中以"卡牌"形式呈现的人物节点。
## 视觉：卡牌框（圆角米色 + 棕框）+ 立绘（Portrait TextureRect 顶部）+ 名字（NameLabel 底部）+ 简介 tooltip。
## 点击卡牌触发 dialogue（条件/限制由 config_path 里的 dialogs 配置决定）。
## 不会自动触发 dialogue —— 玩家必须主动点卡牌。
##
## 视觉实现说明：Godot 4 的 Button 不支持"图标上 / 文字下"的垂直对齐属性。
## 所以人物卡牌不使用 Button 自带的 icon/text，
## 而是在子节点 Card(VBoxContainer) 里放 Portrait(TextureRect) + NameLabel(Label)，
## Button 本体只负责点击 + 卡牌 StyleBox 框。
##
## 用法：在编辑器中拖入场景，设置 charcter_name、config_path 即可。
extends Button

const CHARACTERS := "res://resoures/characters.json"

@export var charcter_name: String
@export var config_path: String

@export var max_size: Vector2 = Vector2(180, 240)
@export var min_size: Vector2 = Vector2(120, 160)
## @deprecated: 保留以兼容现有 .tscn 实例序列化的 ordinary 属性。新布局由 Card 子节点控制。
@export var ordinary := Vector2(120, 120)

@onready var _portrait: TextureRect = $Card/Portrait
@onready var _name_label: Label = $Card/NameLabel
@onready var _tooltip: PanelContainer = $TooltipPanel
@onready var _tooltip_label: Label = $TooltipPanel/Label

var info: Dictionary = {}
var map: Dictionary = {}


func _ready() -> void:
	_apply_card_style()
	setup()


## 卡牌样式：米色卡片 + 棕框 + 圆角，悬浮时高亮，按压时变深。
func _apply_card_style() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.92, 0.88, 0.78, 0.96)
	normal.border_color = Color(0.55, 0.42, 0.28, 1.0)
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(10)
	normal.content_margin_left = 8
	normal.content_margin_top = 8
	normal.content_margin_right = 8
	normal.content_margin_bottom = 8

	var hover := normal.duplicate()
	hover.bg_color = Color(0.97, 0.93, 0.83, 1.0)
	hover.border_color = Color(0.85, 0.62, 0.32, 1.0)
	hover.shadow_color = Color(0.4, 0.3, 0.15, 0.4)
	hover.shadow_size = 6

	var pressed_style := normal.duplicate()
	pressed_style.bg_color = Color(0.82, 0.78, 0.68, 1.0)
	pressed_style.border_color = Color(0.45, 0.32, 0.18, 1.0)

	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_color_override("font_color", Color(0.15, 0.10, 0.05))
	add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.01))
	add_theme_font_size_override("font_size", 20)

	# tooltip 样式
	_tooltip.visible = false
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	ts.border_color = Color(0.55, 0.42, 0.28, 1.0)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(4)
	ts.content_margin_left = 8
	ts.content_margin_top = 4
	ts.content_margin_right = 8
	ts.content_margin_bottom = 4
	_tooltip.add_theme_stylebox_override("panel", ts)
	_tooltip_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	_tooltip_label.add_theme_font_size_override("font_size", 14)


func setup() -> void:
	var file := FileAccess.open(CHARACTERS, FileAccess.READ)
	if file == null:
		push_error("[Character] 无法读取 %s" % CHARACTERS)
		return
	var all_info: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	info = all_info.get(charcter_name, {})

	if info.has("image"):
		var portrait_tex: Texture2D = load(info["image"])
		if portrait_tex != null:
			_portrait.texture = portrait_tex
	if info.has("name"):
		_name_label.text = info["name"]
	if info.has("description"):
		_tooltip_label.text = info["description"]

	# 清空 Button 自带的 icon/text —— 视觉由 Card/Portrait + Card/NameLabel 接管。
	text = ""
	icon = null

	custom_minimum_size = Vector2(180, 300)

	if config_path != "":
		var cf := FileAccess.open(config_path, FileAccess.READ)
		if cf != null:
			map = JSON.parse_string(cf.get_as_text())
			cf.close()


func _on_pressed() -> void:
	var target_dialog: Variant = get_dialog()
	if target_dialog == null:
		return
	PlotImporter.add_plot(target_dialog["path"], target_dialog["name"])


func _on_mouse_entered() -> void:
	_tooltip.visible = true


func _on_mouse_exited() -> void:
	_tooltip.visible = false


# ============================================================
#  对话选择：按 conditions/limits 从 map.dialogs 中挑一个匹配的。
# ============================================================

func get_dialog() -> Variant:
	var dialogs = map.get("dialogs", {})

	for dialog_name in dialogs:
		var dialog = dialogs[dialog_name]
		var conditions = dialog.get("conditions", {})
		var limits = dialog.get("limits", {})
		var method = 1
		var flag := false

		#处理其他数值条件
		if "others" in conditions:
			var others = conditions.others
			for other in others:
				var res = Player[others[other].name] - others[other].value
				var sentence = others[other].sentence

				if sentence == 0:
					if res != 0:
						flag = true
						break
				if sentence == 1:
					if res < 0:
						flag = true
						break
				if sentence == -1:
					if res > 0:
						flag = true
						break

		# 处理玩家标签条件
		if "method" in conditions:
			method = conditions.method
		if "tags" in conditions:
			if not Player.player_has_tags(conditions.tags, method):
				continue
		if "num_tags" in conditions:
			var num_tags = conditions["num_tags"]
			for num_tag_name in num_tags:
				if not Player.player_meet_num_tag(num_tags[num_tag_name].name, num_tags[num_tag_name].left, num_tags[num_tag_name].right):
					flag = true
					break
		# 处理NPC条件
		if "npc" in conditions:
			var npc_conditions = conditions.npc
			# 遍历NPC条件字典
			for npc_name in npc_conditions:
				var npc = npc_conditions[npc_name]
				var npc_method = 1
				if "method" in npc:
					npc_method = npc.method
				if "tags" in npc:
					if not Player.npc_has_tags(npc_name, npc.tags, npc_method):
						flag = true
						break
				if "num_tags" in npc:
					var npc_num_tags = npc["num_tags"]
					for num_tag_name in npc_num_tags:
						if not Player.npc_meet_num_tag(npc_num_tags[num_tag_name].name, npc_name, npc_num_tags[num_tag_name].left, npc_num_tags[num_tag_name].right):
							flag = true
							break
					if flag:
						break

		if flag:
			continue

		# 处理限制条件
		if "method" in limits:
			method = limits.method
		if "tags" in limits:
			if Player.player_has_tags(limits.tags, method):
				continue
		if "num_tags" in limits:
			var lim_num_tags = limits["num_tags"]
			for num_tag_name in lim_num_tags:
				if Player.player_meet_num_tag(lim_num_tags[num_tag_name].name, lim_num_tags[num_tag_name].left, lim_num_tags[num_tag_name].right):
					flag = true
					break

		# 处理NPC限制条件
		if "npc" in limits:
			var npc_limits = limits.npc
			# 遍历NPC限制字典
			for npc_name in npc_limits:
				var npc = npc_limits[npc_name]
				var npc_method = 1
				if "method" in npc:
					npc_method = npc.method
				if "tags" in npc:
					if Player.npc_has_tags(npc_name, npc.tags, npc_method):
						flag = true
						break
				if "num_tags" in npc:
					var npc_num_tags = npc["num_tags"]
					for num_tag_name in npc_num_tags:
						if Player.npc_meet_num_tag(npc_num_tags[num_tag_name].name, npc_name, npc_num_tags[num_tag_name].left, npc_num_tags[num_tag_name].right):
							flag = true
							break
					if flag:
						break

		if flag:
			continue

		return dialog

	return null
