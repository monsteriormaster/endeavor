## 行动队列面板 —— 列出 ActionQueue 中进行中 / 待结算的行动。
## M5（2026-08-23）：补上原缺失的异步结算消费者。
##   - 进行中：显示「等待 N 回合」；
##   - 已完成：显示「已完成」+「结算」按钮 → 弹 ResultPopup → on_confirm 落地。
## 落地语义：effect **直落 player_tags**（异步流程早已结束，不走 flow_tags），
## 归还占用人物卡到卡牌区、书卡入卡牌区、plot({"path","name"}) 调 PlotImporter.add_plot。
class_name ActionPanel
extends Control

@onready var list: VBoxContainer = $Panel/Margin/VBox/Scroll/List
@onready var empty_label: Label = $Panel/Margin/VBox/Scroll/List/Empty


func _ready() -> void:
	ActionQueue.actions_changed.connect(_refresh)
	# action_completed 带 1 个参数（action_id）—— _refresh 必须收得下，否则每次有天行动
	# 完成都刷一条 ERROR（2026-10-14 用户实机日志抓到：教程第 2 天「回家」结算时）。
	ActionQueue.action_completed.connect(_refresh)
	_refresh()


func _refresh(_action_id: String = "") -> void:
	for c in list.get_children():
		if c == empty_label:
			continue
		c.queue_free()
	var actions: Array = ActionQueue.get_actions()
	empty_label.visible = actions.is_empty()
	for a in actions:
		_add_row(a)


func _add_row(a: Dictionary) -> void:
	var row := HBoxContainer.new()
	var status := "已完成" if bool(a.get("completed", false)) else "等待 %d 回合" % int(a.get("wait", 0))
	var lbl := Label.new()
	lbl.text = "%s（%s）" % [String(a.get("trigger_id", "")), status]
	# 墨色字（面板已改奶油纸底，默认黑字虽可读，统一成与标题一致的墨棕更协调）。
	lbl.add_theme_color_override("font_color", Color(0.152941, 0.113725, 0.0705882, 1))
	lbl.add_theme_font_size_override("font_size", 16)
	row.add_child(lbl)
	if bool(a.get("completed", false)):
		var btn := Button.new()
		btn.text = "结算"
		btn.pressed.connect(_on_settle.bind(String(a.get("id", ""))))
		row.add_child(btn)
	list.add_child(row)


func _on_settle(action_id: String) -> void:
	# 结算语义已收敛到 ActionQueue.settle（单一来源），本面板只负责入口。
	ActionQueue.settle(action_id)
