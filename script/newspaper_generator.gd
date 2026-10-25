class_name NewspaperGenerator
extends RefCounted

## 报纸日刊生成器（纯函数，无节点依赖）。
## 过天时调用 generate(day) 产出当天报纸字典，喂给 Newspaper 组件显示。
##
## 每天报纸 = 最多 4 条（3 新闻 + 1 随机效果），按优先级生成：
##   1. 时间事件：查 time_events.json[day]（固定表，可能多条，最多占满 3 新闻位）
##   2. 剧情内容：从 Player.pending_news 队首取（剧情 effect `news` 入队），
##      当天最多消费到 3 条，剩余留队列顺移下一天
##   3. 非剧情池补足：新闻不足 3 时从 flavor_pool.json.flavor_news_pool 随机补，
##      当天不重复（按 id），池空则不足即止
##   4. 随机效果：从 effect_pool 每天 roll 1 条，与上一天（Player.last_flavor）不重复
##
## D-NEWS1（2026-09-30）：时间事件条目可带**显示条件** `requires`——过天时按 Player 当前
## 标签决定哪几条进报纸，用于「同一件事、按剧情分支各写一版」的写法（如狱中暴毙的
## 未触发 / 法拉叶 / 衫斯 / 两人 四版）。字段语义见 _entry_meets_requires()。
## 不写 `requires` 的条目恒通过（严格向后兼容）。
##
## D-NEWS2（2026-10-16）：报纸条目可带**授予标签** `grant_tags: ["X"]`——该条入选当天报纸
## 时授予玩家（幂等）。用于「报纸上登了这件事 → 玩家知道 → 解锁下游触发器」的链路。
## 时间事件与剧情入队（pending_news）两条通路共用 _apply_grant_tags()；只有 generate()
## 授予，generate_fixed() 不授予。首例：day3「兰心歌剧院 恐难以为继」→「报纸剧院传闻」。
##
## 随机源走 Player.make_rng("newspaper")（反 SL：同一天结果恒定，读档不刷结果）。

const NEWSPAPER_TITLE := "白桦纪事报"
const TIME_EVENTS_PATH := "res://resoures/plot/newspaper/time_events.json"
const FLAVOR_POOL_PATH := "res://resoures/plot/newspaper/flavor_pool.json"
const MAX_NEWS := 3

static var _time_events_cache: Dictionary = {}
static var _flavor_pool_cache: Dictionary = {}
static var _loaded := false


## 生成第 day 天的报纸内容。返回 {title, date, columns:[...]}。
static func generate(day: int) -> Dictionary:
	_ensure_loaded()
	var columns: Array = []
	var rng := Player.make_rng("newspaper")

	# 1. 时间事件（固定表；逐条过 requires 条件筛选——这就是「按 tags 决定当天报纸」的入口）
	var events: Variant = _time_events_cache.get(str(day), [])
	if events is Array:
		for e in events:
			if columns.size() >= MAX_NEWS:
				break
			if e is Dictionary and _entry_meets_requires(e as Dictionary):
				columns.append((e as Dictionary).duplicate(true))
				_apply_grant_tags(e as Dictionary)

	# 2. 剧情内容（运行时队列，队首消费，多余顺移下天）
	while columns.size() < MAX_NEWS and Player.pending_news.size() > 0:
		var item: Variant = Player.pending_news.pop_front()
		if item is Dictionary:
			columns.append((item as Dictionary).duplicate(true))
			# D-NEWS2：剧情入队的新闻走同一条 `grant_tags` 通路——用于「过天登报即授标签」的
			# 链（首例：注资后次日登「剧院暂停营业」→ 授「剧院关闭」）。
			_apply_grant_tags(item as Dictionary)

	# 3. 非剧情池补足（当天不重复，按 id）
	var flavor_news: Variant = _flavor_pool_cache.get("flavor_news_pool", [])
	var chosen := {}
	for c in columns:
		if c is Dictionary and c.has("id"):
			chosen[str(c["id"])] = true
	var candidates: Array = []
	if flavor_news is Array:
		for item in flavor_news:
			if item is Dictionary and not chosen.has(str(item.get("id", ""))):
				candidates.append(item)
	while columns.size() < MAX_NEWS and candidates.size() > 0:
		var idx := rng.randi_range(0, candidates.size() - 1)
		columns.append((candidates[idx] as Dictionary).duplicate(true))
		candidates.remove_at(idx)

	# 4. 随机效果位（每天 roll 1，与上一天不重复）
	var effect_pool: Variant = _flavor_pool_cache.get("effect_pool", [])
	if effect_pool is Array and effect_pool.size() > 0:
		var idx := rng.randi_range(0, effect_pool.size() - 1)
		var pick: Variant = effect_pool[idx]
		if effect_pool.size() > 1 and str(pick.get("id", "")) == Player.last_flavor:
			pick = effect_pool[(idx + 1) % effect_pool.size()]
		var effect_col: Dictionary = (pick as Dictionary).duplicate(true)
		effect_col["kind"] = "effect"
		if str(effect_col.get("body", "")) == "":
			effect_col["body"] = "（效果待实现，敬请期待）"
		columns.append(effect_col)
		Player.last_flavor = str(effect_col.get("id", ""))

	return {
		"title": NEWSPAPER_TITLE,
		"date": "第 %d 天" % day,
		"columns": columns,
	}


## 固定日刊（新手教程报纸 GDD）：只读 time_events.json[day] 的新闻数组，原样进 columns，
## 不截断（最多 4 栏）、不补非剧情池、不 roll 随机效果。供报纸 effect 与回看按钮复用。
## 同样过 requires 筛选（否则「同一件事的多种情况」会一起挤进 4 栏）。
static func generate_fixed(day: int) -> Dictionary:
	_ensure_loaded()
	var columns: Array = []
	var events: Variant = _time_events_cache.get(str(day), [])
	if events is Array:
		for e in events:
			if e is Dictionary and _entry_meets_requires(e as Dictionary):
				columns.append((e as Dictionary).duplicate(true))
	return {
		"title": NEWSPAPER_TITLE,
		"date": "第 %d 天" % day,
		"columns": columns,
	}


## D-NEWS2（2026-10-16）：报纸条目可选 `grant_tags: ["X"]` —— 该条**入选当天报纸**时授予
## 玩家（幂等）。时间事件与剧情入队两条通路共用本函数，只在 generate() 调用链里生效；
## generate_fixed() 是回看/历史补发，不授予。
static func _apply_grant_tags(entry: Dictionary) -> void:
	var granted: Variant = entry.get("grant_tags", null)
	if not (granted is Array):
		return
	for gt in (granted as Array):
		var gts := String(gt)
		if gts != "":
			Player.grant_tag(gts)


## 判断一条时间事件是否满足显示条件（D-NEWS1）。`requires` 为**可选**字段：
##   { "tags":     ["A","B"] }  玩家须**全部**持有这些标签
##   { "any_tags": ["A","B"] }  玩家须持有**任一**
##   { "not_tags": ["C"]     }  玩家**一个都不能有**
## 三者可同时出现，须全部满足；缺省、或写成空数组 = 该维度不限制。
## **不写 `requires` → 恒通过**（向后兼容旧数据，不用改已存在的条目）。
##
## ⚠️ 写「同一件事的多种情况」时，条件必须**互斥**——多个条目同时通过会一起占新闻位
##    （每天上限 3，多出来的会被挤掉）。四个情况的正确写法（互斥）：
##     {not_tags:[A,B]} / {tags:[A], not_tags:[B]} / {tags:[B], not_tags:[A]} / {tags:[A,B]}
static func _entry_meets_requires(entry: Dictionary) -> bool:
	var req: Variant = entry.get("requires", null)
	if not (req is Dictionary):
		return true
	var r: Dictionary = req

	# 全部持有（method=1 → all）
	var need_all: Variant = r.get("tags", [])
	if need_all is Array and not (need_all as Array).is_empty():
		if not Player.player_has_tags(need_all as Array, 1):
			return false

	# 持有任一（method=0 → any）
	var need_any: Variant = r.get("any_tags", [])
	if need_any is Array and not (need_any as Array).is_empty():
		if not Player.player_has_tags(need_any as Array, 0):
			return false

	# 一个都不能有
	var forbid: Variant = r.get("not_tags", [])
	if forbid is Array:
		for t in (forbid as Array):
			if String(t) in Player.player_tags:
				return false

	return true


## 惰性加载时间事件表与随机池（静态缓存，避免每天重复读盘）。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_time_events_cache = _read_json_dict(TIME_EVENTS_PATH)
	_flavor_pool_cache = _read_json_dict(FLAVOR_POOL_PATH)
	_loaded = true


static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("NewspaperGenerator: 找不到 %s，将跳过该类新闻" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("NewspaperGenerator: 无法读取 %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	push_warning("NewspaperGenerator: %s 解析失败（非字典）" % path)
	return {}
