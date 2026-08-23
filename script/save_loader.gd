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
	"plot": "",
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
	"gift_att": 60,              # D-SV2 天赋点
	# —— 主角·资源 / 身份 ——
	"player_money": 100,
	"player_name": "请输入你的名字",
	# —— 主角·集合 ——
	"player_equipment": [],
	"player_tags": [],
	"player_num_tags": {},
	"player_stuff": [],
	# —— 成就 ——
	"achievements_unlocked": {},
	# —— 孩子（已并入 npc，统一带 "child" 标签，随上方 "npc" 白名单自动持久化，不再单列）——
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


## 读档：读盘 → 校验 → 灌 Player → 清覆盖层 → 切回存档场景。
## 返回 false 表示未读档（无档 / 坏档 / 版本不兼容），此时**不切场景、不改 Player**。
func load_game() -> bool:
	var save_data: Dictionary = read_save_file()
	if save_data.is_empty():
		push_warning("SaveLoader.load_game: %s" % last_error)
		load_completed.emit(false)
		return false

	apply_save_data(save_data)

	# D-SV9：读档前防御性清空覆盖层（调用方可能已清，幂等安全）
	_clear_overlays()

	var entered_scene: String = Player.path if Player.path != "" else "res://scene/main.tscn"
	if not ResourceLoader.exists(entered_scene):
		push_warning("SaveLoader.load_game: 存档场景 %s 不存在，回落 main" % entered_scene)
		entered_scene = "res://scene/main.tscn"
		Player.path = entered_scene
	get_tree().change_scene_to_file(entered_scene)
	EventSignal.scene_entered.emit(entered_scene)
	load_completed.emit(true)
	return true


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
	return save_data


## 把存档字典灌进 Player（全字段 `.get` + 类型矫正）。别名保留旧函数名 load_data。
func apply_save_data(save_data: Dictionary) -> void:
	for key in PERSISTENT_FIELDS:
		var field: String = String(key)
		var default_value: Variant = _default_of(field)
		var raw: Variant = save_data.get(field, default_value)
		Player.set(field, _coerce(raw, default_value))

	# 瞬态字段：读档时主动清零（GDD §4.2 / F7）
	Player.is_dialogue_exist = false
	Player.is_check_exist = false

	# 反 SL：老档没有种子时补一个，保证 campaign_seed 从此稳定（D-SV6）
	if Player.has_method("ensure_campaign_seed"):
		Player.ensure_campaign_seed()

	# 主角卡与实时属性对齐（读档后人物面板/卡牌读的是 npc.Hero）
	if Player.has_method("hero_merge"):
		Player.hero_merge()

	# 读档改动的字段远多于带 setter 的那几个，统一补发一次，确保 HUD 完整刷新
	Player.notify_stats_changed()


## 兼容旧调用名（历史代码/文档里写的是 load_data）。
func load_data(save_data: Dictionary) -> void:
	apply_save_data(save_data)


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
