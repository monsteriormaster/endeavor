extends Node

## 作弊：快捷键加减金钱（纯开发用，2026-10-23 应用户要求新增）。
##
## 按键（任何时候都生效，聊天框/名字输入框聚焦时除外）：
##   Ctrl + =（或 +）  加 10 钱
##   Ctrl + Shift + =  加 100 钱
##   Ctrl + -          减 10 钱
##   Ctrl + Shift + -  减 100 钱
##
## 实现口径：
## - 只写 `Player.player_money`（setter 自带 `stats_changed.emit()`，HUD 自动刷新；
##   存档走 `SaveLoader.PERSISTENT_FIELDS` 的 `player_money`，会正常存进档里）。
## - 不碰任何 JSON / 触发器 / 成就 —— 作弊加的钱不区分来源，与正常收入同权。
## - `_unhandled_key_input`：只吃没人处理的按键，不与 Esc 关面板等既有链路抢输入；
##   若 OverlayRoot 已把当次按键标记为 handled，这里天然收不到。
## - 输入框兜底：焦点在 LineEdit / TextEdit / SpinBox 上时直接忽略（防名字输入误触）。
## - 金额不夹负：金钱可以为负（经济系统没设下限），照实扣。

## 单次加减的基础金额。Shift 按住时放大 10 倍。
const BASE_AMOUNT := 10


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if not (key.ctrl_pressed or key.meta_pressed):
		return
	# 输入框聚焦时忽略（打字时 Ctrl+= / Ctrl+- 是常见快捷键位，不能抢）
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox:
		return

	var amount := 0
	if key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD:
		amount = BASE_AMOUNT
	elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
		amount = -BASE_AMOUNT
	if amount == 0:
		return
	if key.shift_pressed:
		amount *= 10

	Player.player_money += amount
	var sign_str := "+" if amount > 0 else ""
	print("[Cheat] 金钱 %s%d → %d" % [sign_str, amount, Player.player_money])
	get_viewport().set_input_as_handled()
