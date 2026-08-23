extends Control

## 标题界面 —— 关闭缺陷 D-SV8（存档 GDD §4.6）：
##   ① 有存档时「继续游戏」可用，并在下方显示存档摘要（第 N 天 · 名字 · 保存时间）；
##      无档 / 坏档 / 版本不兼容 → 按钮禁用 + 显示具体原因，而不是点了崩。
##   ② 「新游戏」在已有存档时先二次确认，避免静默覆盖进度（F3）。
##   ③ 新游戏前把 Player 清回默认（返回标题再开新档时，上一局残留会污染新档）。

const SELECTION_SCENE := "res://scene/selection.tscn"
const CONFIRM_DIALOG_PATH := "res://components/confirmdialog.tscn"

@onready var _continue_btn: Button = $Continue
@onready var _start_btn: Button = $Start
@onready var _achievement_btn: Button = $Achievement
@onready var _exit_btn: Button = $Exit
@onready var _hint: Label = $SaveHint


func _ready() -> void:
	_continue_btn.pressed.connect(_on_continue_pressed)
	_start_btn.pressed.connect(_on_new_game_pressed)
	_achievement_btn.pressed.connect(_on_achievement_pressed)
	_exit_btn.pressed.connect(_on_exit_pressed)
	refresh_save_state()


## 刷新「继续」可用性与存档摘要。标题重新进入时调用。
func refresh_save_state() -> void:
	var info: Dictionary = SaveLoader.peek_save_info()
	if info.is_empty():
		_continue_btn.disabled = true
		# 区分「本来没档」和「有档但读不了」，后者要让玩家知道是坏档而不是自己没存过
		var why: String = SaveLoader.last_error
		_hint.text = ("尚无存档" if why.find("没有找到") >= 0 else "存档不可用：%s" % why)
		return
	_continue_btn.disabled = false
	var who: String = String(info.get("player_name", ""))
	var day: int = int(info.get("time", 1))
	var when: String = String(info.get("saved_at_text", ""))
	_hint.text = "存档：第 %d 天 · %s%s" % [day, who, "" if when == "" else " · 保存于 " + when]


func _on_continue_pressed() -> void:
	if not SaveLoader.load_game():
		# 上一次刷新之后存档被删/被改坏也不会崩，就地更新提示
		_hint.text = "无法继续：%s" % SaveLoader.last_error
		refresh_save_state()


func _on_new_game_pressed() -> void:
	if not SaveLoader.has_save():
		_start_new_game()
		return
	var info: Dictionary = SaveLoader.peek_save_info()
	_confirm(
		"开始新游戏",
		"已有存档（第 %d 天 · %s）。\n开始新游戏会在建角色结束时覆盖它，确定继续吗？" % [
			int(info.get("time", 1)), String(info.get("player_name", ""))],
		_start_new_game)


func _start_new_game() -> void:
	# 清掉上一局残留（返回标题→新游戏 的场合），并换一枚反 SL 种子
	SaveLoader.reset_to_new_game()
	get_tree().change_scene_to_file(SELECTION_SCENE)
	EventSignal.scene_entered.emit(SELECTION_SCENE)


func _on_achievement_pressed() -> void:
	AchievementManager.open_list()


func _on_exit_pressed() -> void:
	get_tree().quit()


## 二次确认。复用既有 confirmdialog；取不到组件时降级为直接执行（不阻断玩家）。
func _confirm(dialog_title: String, message: String, on_confirm: Callable) -> void:
	var scene: PackedScene = load(CONFIRM_DIALOG_PATH)
	if scene == null:
		push_warning("loading: 找不到 %s，跳过二次确认" % CONFIRM_DIALOG_PATH)
		on_confirm.call()
		return
	var dialog: Node = scene.instantiate()
	# confirmdialog 是 PopupPanel(Window)，OverlayRoot 会自动挂到 root 而非 CanvasLayer
	OverlayRoot.push_overlay(dialog, {
		"modal": true,
		"esc_closes": true,
		"close_method": "close_dialog",
	})
	dialog.setup(dialog_title, message)
	dialog.confirmed.connect(func() -> void: on_confirm.call())
