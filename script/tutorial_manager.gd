extends Node
## 教程管理器（autoload `TutorialManager`）—— 只负责「教程轨迹」的状态账本。
##
## 设计变更（2026-09-16 用户拍板，D-DOC25）：**废弃原「数据驱动 overlay 步骤序列」实现**。
##   旧实现：`resoures/tutorials/<seq>.json` 步骤表 + `scene/tutorial_overlay.tscn` 弱引导层
##           + `start_sequence()` 逐步推进（已整体删除）。
##   问题：教程内容被切成"步骤 + 等待条件"，与真正的剧情/场景两套并行维护，
##         改剧情就要同步改步骤表；overlay 层与业务弹窗抢层级（D-UI6）；无法承载"两个独立场景"。
##   新实现：教程内容是**普通剧情**（beginning.json）+ 普通触发器 + 普通 effect，
##         由教程场景（tutorial_1.tscn → home.tscn）自己串起来，
##         管理器只留两件事：
##           1. 「进行中」= 玩家持有门控 tag `TUTORIAL_GATE_TAG`（"进行新手教程"）；
##           2. 「已完成」= `Player.tutorial_progress[seq_id] > 0`。
##
## 门控 tag 的**授予点唯一**：`scene/selection.gd::before_trans()`，
## 即"只有通过角色创建(selection)进入教程"这一条路径会打 tag
## （用户 2026-09-16 明确要求）。读档进主城、地图传送、debug 场景都不会打。
## 摘除点唯一：`complete_tutorial()`（教程最后一段对话落地「教程完成」tag 时由 home.gd 调用）。
##
## 场景侧集成（无需再订阅任何 EventSignal）：
##   - `tutorial_1.tscn`（第一段，学校背景）：进场自动播身世 → 报纸 → 主角卡进手牌 → 回家触发器。
##   - `home.tscn`（第二段，家业）：管家引导 → 家业教导（**终点**）。
##     「第一天最后的教导」末句落地 `教程完成` tag → home.gd 收到 dialogue_finished 后
##     调 `complete_tutorial("opening")`。（2026-10-23 压缩流程：点一次管家 → 点一次家业即结束）
##
## 教程门控（全部只认 `TUTORIAL_GATE_TAG` 一个 tag，不绑具体剧情 beat）：
##   - `resoures/spots.json` 的 `返回_主城.locked_when:["进行新手教程"]` → 家业期间不能返回主城；
##   - `components/main_ui.gd` 的「下一天」拦截 → 回家执行前点了只弹提示；
##   - `components/main_ui.gd` 的 `_restore_hand()` → 切场景后把手牌里的主角/管家卡补回；
##   - `scene/home.gd` 的家业首次教导。

## 门控 tag：教程"进行中"的唯一正向标志。
const TUTORIAL_GATE_TAG := "进行新手教程"
## 主教学序列 id（唯一在用；保留 id 参数是为了将来可能有第二条教程线）。
const SEQ_OPENING := "opening"
## 最终剧情收尾的标记 tag：最后一段对话的 effect 落地它，场景据此调 complete_tutorial。
const TUTORIAL_DONE_TAG := "教程完成"
## 孤儿院「首次到访」标记 tag（2026-09-26）：教程刚结束 = 玩家尚未进行任何事件。
## 授予点唯一 = 本文件 complete_tutorial；摘除点 = TriggerPopup._finalize_phase（点击并确定触发器）
## 与 PlotImporter.add_plot（进入任何剧情）。持有它时去孤儿院走「直接去孤儿院」完整剧情，
## 否则走复访分流（见 resoures/triggers/trigger.json 的「收养孩子」）。
const FIRST_VISIT_TAG := "与小七相遇"

## 教程通篇奖励（2026-10-23 用户拍板）：完成新手教程一次性 **+45**。
## 与开局 5、每日 −5 一起构成经济节奏（3 处口径见 `player.gd` 的 `player_money` 注释）。
## ⚠️ 只能落在 `complete_tutorial()` 首个「未完成」分支里 —— 该函数幂等，
##    已完成的档再进不会重复发钱。
const TUTORIAL_MONEY_REWARD := 45


## 某序列是否已完成。`tutorial_progress` 缺省为 0 = 未完成。
## `selection.gd` 据此决定角色创建后进教程第一段还是直接进主城。
func is_completed(seq_id: String = SEQ_OPENING) -> bool:
	return int(Player.tutorial_progress.get(seq_id, 0)) > 0


## 教程是否进行中 = 玩家是否持有门控 tag。
## 注意：这是**状态查询**，不是"是否有 overlay 在跑"（旧实现的语义已废弃）。
func is_active() -> bool:
	return Player.player_has_tags([TUTORIAL_GATE_TAG])


## 场景无关的教程收尾兜底（2026-10-14）：
## 玩家执行过家业后「返回主城」已放行（spots.json 的 locked_when_not），教程最后一段
## 「我的思考」可能在 home 之外的场景播完 —— home.gd 的 dialogue_finished 收尾不在场，
## 门控 tag / 教程进度 / 「与小七相遇」就永远落地不了。这里订阅 dialogue_finished 自检，
## 与 home.gd 的调用重复无害（complete_tutorial 幂等）。
## 连接在 autoload 初始化时建立 → 回调排在场景脚本之前，home.gd 随后重算门控时 tag 已摘。
func _ready() -> void:
	if EventSignal.has_signal("dialogue_finished"):
		EventSignal.dialogue_finished.connect(_on_dialogue_finished)


func _on_dialogue_finished() -> void:
	if Player.player_has_tags([TUTORIAL_DONE_TAG]):
		complete_tutorial(SEQ_OPENING)


## 标记教程完成：写进度 + 摘门控 tag + 发教程奖励 + 解锁「下一天」+ 存档。幂等。
func complete_tutorial(seq_id: String = SEQ_OPENING) -> void:
	if is_completed(seq_id):
		# 已完成但仍残留门控 tag（异常存档）→ 兜底清掉，避免教程门控永久生效。
		remove_gate_tag()
		return
	Player.tutorial_progress[seq_id] = 1
	# 教程奖励（2026-10-23）：开局 5 → 教程结束 50。必须排在下面的幂等 return 之后，
	# 否则读档 / 重复调用会一直刷钱。
	Player.player_money += TUTORIAL_MONEY_REWARD
	remove_gate_tag()
	# 孤儿院首次到访标记：教程刚结束、玩家还没做过任何事 → 第一次去孤儿院走完整剧情。
	# 调用方有两处，都幂等：home.gd 的 dialogue_finished（在 home 场景内收尾）+ 本文件
	# _on_dialogue_finished（场景无关兜底，执行过家业离开家业后也能收尾）。
	Player.grant_tag(FIRST_VISIT_TAG)
	unlock_next_day()
	SaveLoader.save_game()


## 重置（调试 / 二周目）：清完成标记 + 重新挂门控 tag + 存档。
func reset_tutorial(seq_id: String = SEQ_OPENING) -> void:
	Player.tutorial_progress.erase(seq_id)
	grant_gate_tag()
	SaveLoader.save_game()


## 挂门控 tag（幂等）。授予点只有一个 —— selection.gd。
func grant_gate_tag() -> void:
	if not Player.player_has_tags([TUTORIAL_GATE_TAG]):
		Player.grant_tag(TUTORIAL_GATE_TAG)


## 摘门控 tag（幂等）。教程完成 / 异常存档兜底时调用。
func remove_gate_tag() -> void:
	if Player.player_has_tags([TUTORIAL_GATE_TAG]):
		Player.remove_tag(TUTORIAL_GATE_TAG)


## 解锁当前场景 Main_ui 的「下一天」按钮。
## 旧实现在教学步骤里 `_set_next_day_locked(false)` 逐步解锁；新实现只有 selection 的
## 代码路径会碰这个开关，教程结束必须显式置回 false，否则会残留在锁定态。
func unlock_next_day() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var main_ui: Node = scene.get_node_or_null("Main_ui")
	if main_ui != null:
		main_ui.is_next_day_locked = false
