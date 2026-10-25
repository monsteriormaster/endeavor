extends Control
## 通用确认弹窗（纸 + 铜 + 墨）。
##
## ▍2026-10-06 重制：从「引擎默认 `PopupPanel`」收口到本作画风 + 画面居中。
##   旧的三个毛病：① 吃引擎默认深灰皮肤，和「彩铅画在纸上」对撞；
##   ② `position` 写死 `(90,200)`，不在画面中央；③ 正文 Label 没有 `autowrap`，
##   多行警告会被裁掉、字又小又糊。
##
## ▍为什么不再用 `PopupPanel`(Window)：
##   · Window 的 `styles/panel` 只能是**可拉伸**的 `StyleBox`，而纸面板是**整张烤死**
##     的手绘框（主铜框 + 内缘两道 + 四角饰线 + 顶中菱形）—— 拉伸会在中段糊掉，
##     切九宫格又会把四角饰线撕成两段（见 skill《Godot 纸面板改造》§一）。
##   · Window 渲染在所有 `CanvasLayer` 之上，暖色遮罩盖不到它下面，做不出「压暗突出」。
##   改成 `Control` 后与工程其余 5 个弹窗（`check_ui` / `trigger_popup` / `dialogue_ui` /
##   `result_popup` / `name_child_popup`）完全同构：**居中靠 anchor preset 8**，
##   遮罩是两层 `mouse_filter = 2`(IGNORE) 的 `ColorRect`，输入门控交给 OverlayRoot
##   的 `ModalBlocker` —— 顺带绕开了 `OverlayRoot._attach()` 里那三条 Window 特例分支。
##
## ▍素材：`art/ui/confirm_panel.png` 600x360 整张烤死（四周 PAD 18，布局里让开 42）。
##   生成脚本 `design/_tools/make_confirm_assets.py`，与 `trig_panel` / `check_panel` /
##   `dlg_panel` 同一套 `paper_sheet` 画法。标题下的铜线复用 `components/ui_rule.gd`，
##   零新素材；按钮由 Autoload `ButtonSkin` 统一套 `art/ui/btn_paper_{l,s}.png`。

## 纸上墨色。全局主题的 `Button/colors/font_color` 是**纯黑**，与墨色不一致 → 局部覆盖。
const INK := Color(0.180, 0.141, 0.094)

var my_title: String = ''
var message: String = ''
var confirm_text: String = '确认'
var cancel_text: String = '取消'

signal confirmed()
signal canceled()


## `setup()` 可以在**入树之前**调用（`selection.gd` 就是先 setup 再 push_overlay），
## 所以这里刻意不用 `@onready` —— `$` 只在自身子树里查找，不要求已在场景树中。
func setup(cur_title: String, cur_message: String,
		cur_confirm_text: String = '确认', cur_cancel_text: String = '取消') -> void:
	my_title = cur_title
	message = cur_message
	confirm_text = cur_confirm_text
	cancel_text = cur_cancel_text
	update_ui()


func update_ui() -> void:
	var title_l := $Panel/MarginContainer/VBoxContainer/title as Label
	var message_l := $Panel/MarginContainer/VBoxContainer/message as Label
	var cancel_btn := $Panel/MarginContainer/VBoxContainer/buttonbox/cancelbutton as Button
	var confirm_btn := $Panel/MarginContainer/VBoxContainer/buttonbox/confirmbutton as Button

	title_l.text = my_title
	message_l.text = message
	cancel_btn.text = cancel_text
	confirm_btn.text = confirm_text

	# 幂等：`setup()` 可能被调用不止一次，重复 connect 会让一次点击发多次信号。
	if not cancel_btn.pressed.is_connected(_on_cancel_pressed):
		cancel_btn.pressed.connect(_on_cancel_pressed)
	if not confirm_btn.pressed.is_connected(_on_confirm_pressed):
		confirm_btn.pressed.connect(_on_confirm_pressed)

	_style_button(cancel_btn)
	_style_button(confirm_btn)


## 只管**字色**。四态样式盒由 Autoload `ButtonSkin` 在 `node_added` 时统一套好，
## ⚠️ 这里绝不能再 `add_theme_stylebox_override` —— 那会顶掉全局皮（`check_ui` 踩过）。
func _style_button(btn: Button) -> void:
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(slot, INK)


func _on_confirm_pressed() -> void:
	confirmed.emit()
	close_dialog()


func _on_cancel_pressed() -> void:
	canceled.emit()
	close_dialog()


func close_dialog() -> void:
	# 延迟 hide：避免在输入回调栈内同步 hide 导致 Viewport 输入状态损坏（卡死）
	hide.call_deferred()
	if not OverlayRoot.close_overlay(self):
		queue_free()
