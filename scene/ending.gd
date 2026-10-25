extends Control
## 结局结算页（通关 / 破产共用）。class_name 是给调用方写 `EndingPage.enter_with()` 用的，
## 工程里没有第二个 EndingPage（main_ui 与 trigger_manager 都只按路径 load 本场景）。
class_name EndingPage

## **通关结算页**（D-END2，2026-10-23）——「第 20 天 + 当天结局剧情」之后的那一屏。
##
## ▍口径（用户 2026-10-23 原话）：「制作结算页面：完成 20 天以及当天的剧情后黑屏中间
##   四个字：感谢你的游玩；获得成就：谢谢你体验完完整游戏，并制作对应图标」。
##
## ▍2026-10-23 追加：破产也走这一屏
##   用户原话「如果钱扣到负数：达成破产结局；成就：恭喜你破产了；画对应图标；
##   破产后出现游戏结束，但是中间的字是恭喜你破产了，再次点击回到主菜单」。
##   调用方是 `components/main_ui.gd::_trigger_bankruptcy()`，进来之前先
##   `EndingPage.enter_with("恭喜你破产了", "恭喜你破产了")`。
##
## ▍它接在哪里
##   `TriggerManager._perform_game_ending()`（毕业剧情最后一段播完）→ 存档 → 清覆盖层
##   → 切到本场景。旧的落点是 `scene/loading.tscn` 标题页（D-GRAD1，2026-10-16），
##   现在中间插了这一屏：结局播完先看「感谢你的游玩」，再回标题。
##
## ▍视觉
##   近黑底 + 居中一行「感谢你的游玩」。
##   **不是纯黑 #000000**：工程冻结规矩「不用纯黑」，这里用 #0A0807（暖墨黑）——
##   在黑屏语义下与纯黑不可分辨，但不踩那条红线。
##   文字色 #EDE4D2（纸白），字体走全局主题（资源圆体简中 Light），不另设字体。
##   整屏动效只有透明度，没有位移、没有色块：文字 1.6s 淡入 → 停 1.0s → 提示 0.8s 淡入。
##
## ▍成就
##   `_ready` 立刻解锁「谢谢你体验完完整游戏」并落盘。
##   刻意放在这里、而不是 `_perform_game_ending()` 里：
##     · 解锁会立刻往 OverlayRoot（层 50）推题签弹窗，而过场快照在层 120 ——
##       在收场那一刻解锁，弹窗 2s 生命的前 0.45s 全被快照盖着，露出来的时长不够看；
##     · 在本场景 `_ready` 解锁，弹窗正好在「黑屏落定」时出现（此时快照已淡到 0）。
##   落盘是因为 `_perform_game_ending()` 那次 save 发生在解锁**之前**，
##   不补一次，玩家「在结局页直接关窗口」就会丢掉这枚成就。
##
## ▍出口
##   提示淡入之后（约 3.4s）才接受输入；点任意处 / 任意键 / Esc → 过场回标题页。
##   不做自动返回：这是玩家最后能停留的一屏，不该被计时器赶走。
##
## ▍验收
##   `debug/_ending_page_probe.tscn`（配置 / 图标 / 场景结构 / 解锁 / 出口五组）。

const TITLE_SCENE := "res://scene/loading.tscn"
## 通关成就 id —— 必须与 `resoures/achievements.json` 的键逐字一致。
const ACH_ENDING := "谢谢你体验完完整游戏"
## 默认文案 = 通关那套。破产（2026-10-23）进来时由 `enter_with()` 改掉。
const DEFAULT_TEXT := "感谢你的游玩"

## ▍两种结局共用这一屏（2026-10-23）
##   通关 → 「感谢你的游玩」+ 成就「谢谢你体验完完整游戏」
##   破产 → 「恭喜你破产了」+ 成就「恭喜你破产了」
## 差别只有「中间那行字」和「解锁哪枚成就」，视觉 / 动效 / 出口完全一样，
## 所以不另开场景 —— 参数走这两个 static，由调用方在 `change_scene` **之前**写。
## ⚠️ `_ready` 读完立刻复位成默认：否则一局里先破产再通关（或反过来）会串味。
static var pending_text: String = DEFAULT_TEXT
static var pending_ach: String = ACH_ENDING

## 调用方入口。不传就用默认（通关）。
static func enter_with(text: String, ach_id: String) -> void:
	pending_text = text if text != "" else DEFAULT_TEXT
	pending_ach = ach_id if ach_id != "" else ACH_ENDING

## 正文淡入 / 停留 / 提示淡入（秒）。
const THANKS_FADE := 1.6
const HOLD := 1.0
const HINT_FADE := 0.8

@onready var _thanks: Label = $Thanks
@onready var _hint: Label = $Hint

## 提示出来之前不吃输入：防止连点把这一屏直接跳过（玩家根本没看清那行字）。
var _accept_input: bool = false
var _leaving: bool = false
## 本屏实际用的文案 / 成就 id（`_ready` 从 static 取一次，取完复位成默认）。
var _text: String = DEFAULT_TEXT
var _ach: String = ACH_ENDING


func _ready() -> void:
	_text = pending_text
	_ach = pending_ach
	pending_text = DEFAULT_TEXT
	pending_ach = ACH_ENDING

	_thanks.text = _text
	_thanks.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_hint.modulate = Color(1.0, 1.0, 1.0, 0.0)

	AchievementManager.unlock(_ach)
	SaveLoader.save_game()

	var tw := create_tween()
	tw.tween_property(_thanks, "modulate:a", 1.0, THANKS_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(HOLD)
	tw.tween_property(_hint, "modulate:a", 0.72, HINT_FADE) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_on_intro_done)


func _on_intro_done() -> void:
	_accept_input = true


## 任意键 / 鼠标点击 / 触屏 → 回标题。
## ⚠️ 2026-10-25：从 `_unhandled_input` 改成 `_input`。原因：`_unhandled_input` 只在
## **没有控件消费该事件**时才收到，而本场景根 Control 默认 `mouse_filter=STOP`（已改 IGNORE）
## 以及成就题签的覆盖层都可能先把点击吃掉 —— 表现就是「结局页怎么点都没反应」。
## `_input` 在 GUI 分发之前拿到事件，3.4s 输入门控（_accept_input）已经防住误触。
func _input(event: InputEvent) -> void:
	if not _accept_input or _leaving:
		return
	var pressed := false
	var mb := event as InputEventMouseButton
	if mb != null:
		pressed = mb.pressed
	else:
		var key := event as InputEventKey
		if key != null:
			pressed = key.pressed and not key.echo
		else:
			var touch := event as InputEventScreenTouch
			if touch != null:
				pressed = touch.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	leave()


## 回标题（过场由 SceneTransition 统一处理：抓帧 → 换场 → 淡出）。
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	SceneTransition.change_scene(TITLE_SCENE)


## 探针接口：一次把验收要用的读数交出去（探针不要自己另算）。
func probe_state() -> Dictionary:
	return {
		"ach_id": _ach,
		"ach_unlocked": AchievementManager.is_unlocked(_ach),
		"ending_ach_unlocked": AchievementManager.is_unlocked(ACH_ENDING),
		"thanks_text": _thanks.text if _thanks != null else "",
		"thanks_alpha": _thanks.modulate.a if _thanks != null else -1.0,
		"hint_text": _hint.text if _hint != null else "",
		"hint_alpha": _hint.modulate.a if _hint != null else -1.0,
		"accept_input": _accept_input,
		"leaving": _leaving,
	}
