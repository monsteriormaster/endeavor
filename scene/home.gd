extends Node2D

## 家业场景（教程第二段 + 常规家园）。**同一个场景，按「进行新手教程」tag 分流**：
##   持有 tag  = 教程进行中（刚执行完「回家」进来）→ 教程编排生效；
##   无   tag  = 常规家园 → 全部教程分支静默跳过，与普通场景无异。
##
## 本场景涉及的 5 条显隐 / 可用性规则（用户 2026-09-16 拍板；2026-10-16 家业主线实装补第 5 条）：
##   1. 管家寺库奇（$HomeMap/sicourge）：**持有 tag `出现管家` 才出现**（场景自己决定显隐，
##      没有这个 tag 就不显示）。`出现管家` 的**授予点 = 「回家」触发器的结算结果**
##      （`trigger_popup.gd::_compute_go_home_result` 的 `effect.tags`，进家业前落地）；
##      **摘除点 = 「斯库奇引导1」末句 effect 的 `remove_tags`** —— 也就是说：与管家的第一次
##      对话一结束，`出现管家` 消失 → 管家连同地图入口一起消失，同时（同一句 effect 的
##      `add_to_hand`）管家卡进入手牌。此后一切都靠手牌 + 「与同伴交流」推进，
##      地图上不再留第二个入口（因此也不会出现「点他没反应」的死按钮）。
##   2. 「处置丹尼斯」两张牌 —— `私下处置丹尼斯`（$HomeMap/dispose_home）、
##      `将丹尼斯移交警方`（$HomeMap/dispose_law）：**持有 `处理丹尼斯的方法` 才出现**。
##      规则声明在 `resoures/triggers/trigger.json` 各自触发器的 `show_when.tags`（数据化），
##      由 `trigger_spot.gd::_refresh_visibility` 落地——本文件不重复实现判据，避免两处分叉。
##   3. 「返回主城」：由 `spots.json` 的 `返回_主城.locked_when:["进行新手教程"]` 管控
##      （悬浮提示「发生了那么大的事，先问问管家吧。」）。门控在 scene_spot 里只在 `_ready/setup()`
##      结算一次，而教程是在本场景内结束的 → 本文件负责在收尾时**主动重算**。
##   4. 「家业管理」首次点击 → 播「第一天最后的教导」（仅 1 次，落地「家业教导完成」）。
##      **这一段同时是教程终点**（2026-10-23 压缩流程）：末句 effect 落「教程完成」→
##      本文件收到 dialogue_finished → `TutorialManager.complete_tutorial()`。
##      也就是说教程的完整节奏只剩两步：**点一次管家（斯库奇引导1）→ 点一次家业（本段）**。
##   5. 家业主线（剧情线3）三个调查触发点（2026-10-16 实装）**不在本场景**：
##      `群死凶器的调查` → 商业街、`群死常规的处理的调查` / `调查丹尼斯` → 主城
##      （用户 2026-10-16 拍板：地图与任务板不冲突，主城总览也挂触发器）。
##      入口链 = 教程终点「我的思考」给管家入队「与管家交流群死前」→ 与同伴交流播放该剧情授 tag
##      → 凶器（商业街）/ 警方（主城）显；调查完结「调查丹尼斯之夜」授「处理丹尼斯的方法」
##      → 第 2 条的处置两点显。跨场景授 tag 的即时刷新由
##      `trigger_spot.gd` 订阅 `EventSignal.trigger_flow_completed` 全局完成（本场景内不再逐个推）。
##
## 注意区分两套 tag（不要混用）：
##   - `出现管家` 管**管家这一个 NPC 的显隐**（场景自己判，见规则 1）；
##   - `进行新手教程` 管**教程流程门控**（下一天拦截、返回锁定、家业教导分流），授予点唯一在
##     `selection.gd::before_trans()`，摘除唯一在 `TutorialManager.complete_tutorial()`。
##   管家不用门控 tag 判定：门控 tag 覆盖整段教程，而管家只该在「进家 → 第一次对话结束」这一小段出现。
##
## 终点：**「第一天最后的教导」（点家业那一次）落地「教程完成」tag** → 本文件收到
## dialogue_finished 后调 TutorialManager.complete_tutorial("opening") → 摘「进行新手教程」
## → 返回主城解锁（下一天同步解封）。2026-10-23 起教程只剩两步：点管家 → 点家业。
## （管家**不在这里**消失：他的显隐认 `出现管家`，早在「斯库奇引导1」末句就已摘除并转入手牌。）

@onready var _estate: TriggerSpot = $HomeMap/estate
@onready var _sicourge: Node = $HomeMap/sicourge
## 「返回主城」传送点（scene_spot）：教程期间被 locked_when 锁住，教程结束需重算解锁。
@onready var _exit_spot: Node = $HomeMap/Exit

var _estate_original: Callable


func _ready() -> void:
	# 拦截「家业管理」触发器：教程期间首次点击先播「第一天最后的教导」。
	# 先断开 tscn 里编辑器连的原回调，改由本脚本转发（原回调存下来，非教程路径照常调用）。
	_estate_original = Callable(_estate, "_on_pressed")
	if _estate.pressed.is_connected(_estate_original):
		_estate.pressed.disconnect(_estate_original)
	_estate.pressed.connect(_on_estate_pressed)

	EventSignal.dialogue_finished.connect(_on_dialogue_finished)
	_refresh_scene_gates()


## 家业管理：教程进行中且尚未教导 → 播「第一天最后的教导」；否则正常打开触发器。
func _on_estate_pressed() -> void:
	if TutorialManager.is_active() and not Player.player_has_tags(["家业教导完成"]):
		PlotImporter.add_plot("res://resoures/plot/misson/beginning.json", "第一天最后的教导")
	else:
		_estate_original.call()


func _on_dialogue_finished() -> void:
	# 教程终点：最后一段「我的思考」落地「教程完成」→ 收尾（摘门控 tag、存档、解锁下一天）。
	# complete_tutorial 幂等，因此对每一段对话都无脑检查是安全的。
	if Player.player_has_tags([TutorialManager.TUTORIAL_DONE_TAG]):
		TutorialManager.complete_tutorial(TutorialManager.SEQ_OPENING)
	_refresh_scene_gates()


## 重算所有「tag → 显隐 / 可用性」的落点（场景自身的门控在这里统一结算）。
## 必须在三处调用：进场景（_ready）、每段对话结束（剧情 effect 可能刚改 tag）、教程收尾之后。
##
## 为什么管家显隐由本文件管、不交给 character.gd：显隐是**场景级**问题（「这个家的入口该不该
## 画在图上」），判据只写一处才不会出现第二种真相；且 `_ready` 进场景时就要求算出正确初值，
## 而 character.gd 并没有「按 tag 决定自己在不在图上」的能力。
## 另注意 Godot 初始化顺序：子节点 `_ready` 先于父节点 → 订阅 `dialogue_finished` 时
## character.gd 的回调也会先跑；本文件统一在收尾之后重算，顺序才不受影响。
func _refresh_scene_gates() -> void:
	# 1. 管家：由场景按 tag 决定 —— 持有 `出现管家` 才出现，没有就不显示。
	#    授予 =「回家」结算结果（trigger_popup._compute_go_home_result 的 effect.tags）
	#    摘除 =「斯库奇引导1」末句 effect 的 remove_tags（同一句里 add_to_hand 让管家进手牌）
	if _sicourge != null:
		_sicourge.visible = Player.player_has_tags(["出现管家"])
	# 2. 处置丹尼斯×2：显隐判据在 trigger.json 的 show_when，本文件只负责「同一时刻推一把」，
	#    以免管家换了状态而这两张牌还停在上一帧。
	_refresh_gated_spot("dispose_home")
	_refresh_gated_spot("dispose_law")
	# 3. 「返回主城」：scene_spot 的门控只在 setup() 里结算一次，
	#    教程是在本场景内结束的（tag 在场景存活期间被摘除），因此必须主动重算，否则要等下次重进才解锁。
	if _exit_spot != null and _exit_spot.has_method("setup"):
		_exit_spot.setup()


## 让某个受管触发点按 trigger.json 的 show_when 重新结算显隐（TriggerSpot 内的唯一入口）。
func _refresh_gated_spot(node_name: String) -> void:
	var spot: Node = get_node_or_null("HomeMap/" + node_name)
	if spot != null and spot.has_method("_refresh_visibility"):
		spot._refresh_visibility()
