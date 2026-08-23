extends Node2D

## 新手引导场景：角色创建(selection)完成后自动进入。
## 只负责场景装配（角色显隐、回家切场景），引导推进全部交给 TutorialManager
## （数据驱动、弱引导）。完成教学后，玩家点「次日」即进入主城 main.tscn。
## 若教学已完成（读档/二周目），直接跳主城，不在此停留。

@onready var sicourge = $sicourge
@onready var hero = $hero


func _ready() -> void:
	# 教学已完成 → 直接进主城，避免卡在引导场景
	if TutorialManager.is_completed("opening"):
		Player.path = "res://scene/main.tscn"
		get_tree().change_scene_to_file('res://scene/main.tscn')
		return

	# 教学期间把 Player.path 指向本场景，使「次日」重载时仍停留引导场景而非跳走。
	Player.path = "res://scene/guide.tscn"
	sicourge.hide()
	EventSignal.dialogue_finished.connect(change)
	TutorialManager.start_sequence("opening")

	# 仅在教学第 0 步时自动播开场自述，免去手动点角色；中途读档/重玩不重播。
	if int(Player.tutorial_progress.get("opening", 0)) == 0:
		_auto_start_opening()


## 自动触发主角的开场对白（仅首次进入、且当前无任何对话在进行时）。
func _auto_start_opening() -> void:
	if hero == null or Player.is_dialogue_exist:
		return
	var dialog = hero.get_dialog()
	if dialog != null:
		PlotImporter.add_plot(dialog["path"], dialog["name"])


## 对话结束后根据剧情标签调整场景（「第二天剧情」读完后管家斯库奇现身）。
func change() -> void:
	if Player.player_has_tags(["第二天剧情"]):
		sicourge.show()
		hero.hide()


## 调试按钮占位（guide.tscn 中遗留的 "debug" 按钮连接此信号，
## 方法缺失会导致场景加载时信号连接报错；保留为安全空实现）。
func _on_button_pressed() -> void:
	pass
