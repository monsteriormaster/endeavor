extends Node2D

## 新手教程第一段（独立场景，学校背景）：角色创建(selection)完成后自动进入。
## 流程（用户定制 2026-08-27 / 2026-09-16 独立场景版）：
##   进场自动播身世「游戏开始」→ 自动接「第二天剧情」（报纸）→ 主角卡进手牌 →
##   拖主角卡入「回家」触发器 → 执行（等待 1 回合）→ 关闭 → 点「下一天」→
##   过天结算（「我迫不及待回家看看了」）→ 进入家业 home.tscn（第二段）。
## 教学期间「下一天」由 main_ui 拦截（无「想回家了」tag 时弹提示、不进入下一天）。

var _newspaper_launched := false


func _ready() -> void:
	# 教学已完成 → 直接进主城，避免卡在教程场景
	if TutorialManager.is_completed("opening"):
		Player.path = "res://scene/main.tscn"
		get_tree().change_scene_to_file('res://scene/main.tscn')
		return

	Player.path = "res://scene/tutorial_1.tscn"
	EventSignal.dialogue_finished.connect(_on_dialogue_finished)
	# 进场自动播身世；读档回 tutorial_1 时按进度接续，避免重复播。
	if not Player.player_has_tags(["游戏开始"]):
		PlotImporter.add_plot("res://resoures/plot/misson/beginning.json", "游戏开始")
	elif not Player.player_has_tags(["第二天剧情"]):
		_newspaper_launched = true
		call_deferred("_launch_newspaper")


## 身世对话结束 → 自动接报纸。
func _on_dialogue_finished() -> void:
	if Player.player_has_tags(["游戏开始"]) and not Player.player_has_tags(["第二天剧情"]) and not _newspaper_launched:
		_newspaper_launched = true
		call_deferred("_launch_newspaper")


## 延迟一帧再接报纸，避免在对话结束回调里直接嵌套启动新对话导致状态竞争。
func _launch_newspaper() -> void:
	PlotImporter.add_plot("res://resoures/plot/misson/beginning.json", "第二天剧情")
