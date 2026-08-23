extends Control

const TextVars := preload("res://script/text_vars.gd")

@export_group("UI")
@export var character_name_text: Label
@export var text_box: Label
@export var option_box: VBoxContainer
@export var panel: Panel
@export var default_panel_height: float = 227.0

## 报纸弹窗尺寸（屏幕正中，固定宽高，内容过长会被裁切）
const NEWSPAPER_WIDTH: float = 720.0
const NEWSPAPER_HEIGHT: float = 420.0

enum LayoutMode { DEFAULT, NEWSPAPER }
## 避开原生 Control.layout_mode（Godot 4.7+ 已将其作为布局系统属性占用）。
var _layout: LayoutMode = LayoutMode.DEFAULT


var main_dialogue: DialogueGroup
var dialogue_index: int = 0
var typing_tween: Tween

var hero = Player.player_name

## 选项触发了"取名弹窗"等阻塞型 effect 时，暂存要跳转的下一步，等弹窗确认后再继续。
var _pending_next: int = -1


func show_dialogue_group(dialogue_group: DialogueGroup) -> void:
	main_dialogue = dialogue_group
	dialogue_index = 0
	_apply_layout(dialogue_group.layout)
	visible = true
	display_next_dialogue()


func _apply_layout(layout: String) -> void:
	if layout == "newspaper":
		_layout = LayoutMode.NEWSPAPER
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.offset_left = -NEWSPAPER_WIDTH / 2.0
		panel.offset_right = NEWSPAPER_WIDTH / 2.0
		panel.offset_top = -NEWSPAPER_HEIGHT / 2.0
		panel.offset_bottom = NEWSPAPER_HEIGHT / 2.0
		panel.custom_minimum_size = Vector2(NEWSPAPER_WIDTH, NEWSPAPER_HEIGHT)
		# 报纸弹窗不需要角色名 & 选项
		character_name_text.visible = false
		option_box.visible = false
	else:
		_layout = LayoutMode.DEFAULT
		panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		panel.offset_top = -default_panel_height
		panel.offset_left = 0.0
		panel.offset_right = 0.0
		panel.custom_minimum_size = Vector2(0.0, default_panel_height)
		character_name_text.visible = true
		option_box.visible = true


func display_next_dialogue() -> void:
	if dialogue_index == -1:
		Player.is_dialogue_exist = false
		visible = false
		EventSignal.emit_signal('dialogue_finished')
		_close_self()
		return

	clear_options()

	var dialogue = main_dialogue.dialogue_list[dialogue_index]
	var full_text: String = TextVars.resolve(dialogue.content, dialogue.context)

	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
		text_box.text = full_text
		if dialogue.is_option == false:
			dialogue_index = _resolve_next(dialogue)
	else:
		character_name_text.text = TextVars.resolve(dialogue.character_name, dialogue.context)

		typing_tween = get_tree().create_tween()
		text_box.text = ""
		for character in full_text:
			typing_tween.tween_callback(append_character.bind(character)).set_delay(0.05)
		if dialogue.is_option == false:
			typing_tween.tween_callback(func(): dialogue_index = _resolve_next(dialogue))


	if dialogue.effect != {} and !dialogue.is_effect_excute:
		dialogue.is_effect_excute = true
		var blocked := deal_effect(dialogue.effect)
		if blocked:
			# 步骤级阻塞型 effect（如 name_child）：弹窗确认后需自动推进到本步 next。
			# 选项级 name_child 由 on_option_entered 已设置 _pending_next，这里不覆盖。
			_pending_next = _resolve_next(dialogue)

	if dialogue.is_option:
		show_option(dialogue.options, dialogue.context)


func append_character(character: String) -> void:
	text_box.text += character


func show_option(options, ctx: Dictionary) -> void:
	for option in options:
		if option["is_ava"]:
			var option_label = Button.new()
			option_label.text = TextVars.resolve(option.text, ctx)
			option_label.pressed.connect(on_option_entered.bind(option.effect, option.next))
			option_box.add_child(option_label)
		else:
			var option_label = Button.new()
			option_label.text = TextVars.resolve(option["condition"].description, ctx)
			option_label.disabled = true
			option_box.add_child(option_label)


func _ready() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	# 报纸模式：点击任意位置或按回车 → 推进对话
	if not visible:
		return
	if _layout != LayoutMode.NEWSPAPER:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			display_next_dialogue()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ENTER:
			display_next_dialogue()
			get_viewport().set_input_as_handled()
			return


func _on_click(event: InputEvent) -> void:
	# 普通模式：仅点击 Panel 区域推进（报纸模式由 _input 统一处理）
	if _layout == LayoutMode.NEWSPAPER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		display_next_dialogue()


func on_option_entered(effect, next: int) -> void:
	var blocked := false
	if effect != {}:
		blocked = deal_effect(effect)
	if blocked:
		# 取名弹窗等阻塞型 effect：先别推进，等 confirmed 后再继续
		_pending_next = next
		return
	dialogue_index = next
	display_next_dialogue()


## 对白播完后销毁自身。
## 旧实现只把 visible 置 false，节点会永远挂在树上：每播一段剧情就多一个常驻实例
## （内存泄漏，且它的 _input 仍在抢输入）。接入 OverlayRoot 后更不能留 ——
## 只要它还在模态栈里，输入拦截层就不会撤，地图和 HUD 会彻底点不动。
func _close_self() -> void:
	if not OverlayRoot.close_overlay(self):
		queue_free()


func clear_options() -> void:
	for child in option_box.get_children():
		child.queue_free()


## 步骤推进时解析最终 next：
## 若该步配置了 nexts（条件跳转），按顺序取首个命中条件的 next；
## 无条件（缺 condition 或为空）的条目作为默认兜底；无命中则回落到固定 next。
## condition 写法与 option.condition 一致，复用 PlotImporter.sentence_condition（含 child 键）。
func _resolve_next(dialogue) -> int:
	var nexts = dialogue.nexts
	if nexts is Array and nexts.size() > 0:
		for entry in nexts:
			var cond = entry.get("condition", {})
			if cond == {} or PlotImporter.sentence_condition(cond):
				return int(entry.get("next", -1))
	return int(dialogue.next)


func deal_effect(dialogue_effects) -> bool:
	# 对话系统 effect 处理统一转发 EffectProcessor（三系统共用同一套 effect 契约）。
	# name_child 为阻塞型：通过 on_name_child 回调触发取名弹窗，apply 返回 blocked=true，
	# 调用方（display_next_dialogue / on_option_entered）据此暂存 _pending_next，等弹窗确认后推进。
	if not (dialogue_effects is Dictionary):
		return false
	return EffectProcessor.apply(dialogue_effects, {"on_name_child": _open_name_child_popup})

func translate_condition(condition) -> String:
	return condition.description


## ---- 孩子取名弹窗（name_child effect） ----
const NameChildPopup := preload("res://components/name_child_popup.tscn")

## 弹出取名弹窗。孩子 npc 条目已由 EffectProcessor._add_child_npc 在 apply name_child 时创建
## （含 child 标签，名字先填 default），这里只负责弹窗并把确认的名字写回 Player.npc[child_id]["name"]。
func _open_name_child_popup(cfg: Dictionary) -> void:
	var default_name: String = cfg.get("default", "伊莱克")
	var child_id: String = cfg.get("id", "adopted")

	var popup = NameChildPopup.instantiate()
	popup.confirmed.connect(_on_child_named.bind(child_id))
	OverlayRoot.push_overlay(popup, {"modal": true, "esc_closes": false})
	# setup 必须在弹窗入树、_ready 跑完（@onready 节点就绪）之后调用，
	# 否则 _input 仍为 Nil：默认名写不进输入框，确认时 _emit 取不到名字，
	# 导致 name_child 取名彻底失效。
	popup.setup.call_deferred(default_name)


## 玩家在弹窗里确认名字后：写回名字；若由选项触发则继续推进对话。
func _on_child_named(name: String, child_id: String) -> void:
	if name != "" and Player.npc.has(child_id):
		Player.npc[child_id]["name"] = name
	if _pending_next != -1:
		var n := _pending_next
		_pending_next = -1
		dialogue_index = n
		display_next_dialogue()
