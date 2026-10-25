"""
鉴定界面 - 展示鉴定过程和结果
由 CheckProcessor 自动实例化，不需要手动调用。
"""

extends Control

const TextVars := preload("res://script/text_vars.gd")

@export var title_label: Label
@export var desc_label: Label
@export var formula_label: Label
@export var x_label: Label
@export var qualitative_label: Label
@export var modifiers_container: VBoxContainer
@export var roll_label: Label
@export var final_label: Label
@export var difficulty_label: Label
@export var result_label: Label
@export var continue_button: Button

const ATTR_DISPLAY = {
	"int": "智力",
	"app": "魅力",
	"str": "力量",
	"bod": "体魄",
	"edu": "教育",
}

const RESULT_TEXT = {
	"crit_success": "✦ 大成功！ ✦",
	"success": "成功！",
	"failure": "失败……",
	"crit_failure": "✦ 大失败 ✦",
}

const RESULT_COLORS = {
	# D-C7：大成功改为金色，与普通成功（绿）明确区分。
	# 2026-10-01 纸底改版：整组**统一加深**——原值是为深墨紫底（B 套）挑的亮色，
	# 放到米色纸（#F3EEE3）上「大成功金」几乎看不见（亮度 199 vs 纸 238）。
	"crit_success": Color(0.66, 0.47, 0.04),
	"success": Color(0.15, 0.48, 0.18),
	"failure": Color(0.72, 0.42, 0.10),
	"crit_failure": Color(0.70, 0.15, 0.14),
}

## 纸底上仍要读得清的「好 / 坏 / 中性」三档，供加成、胜算共用。
const INK_GOOD := Color(0.15, 0.48, 0.18)
const INK_MID := Color(0.68, 0.52, 0.06)
const INK_BAD := Color(0.72, 0.42, 0.10)
const INK_DEAD := Color(0.50, 0.46, 0.42)

# ============================================================
#  外观（A 套：纸 + 铜 + 墨。2026-10-01 从引擎默认面板收口过来）
# ============================================================
## 「继续」按钮的字色。**纸片样式自 2026-10-06 起不再在这里设** ——
## 全工程按钮统一由 Autoload `ButtonSkin` 按尺寸套 `art/ui/btn_paper_{l,s}.png`。
## ⚠️ 若再在这里 `add_theme_stylebox_override`，会把全局皮顶掉
##    （本函数在 `_ready` 里跑，晚于 ButtonSkin 的 node_added），统一随即失效。
const BTN_INK := Color(0.180, 0.141, 0.094)

var _check_data: Dictionary
var _resolved: Dictionary
var _processor: Node


func _ready() -> void:
	_style_button()


func _style_button() -> void:
	if continue_button == null:
		return
	# 全局 default_texture_filter = NEAREST，九宫格的细描边必须单独开 LINEAR。
	continue_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	continue_button.add_theme_color_override("font_color", BTN_INK)
	continue_button.add_theme_color_override("font_hover_color", BTN_INK)
	continue_button.add_theme_color_override("font_pressed_color", BTN_INK)


func show_check(check_data: Dictionary, resolved: Dictionary, processor: Node) -> void:
	_check_data = check_data
	_resolved = resolved
	_processor = processor
	visible = true

	# 标题 & 描述（D-C10：过 TextVars 解析 {player_name} 等占位符）
	title_label.text = "鉴定：" + check_data.get("title", "未知鉴定")
	desc_label.text = TextVars.resolve(String(check_data.get("description", "")), {})

	# 属性公式
	var attrs: Dictionary = resolved.get("attrs", {})
	var parts := PackedStringArray()
	for attr_name in attrs:
		var display: String = ATTR_DISPLAY.get(attr_name, attr_name)
		parts.append(display + "×" + str(attrs[attr_name]))
	formula_label.text = "属性：" + "  +  ".join(parts)

	# 有效骰面
	x_label.text = "有效骰面：1d" + str(resolved["x"])

	# 难度
	difficulty_label.text = "难度：" + str(resolved["difficulty"])

	# 加成列表（含未生效灰显，D-C8）
	_show_modifiers(check_data.get("modifiers", []), resolved["modifiers"], resolved["modifier_total"])

	# D-C9：胜算定性带（不暴露精确 %）
	_show_qualitative(resolved)

	# 不可能成功的提示
	if resolved.get("impossible", false):
		x_label.text += "  （骰面+加成不足以触及难度）"

	# 先隐藏结果区域
	roll_label.text = "骰子：……"
	final_label.visible = false
	result_label.visible = false
	continue_button.visible = false

	# 掷骰动画
	_animate_roll()


## D-C8：展示全部加成配置；已生效高亮、未生效灰显（让玩家看懂杠杆）。
func _show_modifiers(all_config: Array, active: Array, total: int) -> void:
	for child in modifiers_container.get_children():
		child.queue_free()

	if all_config.is_empty():
		var label: Label = Label.new()
		label.text = "加成：无"
		label.add_theme_font_size_override("font_size", 16)
		modifiers_container.add_child(label)
		return

	for mod in all_config:
		var is_on: bool = _is_mod_active(mod, active)
		var bonus: int = int(mod.get("bonus", 0))
		var sign_str := "+" if bonus >= 0 else ""
		var desc: String = String(mod.get("desc", mod.get("name", "?")))
		var label: Label = Label.new()
		label.text = "  " + desc + "  " + sign_str + str(bonus)
		if is_on:
			label.add_theme_color_override("font_color", INK_GOOD)
		else:
			label.add_theme_color_override("font_color", INK_DEAD)
			label.text += "  （未满足）"
		label.add_theme_font_size_override("font_size", 16)
		modifiers_container.add_child(label)

	var total_label: Label = Label.new()
	total_label.text = "加成合计：+" + str(total)
	total_label.add_theme_font_size_override("font_size", 16)
	modifiers_container.add_child(total_label)


## 判断某条加成配置当前是否生效（与已生效列表按 source+name 匹配）。
func _is_mod_active(mod: Dictionary, active: Array) -> bool:
	var s: String = String(mod.get("source", ""))
	var n: String = String(mod.get("name", ""))
	for a in active:
		if String(a.get("source", "")) == s and String(a.get("name", "")) == n:
			return true
	return false


## D-C9：定性胜算带，只给「极高/高/中/低/极低」与配色，不显精确概率。
func _show_qualitative(resolved: Dictionary) -> void:
	if qualitative_label == null:
		return
	if resolved.get("impossible", false):
		qualitative_label.text = "胜算：几乎不可能"
		qualitative_label.add_theme_color_override("font_color", INK_DEAD)
		return
	var x: int = int(resolved.get("x", 1))
	var mod_total: int = int(resolved.get("modifier_total", 0))
	var difficulty: int = int(resolved.get("difficulty", 1))
	# 期望余量 = 骰子期望 (x+1)/2 + 加成 - 难度
	var expected_margin: float = float(x + 1) / 2.0 + float(mod_total) - float(difficulty)
	var text: String
	var col: Color
	if expected_margin >= 3.0:
		text = "胜算：极高"; col = INK_GOOD
	elif expected_margin >= 1.0:
		text = "胜算：高"; col = Color(0.38, 0.52, 0.12)
	elif expected_margin >= 0.0:
		text = "胜算：中"; col = INK_MID
	elif expected_margin >= -2.0:
		text = "胜算：低"; col = INK_BAD
	else:
		text = "胜算：极低"; col = Color(0.70, 0.15, 0.14)
	qualitative_label.text = text
	qualitative_label.add_theme_color_override("font_color", col)


func _animate_roll() -> void:
	var x: int = _resolved["x"]
	var tween: Tween = get_tree().create_tween()
	tween.bind_node(self)

	# 滚动假数字
	var frames := 12
	for _i in range(frames):
		var fake: int = randi() % max(1, x) + 1
		tween.tween_callback(_set_roll_text.bind(str(fake)))
		tween.tween_interval(0.06)

	# 定格到真实结果
	tween.tween_callback(_on_roll_settled)


func _set_roll_text(value: String) -> void:
	roll_label.text = "骰子：" + value


func _on_roll_settled() -> void:
	roll_label.text = "骰子：" + str(_resolved["roll"])
	_show_final_result()


func _show_final_result() -> void:
	var roll: int = _resolved["roll"]
	var mod_total: int = _resolved["modifier_total"]
	var final_val: int = _resolved["final"]
	var result_level: String = _resolved["result_level"]

	# 判定音已移除（2026-10-14）：原在结果定格时按 result_level 播 ui_verdict_fail/maybe/pass，
	# 现改为静默出结果。`ui_verdict_*` 素材与注册表条目保留，需要时可一键接回。

	# 最终值
	if mod_total > 0:
		final_label.text = "最终：%d + %d = %d" % [roll, mod_total, final_val]
	else:
		final_label.text = "最终：%d" % final_val
	final_label.visible = true

	# 结果文字 + 颜色
	result_label.text = RESULT_TEXT.get(result_level, "未知")
	result_label.add_theme_color_override("font_color", RESULT_COLORS.get(result_level, Color.WHITE))
	result_label.visible = true

	continue_button.visible = true


func _on_continue_pressed() -> void:
	_processor.on_check_confirmed(_check_data, _resolved)
	# 统一从覆盖层管理器出栈（内部会 queue_free）；未被托管时自行销毁
	if not OverlayRoot.close_overlay(self):
		queue_free()
