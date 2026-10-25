extends Control

## 为孩子取名弹窗：由对话系统 `name_child` effect 触发。
##
## 经 OverlayRoot 以 modal + esc_closes=false 呼出，强制玩家取名后才能继续。
## 对外发 `confirmed(name)` 信号；dialogue_ui 监听它把名字写回 Player.npc[child_id]["name"]。

signal confirmed(name: String)

@onready var _input: LineEdit = $Panel/Margin/VBox/LineEdit
@onready var _confirm: Button = $Panel/Margin/VBox/ConfirmButton


func _ready() -> void:
	_confirm.pressed.connect(_on_confirm)
	_input.text_submitted.connect(_on_submitted)


## 预填默认名，聚焦并全选（首次按键即替换默认名）。
func setup(default_name: String) -> void:
	_input.text = default_name
	_input.placeholder_text = default_name
	_input.grab_focus.call_deferred()
	_input.select_all()


func _on_confirm() -> void:
	_emit()


func _on_submitted(_submitted_text: String) -> void:
	_emit()


func _emit() -> void:
	var nm: String = _input.text.strip_edges()
	if nm == "":
		nm = _input.placeholder_text
	confirmed.emit(nm)
	# 组件自身收尾走 OverlayRoot.close_overlay（会自动出栈并 queue_free）。
	if not OverlayRoot.close_overlay(self):
		queue_free()
