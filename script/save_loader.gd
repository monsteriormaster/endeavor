"""
存档管理 —— 负责数据存档 / 读档（单档，明文 JSON）。

契约来源：design/存档系统策划案.md v0.1 §4（本文件为 D-SV1~D-SV9 的落地实现）

使用方法：
	SaveLoader.save_game()        # 存档，返回 bool（写盘失败不静默）
	SaveLoader.load_game()        # 读档 + 切回存档场景，返回 bool
	SaveLoader.has_save()         # 是否存在可用存档（标题「继续」按钮用）
	SaveLoader.peek_save_info()   # 只读摘要（天数/名字/版本/时间戳），不改 Player
	SaveLoader.delete_save()      # 删档（新游戏覆盖前可用）
	SaveLoader.apply_save_data(d) # 只把字典灌进 Player，不切场景（测试/迁移用）

关键纪律（GDD §8 内容准则）：
1. **白名单即契约**：`PERSISTENT_FIELDS` 是唯一真源。`Player` 新增任何玩法字段
   必须在此登记，否则会丢（player.gd 顶部注释的约定就是指这里）。
2. **读档宁可给默认，不可崩**：所有字段走 `.get(key, default)` + 类型矫正（D-SV3）。
   JSON 里数字一律是 float，必须按默认值类型回收成 int/float，否则赋给 int 字段会精度告警。
3. **瞬态绝不进存档**：`is_dialogue_exist` / `is_check_exist` / OverlayRoot 栈 / in-flight
   动画等（GDD §4.2）；读档时反而要主动清零，避免 F7 覆盖层残留。
4. **版本只增不降**：破坏性变更才自增 `SAVE_VERSION`（D-SV4）。
"""


extends Node

## 存档写入完成（ok=false 表示写盘失败）
signal save_completed(ok: bool)
## 读档完成（ok=false 表示无档 / 坏档 / 版本不兼容）
signal load_completed(ok: bool)

const SAVE_PATH := "user://endeavoursavegame.json"

## 存档格式版本（D-SV4）。破坏性变更（字段语义颠覆、无法前向填充）时才 +1。
const SAVE_VERSION := 1
## 能读取的最低版本。低于此值 → 友好拒绝，不崩（GDD §4.5）。
const MIN_SUPPORTED_VERSION := 1
## legacy 档（无 save_version 字段）按 0 处理，走前向填充。
const LEGACY_VERSION := 0

## 持久化字段白名单 + 缺失默认值（GDD §4.1）。
## 值的**类型**同时充当类型矫正的模板：int/float/String/Array/Dictionary。
const PERSISTENT_FIELDS := {
	# —— 场景锚点 ——
	"path": "",
	# D-SV10 剧情位置：{path, name, index, ctx}。读档后据此续播到中断的那一句
	# （save_loader.load_game → PlotImporter.resume_plot_if_any）。
	"plot": {},
	"exact_situation": {},
	# —— 时间 ——
	"time": 1,
	# —— 主角·属性 ——
	"player_app": 0,
	"player_int": 0,
	"player_str": 0,
	"player_bod": 0,
	"player_edu": 1,
	"player_bac": "男爵",
	"nobility": 1,                # D-NOB 贵族等级（1男爵~5公爵）
	"player_app_fact": "",
	"player_age": 16.0,          # D-SV7
	"player_att": 20,            # D-SV1 属性点
	"gift_att": 15,              # D-SV2 天赋点（2026-10-23 用户拍板初始 15）
	# —— 主角·资源 / 身份 ——
	# 开局 5（2026-10-23 用户拍板）：新游戏 = `reset_to_new_game()` → `apply_save_data({})`，
	# 取的就是这里的默认值，所以本行是「初始金钱」的唯一真源；教程结束 +45 见 TutorialManager。
	"player_money": 5,
	"player_name": "",
	# —— 主角·集合 ——
	# 装备：三槽字典 {weapon/armor/jewelry: 装备名}（2026-10-24 由数组改为字典，
	# 与 npc 条目的 equipment 同形态；老档的数组形态由 apply_save_data 归槽迁移）。
	"player_equipment": {},
	"player_tags": [],
	"player_num_tags": {},
	"player_stuff": [],
	# —— 手牌账本（D-HAND1，2026-10-14）：CardArea 是场景内节点，手牌真值在 Player.hand ——
	"hand": [],
	# D-HAND2（2026-10-14）：老档迁移**一次性**标记。缺这个字段 = 老档 → 允许迁移一次。
	"hand_migrated": false,
	"tag_turns": {},              # 带 turn 的 tag 剩余回合（疲惫 turn=5，读档后继续倒计时）
	# —— 成就 ——
	"achievements_unlocked": {},
	# —— 打听池已抽 id（随机不重复）——
	"inquiry_drawn": [],
	# —— 回合级触发器「本回合已消耗」卡 id（D-DOC24，{触发id: [卡id]}；过天清空）——
	"trigger_consumed": {},
	# —— 报纸日刊（剧情新闻队列 + 上一天随机效果 id + 当天报纸快照）——
	"pending_news": [],
	"pending_tags": [],   # D-PENDING-TAGS：次日生效 tag 队列（过天转正）
	"last_flavor": "",
	"daily_newspaper": {},
	# —— 孩子（已并入 npc，统一带 "child" 标签，随上方 "npc" 白名单自动持久化，不再单列）——
	# —— 毕业结局（D-GRAD1，2026-10-16）：stage ""/playing/done + 剩余剧情键队列。
	#    结局播到一半存档/读档，靠这两个字段把队列接回去（TriggerManager._on_dialogue_finished）。
	"graduation_stage": "",
	"graduation_queue": [],
	# —— 叙事 ——
	"development": {},
	"npc": {},
	# —— 教学 ——
	"tutorial_progress": {},
	# —— 反 SL（D-SV6）——
	"campaign_seed": "",
}

## 最近一次读档失败原因（供 UI 提示）。成功时为空串。
var last_error: String = ""


# ============================================================
#  对外主流程
# ============================================================

## 存档。返回是否写盘成功。
func save_game() -> bool:
	# 存档前把主角实时属性同步进主角卡，避免 npc.Hero 与 player_* 不一致
	if Player.has_method("hero_merge"):
		Player.hero_merge()

	# 存档前把**当前卡牌区视图**同步进账本（2026-10-24）：视图才是玩家此刻看到的
	# 「我手上有什么」。账本理论上各变更点都写过，但这里是落盘前最后一道闸 ——
	# 少写一次，玩家读档就少一张卡，而且不会有任何报错。
	# 没有视图（标题页 / 纯逻辑探针）时跳过，账本原样落盘。
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null and ca.has_method("flush_hand"):
		ca.flush_hand()

	var save_data: Dictionary = data_get()
	var json: String = JSON.stringify(save_data, "\t")

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入存档文件（错误码 %d）" % FileAccess.get_open_error()
		push_error("SaveLoader.save_game: " + last_error)
		save_completed.emit(false)
		return false
	file.store_string(json)
	file.close()
	last_error = ""
	save_completed.emit(true)
	return true


## 读档：读盘 → 校验 → **退役旧 UI** → 灌 Player → 切回存档场景。
## 返回 false 表示未读档（无档 / 坏档 / 版本不兼容），此时**不切场景、不改 Player**。
func load_game() -> bool:
	var save_data: Dictionary = read_save_file()
	if save_data.is_empty():
		push_warning("SaveLoader.load_game: %s" % last_error)
		load_completed.emit(false)
		return false

	# D-SV9 扩展（2026-10-24）：**旧 UI 必须先退役，再灌数据**。顺序反了就会出这两种事故：
	#   ① 活动触发器弹窗关闭时把槽里的卡「归还手牌」→ 改的是刚灌进来的新账本；
	#   ② 旧卡牌区视图在换场景那一下把自己的 `_cards` 写回账本 → 存档里的手牌被
	#      上一局的快照（常常是空的）整个盖掉，玩家点「继续游戏」看到的就是「卡全没了」。
	_discard_ui_views()

	apply_save_data(save_data)

	var entered_scene: String = Player.path if Player.path != "" else "res://scene/main.tscn"
	if not ResourceLoader.exists(entered_scene):
		push_warning("SaveLoader.load_game: 存档场景 %s 不存在，回落 main" % entered_scene)
		entered_scene = "res://scene/main.tscn"
		Player.path = entered_scene
	get_tree().change_scene_to_file(entered_scene)
	EventSignal.scene_entered.emit(entered_scene)
	# D-SV10：存档时若正处在一段剧情里（Player.plot 非空），等新场景就绪后续播到中断的那一句。
	_resume_plot_after_scene()
	load_completed.emit(true)
	return true



## D-SV10：读档后把被中断的剧情续上。
##
## 必须**等新场景 `_ready` 跑完**再动手：`change_scene_to_file` 是延迟换幕，调用后
## 当前帧里新场景尚未建立，此刻 add_plot 会挂到一个马上就要被销毁的旧场景上。
## 等两帧 —— 第 1 帧换幕、第 2 帧新场景就绪（本函数是协程，调用方 `load_game` 不阻塞）。
func _resume_plot_after_scene() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	PlotImporter.resume_plot_if_any()


## 是否存在**可用**存档（文件存在 + 能解析 + 版本兼容）。标题「继续」按钮用。
func has_save() -> bool:
	return not read_save_file().is_empty()


## 只读摘要，不改动 Player。供标题「继续」显示"第 N 天 · 名字"。
## 无档 / 坏档时返回 {}。
func peek_save_info() -> Dictionary:
	var save_data: Dictionary = read_save_file()
	if save_data.is_empty():
		return {}
	return {
		"save_version": int(save_data.get("save_version", LEGACY_VERSION)),
		"saved_at_unix": int(save_data.get("saved_at_unix", 0)),
		"saved_at_text": String(save_data.get("saved_at_text", "")),
		"player_name": String(save_data.get("player_name", "")),
		"time": int(save_data.get("time", 1)),
		"path": String(save_data.get("path", "")),
	}


## 新游戏：把 Player 全字段清回白名单默认值 + 换一枚新的 campaign_seed。
## 用于「返回标题后再开新档」——否则上一局的 tags/npc/天数会残留在 Autoload 里。
## 注意：本函数不删除磁盘存档（旧档会在建角色结尾 save_game 时被覆盖）。
func reset_to_new_game() -> void:
	apply_save_data({})
	Player.campaign_seed = ""
	Player.ensure_campaign_seed()


## 删除存档文件。返回是否真的删掉了。
func delete_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		# user:// 在部分平台不能 globalize，退回 DirAccess.open
		var dir := DirAccess.open("user://")
		if dir != null:
			err = dir.remove(SAVE_PATH.get_file())
	return err == OK


# ============================================================
#  读盘（D-SV5 健壮性 + D-SV4 版本校验）
# ============================================================

## 读文件 + 解析 + 版本校验。任何一步失败返回 {} 并写 last_error，**绝不崩**。
func read_save_file() -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(SAVE_PATH):
		last_error = "没有找到存档"
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		last_error = "存档无法打开（错误码 %d）" % FileAccess.get_open_error()
		return {}
	var text: String = file.get_as_text()
	file.close()

	# 用 JSON 实例而非 JSON.parse_string：坏档只拿错误码，不往控制台喷引擎级 ERROR
	var parser := JSON.new()
	if parser.parse(text) != OK:
		last_error = "存档已损坏（第 %d 行：%s）" % [parser.get_error_line(), parser.get_error_message()]
		return {}
	if not (parser.data is Dictionary):
		last_error = "存档已损坏（内容不是 JSON 对象）"
		return {}
	var save_data: Dictionary = parser.data

	var v: int = int(save_data.get("save_version", LEGACY_VERSION))
	if v > SAVE_VERSION:
		last_error = "存档来自更高版本（v%d > v%d），无法读取" % [v, SAVE_VERSION]
		return {}
	if v != LEGACY_VERSION and v < MIN_SUPPORTED_VERSION:
		last_error = "存档版本过旧（v%d < v%d），不兼容" % [v, MIN_SUPPORTED_VERSION]
		return {}
	# v == LEGACY_VERSION（老档无版本号）→ 允许，按 §4.5 前向填充默认值
	return save_data


# ============================================================
#  字段组装 / 灌入
# ============================================================

## 组装持久化字典（白名单 + 元信息）。
func data_get() -> Dictionary:
	var save_data: Dictionary = {}
	for key in PERSISTENT_FIELDS:
		var field: String = String(key)
		if field in Player:
			save_data[field] = Player.get(field)
		else:
			# Player 还没有该字段（例如尚未落地的新字段）→ 写默认值，保持档面完整
			save_data[field] = _default_of(field)
			push_warning("SaveLoader.data_get: Player 缺少白名单字段 %s，写入默认值" % field)

	# —— 元信息 ——
	save_data["save_version"] = SAVE_VERSION
	save_data["saved_at_unix"] = int(Time.get_unix_time_from_system())
	save_data["saved_at_text"] = Time.get_datetime_string_from_system(false, true)

	# 手牌补全（2026-10-24）：账本之外，把**已经拖进触发器卡槽、还没关窗**的玩家卡一起存。
	# 那些卡拖进槽时就已从账本摘掉（`remove_hand_card`），若不并进来，存档里的手牌就是缺的
	# —— 读档后弹窗不存在了，卡也就永远回不来。
	save_data["hand"] = _hand_for_save()
	return save_data



## 把存档字典灌进 Player（全字段 `.get` + 类型矫正）。别名保留旧函数名 load_data。
func apply_save_data(save_data: Dictionary) -> void:
	# 🔴 老档装备是**数组**（["多功能军刀"]）。三槽制改造后字段是字典，`_coerce` 会把数组
	#    判成类型不符、回落成 `{}` —— 装备会静默消失。所以先取出原值，灌完字段后再归槽补回。
	var legacy_equipment: Variant = save_data.get("player_equipment", null)
	for key in PERSISTENT_FIELDS:
		var field: String = String(key)
		var default_value: Variant = _default_of(field)
		var raw: Variant = save_data.get(field, default_value)
		Player.set(field, _coerce(raw, default_value))

	# 老档装备归槽。必须排在 hero_merge 之前 —— hero_merge 会把 player_equipment 镜像进
	# npc.Hero 条目，晚于它就白干（面板读的是条目）。
	if legacy_equipment is Array and not (legacy_equipment as Array).is_empty():
		Player.migrate_equipment_from_array(legacy_equipment)

	# 瞬态字段：读档时主动清零（GDD §4.2 / F7）
	Player.is_dialogue_exist = false
	Player.is_check_exist = false

	# 反 SL：老档没有种子时补一个，保证 campaign_seed 从此稳定（D-SV6）
	if Player.has_method("ensure_campaign_seed"):
		Player.ensure_campaign_seed()

	# 主角卡与实时属性对齐（读档后人物面板/卡牌读的是 npc.Hero）
	if Player.has_method("hero_merge"):
		Player.hero_merge()

	# D-HAND1 手牌账本：老档没有 hand 字段（读到空），按旧「按进度补卡」规则迁移一次。
	# 必须排在 hero_merge 之后 —— 迁移要用 npc.Hero 构造主角卡。
	if Player.has_method("migrate_hand_from_progress"):
		Player.migrate_hand_from_progress()

	# 事故补偿：账本被旧视图写坏的档（2026-10-24），每个档只补一次
	_repair_empty_hand_once()

	# D-TAGMIG（2026-10-23）：触发器显隐改成「只认 tags」之后的存档迁移，见函数注释。
	_migrate_item_tags_to_player_tags()

	# 读档改动的字段远多于带 setter 的那几个，统一补发一次，确保 HUD 完整刷新
	Player.notify_stats_changed()

	# 手牌账本换代（2026-10-24）：账本刚被整体替换，旧卡牌区视图手里那份从此作废。
	# 视图靠 `Player.hand_gen` 与自己的出生世代比对，离场时不再写回（见 card_area._exit_tree）。
	Player.hand_gen += 1


## 盘上的手牌 = 账本 + 「在触发器卡槽里待归还的玩家卡」的快照。
##
## 为什么要把槽里那些也并进来：`CardSlot.remove_card` 在卡被拖进槽的那一刻就把它从账本摘掉了
## （卡不算「在手上」）。这在游戏内是对的 —— 但它让「存档」变成了「只存账本」：玩家把卡放
## 进某个触发器（还没执行 / 已执行但还没关窗）时存档，读档后弹窗不存在，那些卡就**凭空蒸发**。
## 语义口径：读档 = 回到「卡还在手上」的状态（槽位状态本来就不持久化），不会让玩家多拿卡
## —— 消耗品已在 `_returnable_cards()` 里被排除，执行后关窗本来也会归还。
##
## 去重与 `Player.add_hand_card` 同口径：同 id 且不可堆叠只留一份。
func _hand_for_save() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for entry in Player.hand:
		out.append(entry)
		if entry is Dictionary:
			seen[String((entry as Dictionary).get("id", ""))] = true
	var extra: Array = TriggerManager.pending_hand_cards()
	for card in extra:
		if not (card is CardData):
			continue
		var c := card as CardData
		var cid := String(c.id)
		if cid == "":
			continue
		if seen.has(cid) and not c.is_stackable():
			continue
		seen[cid] = true
		out.append(c.to_data())
	return out



## D-TAGMIG（2026-10-23）：「显隐只认 tags」改造的存档迁移。
##
## 背景：`郊外小屋 / 纸条解疑 / 郊外挖宝 / 箱子与画` 这四个点位的 show_when 是本次才加的，
## 之前点位恒显、靠 display 层 `player_stuff` 分档。现在点位本身由与**物品同名**的 tag 门控。
## 老存档手里有钥匙 / 纸条 / 箱子，身上却没有这些 tag —— 不回填的话剧情链在新版本里
## 断在第一个点（玩家以为出了 bug），而这正是本次改造要消灭的那类静默断链。
##
## 幂等：只在「有物品、没同名 tag」时补一趟；不删 tag、不动物品。
## ⚠️ 名字必须与 trigger.json 的 `show_when.tags` 逐字一致，改一处忘了另一处就是静默断链。
const ITEM_TAG_BACKFILL := [
	"法拉叶藏身处的钥匙",
	"神秘纸条",
	"舞春神的钥匙",
	"奇怪的箱子",
	"《舞春神》",
]


func _migrate_item_tags_to_player_tags() -> void:
	for item_name in ITEM_TAG_BACKFILL:
		if not Player.player_stuff.has(item_name):
			continue
		if Player.player_tags.has(item_name):
			continue
		Player.grant_tag(item_name)
		print("[SaveLoader] D-TAGMIG：老存档有「%s」但没同名 tag，补上" % item_name)


## 兼容旧调用名（历史代码/文档里写的是 load_data）。
func load_data(save_data: Dictionary) -> void:
	apply_save_data(save_data)


## 一次性事故补偿（2026-10-24）：账本被「旧视图覆盖」写坏的存档。
##
## 事故链：读档换场景那一下，旧 `CardArea._exit_tree` 把自己的空 `_cards` 写回账本
## （现已由 `_discard_ui_views` + `Player.hand_gen` 堵住），紧接着某次自动存档（过天 /
## 剧情结算）把这个空账本落了盘。而 `hand_migrated` 早就是 true，`migrate_hand_from_progress`
## 再也不会补 —— 玩家点「继续游戏」看到的就是「所有卡片消失」，且没有任何报错。
##
## 口径：**每个档只补一次**（标记落 `tutorial_progress`，该字段已在白名单，不需新增持久字段）；
## 只认「迁移过却仍然空」的档，补的也只有老规则那几张（主角 / 管家 / 孩子）。
const HAND_REPAIR_KEY := "_hand_repair_20261024"


func _repair_empty_hand_once() -> void:
	if int(Player.tutorial_progress.get(HAND_REPAIR_KEY, 0)) == 1:
		return
	# 全新档（还没迁移过）走正常迁移，不在这里插手；手上有卡就不用补。
	if not Player.hand_migrated or not Player.hand.is_empty():
		return
	Player.migrate_hand_from_progress(true)
	# 补不到任何卡（身上没有那几条老 tag）→ **不打标记**：这不属于事故档，
	# 别让新开局的档白白吃下一次检查的钉子（每次读档只多一次空转）。
	if Player.hand.is_empty():
		return
	Player.tutorial_progress[HAND_REPAIR_KEY] = 1
	print("[SaveLoader] 手牌事故补偿：账本为空但已迁移过 → 按老规则补回 %d 张 %s" % [
		Player.hand.size(), str(Player.hand_ids())])



# ============================================================
#  内部辅助
# ============================================================

## 取白名单字段的默认值；容器类型返回**深拷贝**，避免多处共享同一引用。
func _default_of(field: String) -> Variant:
	var d: Variant = PERSISTENT_FIELDS.get(field, null)
	if d is Dictionary:
		return (d as Dictionary).duplicate(true)
	if d is Array:
		return (d as Array).duplicate(true)
	return d


## 按默认值的类型矫正读出来的值（JSON 数字全是 float；容器要深拷贝）。
## 类型不匹配（例如老档把数组写成了字符串）→ 回落默认值，不崩。
func _coerce(value: Variant, default_value: Variant) -> Variant:
	match typeof(default_value):
		TYPE_INT:
			if value is int or value is float or value is bool:
				return int(value)
			if value is String and (value as String).is_valid_int():
				return int(value as String)
			return int(default_value)
		TYPE_FLOAT:
			if value is int or value is float or value is bool:
				return float(value)
			if value is String and (value as String).is_valid_float():
				return float(value as String)
			return float(default_value)
		TYPE_STRING:
			if value is String:
				return value
			if value == null:
				return String(default_value)
			return str(value)
		TYPE_BOOL:
			if value is bool or value is int or value is float:
				return bool(value)
			return bool(default_value)
		TYPE_ARRAY:
			if value is Array:
				return (value as Array).duplicate(true)
			return default_value
		TYPE_DICTIONARY:
			if value is Dictionary:
				return (value as Dictionary).duplicate(true)
			return default_value
	return value if value != null else default_value


## 幂等清空覆盖层栈（D-SV9）。OverlayRoot 不可用（单测/早期启动）时跳过。
func _clear_overlays() -> void:
	var overlay: Node = get_node_or_null("/root/OverlayRoot")
	if overlay != null and overlay.has_method("clear_all"):
		overlay.clear_all()


## 读档前让**本场景那一套 UI** 退休（2026-10-24「点继续游戏手牌全没」的正面修复）。
##
## 两步，顺序不能反：
##   ① 卡牌区视图 `mark_stale()` + 注销 —— 它手里的 `_cards` 是**上一局**的快照。
##      读档后换场景那一下，它的 `_exit_tree` 会无脑 `Player.set_hand_from(_cards)`，
##      把刚灌进来的存档账本整个盖掉（旧视图空 → 「所有卡片消失」；旧视图有卡 → 手牌回退）。
##   ② 清覆盖层 —— 活动触发器弹窗关闭时会把槽里的卡「归还手牌」，必须发生在灌数据**之前**，
##      否则它改的就是刚灌进来的新账本。
func _discard_ui_views() -> void:
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null:
		if ca.has_method("mark_stale"):
			ca.mark_stale()
		TriggerManager.register_card_area(null)
	_clear_overlays()

