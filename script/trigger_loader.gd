## 触发器加载器（Autoload）— 加载 trigger.json，缓存；提供取、默认值合成、校验、display 选择。
## 纯数据/查询服务（无状态变更）， autoload 合理。
extends Node

const TRIGGER_PATH := "res://resoures/triggers/trigger.json"
const DEFAULT_FAIL_STATE := "失败"
const DEFAULT_PERFORMER := "执行者"
const DEFAULT_CHECK_TYPE := "compare"
## D-DOC24 初始化作用域默认值：static = 内容不随回合变化（游戏开始时初始化一次）。
const DEFAULT_INIT_SCOPE := "static"
## D-DOC24 初始化作用域：回合级（内容每回合变化 → 每个回合边界重建实例）。
const INIT_SCOPE_TURN := "turn"

var _triggers: Dictionary = {}  # id -> raw trigger dict


func _ready() -> void:
	_load_all()
	print("[TriggerLoader] 已加载 %d 个触发器" % _triggers.size())


func _load_all() -> void:
	var data := _load_json(TRIGGER_PATH)
	if data.is_empty():
		return
	# trigger.json 顶层若是单个触发器（带 "id"），按其 id 注册
	if data.has("id"):
		_triggers[String(data["id"])] = data
	else:
		# 否则视为 {id: trigger} 字典；忽略 "_" 开头键（引擎约定）
		for k in data:
			if String(k).begins_with("_"):
				continue
			_triggers[String(k)] = data[k]


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[TriggerLoader] 无法打开 %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[TriggerLoader] %s 解析失败" % path)
		return {}
	return parsed


## 按 id 取原始触发器（空字典=未找到）。
func get_trigger(trigger_id: String) -> Dictionary:
	return _triggers.get(trigger_id, {})


## 该触发器是否可重复（使用后触发器点仍可再次触发）。省略→false。
func is_repeatable(trigger_id: String) -> bool:
	var raw: Dictionary = get_trigger(trigger_id)
	return bool(raw.get("repeatable", false))


## 该触发器是否「独占」（E-独占，2026-08-23）。省略→true。
## true：同一触发器不可同时弹出多个弹窗（防连点）+ 该触发器执行未结束（进行中行动）时不可再开。
## false：放开上述限制（允许同 id 重复打开 / 进行中重开）。
func is_exclusive(trigger_id: String) -> bool:
	var raw: Dictionary = get_trigger(trigger_id)
	return bool(raw.get("exclusive", true))


## 初始化作用域（D-DOC24）："static"（默认，游戏开始初始化一次）/ "turn"（回合级，每回合重建实例）。
func init_scope_of(trigger_id: String) -> String:
	var raw: Dictionary = get_trigger(trigger_id)
	return String(raw.get("init_scope", DEFAULT_INIT_SCOPE))


## 是否回合级触发器（内容每回合变化 → 回合边界重建实例，弹窗只读实例）。
func is_turn_scoped(trigger_id: String) -> bool:
	return init_scope_of(trigger_id) == INIT_SCOPE_TURN


## 全部触发器 id（按 JSON 声明顺序）。
func all_trigger_ids() -> Array:
	return _triggers.keys()


## 指定初始化作用域的触发器 id 列表（D-DOC24：TriggerManager.init_turn 用它筛回合级）。
func list_by_init_scope(scope: String) -> Array:
	var out: Array = []
	for tid in _triggers.keys():
		if init_scope_of(String(tid)) == scope:
			out.append(String(tid))
	return out


# ============================================================
#  默认值合成（深拷贝，不改原数据）
# ============================================================

func expand(raw: Dictionary) -> Dictionary:
	var t: Dictionary = raw.duplicate(true)
	# ④ repeatable 省略→默认 false（一次性；true=可重复触发）
	if not t.has("repeatable"):
		t["repeatable"] = false
	# ⑤ exclusive 省略→默认 true（独占：同 id 不可同时多开 + 执行未结束不可重开）
	if not t.has("exclusive"):
		t["exclusive"] = true
	# ⑥ init_scope 省略→默认 static（D-DOC24：游戏开始初始化一次；写 "turn" = 回合级每回合重建实例）
	if not t.has("init_scope"):
		t["init_scope"] = DEFAULT_INIT_SCOPE
	var fail_state: String = t.get("fail_state", DEFAULT_FAIL_STATE)
	var turns: Dictionary = t.get("turns", {})
	for turn_id in turns:
		var turn: Dictionary = turns[turn_id]
		var phases: Array = turn.get("phases", [])
		for ph in phases:
			var phase: Dictionary = ph
			var phase_name: String = String(phase.get("phase", ""))
			var displays: Dictionary = phase.get("displays", {})
			for dname in displays:
				var d: Dictionary = displays[dname]
				# ① 卡牌情况 默认 [[]]*N
				var slots: Dictionary = d.get("slots", {})
				if not d.has("卡牌情况"):
					d["卡牌情况"] = _synth_ka(slots.size())
				# ②③ check.type / performer / suc effect
				var check_v: Variant = d.get("check", null)
				if check_v is Dictionary:
					var check: Dictionary = check_v
					if not check.has("type"):
						check["type"] = DEFAULT_CHECK_TYPE
					if not check.has("performer"):
						check["performer"] = DEFAULT_PERFORMER
					_synth_suc_effects(check, fail_state, phase_name)
	return t


func _synth_ka(n: int) -> Array:
	var out: Array = []
	for _i in n:
		out.append([])
	return out


func _synth_suc_effects(check: Dictionary, fail_state: String, phase_name: String) -> void:
	var branches: Dictionary = check.get("branches", {})
	for bkey in branches:
		var b: Dictionary = branches[bkey]
		if b.has("effect"):
			continue
		var idx := _suc_index(String(bkey))
		if idx == 0:
			b["effect"] = {"tags": [fail_state]}
		elif idx > 0:
			b["effect"] = {"tags": [phase_name]}


func _suc_index(bkey: String) -> int:
	if bkey.begins_with("suc"):
		return int(bkey.substr(3))
	return -1


# ============================================================
#  display 选择（卡牌情况子集匹配 + requires + 特异性）
# ============================================================

## 在 phase 的 displays 中选最具体匹配。placed: {slot_name: CardData}。world_tags: 世界状态 tag（require 用）。
## M1（2026-08-23）：display 新增可选 `conditions`：
##   {"attrs": {"str": {"min":3}, "app": {"min":6,"max":8}}, "num_tags": {"酒馆后厨工作经验": {"min":3,"max":3}}}
##   attrs 按 performer 槽卡的属性判定（无卡 → 不匹配）；num_tags 按 Player.player_num_tags 判定。
##   特异性计分：卡牌情况条款 ×10（拒绝类优先），conditions 条款各 ×1（互斥区间下并列歧义由互斥消除）。
func select_display(phase: Dictionary, placed: Dictionary, world_tags: Array) -> Dictionary:
	var displays: Dictionary = phase.get("displays", {})
	if displays.is_empty():
		return {}
	var best: Dictionary = {}
	var best_score := -1
	for dname in displays:
		var d: Dictionary = displays[dname]
		if not _requires_ok(d, world_tags):
			continue
		if not _cards_ok(d, placed):
			continue
		if not _conditions_ok(d, placed):
			continue
		var score := _specificity(d)
		if score > best_score:
			best_score = score
			best = d
	return best


## M1：display 条件判定（attrs/num_tags/tags/unless_tags 区间）。performer 名取 display.check.performer，缺省「执行者」。
## D-DOC2（2026-08-24）：conditions.sum=true 时，attrs 区间按「全部已放角色卡的属性求和」判定，
##   而非仅看 performer 单卡。用于「总 int > 14」「总 bod > 14」等队伍属性门控。
## D-DOC21（2026-09-09）：conditions 新增 tag 系条件——
##   tags:[...]：玩家已持有**全部**所列 tag 才匹配（story 门控 display 层）；
##   unless_tags:[...]：玩家持有**任一**所列 tag 即不匹配（「无约定/信赖才走 app」互斥）。
##   tags/unless_tags 各计 1 specificity（见 _specificity），保证带条件层压过无条件兜底层。
## D-DOC22（2026-09-09）：无卡槽「亲历」display（如剧院看剧，无执行者槽）——
##   tags_any:[...]：玩家持有**任一**所列 tag 即匹配（doc「Tags：乐感 || 学习」或分支）；
##   player_attrs:{attr:{min/max}}：按玩家自身生效属性（Player.effective_self_attrs，含 bonus）判区间，
##   与「有 performer 卡时 attrs + effective:true」同口径（总数值=属性+bonus）。两者各计 specificity。
## 2026-09-25（学校学习）：跨槽结构键 ——
##   any_slot:{names|tags|lack_tags, slots}：已放卡中「存在一张」满足（逐槽 卡牌情况 表达不了）；
##   placed_count:{slots, tag, min, max}：限定范围内已放卡数量闭区间。权重见 _specificity。
func _conditions_ok(d: Dictionary, placed: Dictionary) -> bool:
	var conds_v: Variant = d.get("conditions", null)
	if not (conds_v is Dictionary):
		return true
	var conds: Dictionary = conds_v
	var performer_name := "执行者"
	var check_v: Variant = d.get("check", null)
	if check_v is Dictionary:
		performer_name = String((check_v as Dictionary).get("performer", "执行者"))
	var performer: CardData = placed.get(performer_name, null)
	var use_sum := bool(conds.get("sum", false))
	# D-DOC14（2026-08-26）：effective=true → attrs 按「生效值」（裸值 + tag/装备 bonus）判定；
	# 省略 → 沿用裸值（历史行为，酒馆打工/群死调查等保持原口径）。打听 App 门槛用生效值。
	var use_eff := bool(conds.get("effective", false))

	# D-DOC21：tag 系条件（查 Player.player_tags —— 剧情/状态 tag 均为长期已提交 tag）。
	var req_tags_v: Variant = conds.get("tags", null)
	if req_tags_v is Array and not (req_tags_v as Array).is_empty():
		if not Player.player_has_tags(req_tags_v, 1):
			return false
	var unless_v: Variant = conds.get("unless_tags", null)
	if unless_v is Array and not (unless_v as Array).is_empty():
		if Player.player_has_tags(unless_v, 2):
			return false
	# D-DOC22（2026-09-09）：tags_any —— 玩家持有**任一**所列 tag 即匹配（区别于 tags 的「全持有」）。
	# 用于无卡槽 doc 简写「Tags：乐感 || 学习」这类或分支。
	var tags_any_v: Variant = conds.get("tags_any", null)
	if tags_any_v is Array and not (tags_any_v as Array).is_empty():
		if not Player.player_has_tags(tags_any_v, 2):
			return false
	# D-DOC21：requires_placed=true → 无 performer 卡即不匹配（tag 门控层也须放卡后才现身，
	# 保证打开先见兜底文案、{executor_name} 占位符有解析落点）。
	if bool(conds.get("requires_placed", false)) and performer == null:
		return false

	# D-DOC23（2026-09-10 神秘杂货店）：player_stuff —— 玩家持有**全部**所列物品（Player.player_stuff
	# 含物品名）才匹配。用于「持有越狱工具清单→店主换一副嘴脸」这类按物品持有分流的初始文案。
	var stuff_v: Variant = conds.get("player_stuff", null)
	if stuff_v is Array and not (stuff_v as Array).is_empty():
		for it in stuff_v:
			if not Player.player_stuff.has(String(it)):
				return false

	# attrs 区间：{"str": {"min":3}, "app": {"min":6,"max":8}}
	# sum=true → 求所有已放角色卡的该属性之和；否则取 performer 单卡。
	# effective=true → 各卡取 Player.effective_attrs_of（生效值），sum 同样逐卡取生效值求和。
	var attrs_v: Variant = conds.get("attrs", null)
	if attrs_v is Dictionary:
		if not use_sum and performer == null:
			return false
		for an in attrs_v:
			var spec = attrs_v[an]
			if not (spec is Dictionary):
				continue
			var lo := -2147483648
			var hi := 2147483647
			if spec.has("min"):
				lo = int(spec["min"])
			if spec.has("max"):
				hi = int(spec["max"])
			var val := 0
			if use_sum:
				for sn in placed:
					var c: CardData = placed[sn]
					if c != null and c.card_type == "character":
						if use_eff:
							val += int(Player.effective_attrs_of(c).get(String(an), 0))
						else:
							val += int(c.attrs.get(String(an), 0))
			else:
				if use_eff:
					val = int(Player.effective_attrs_of(performer).get(String(an), 0))
				else:
					val = int(performer.attrs.get(String(an), 0))
			if val < lo or val > hi:
				return false

	# D-DOC22（2026-09-09）：player_attrs —— 无卡槽「亲历」场景的 display 属性判定。
	# 语义：按**玩家自身**（Player 生效属性 effective_self_attrs，含 tag/装备 bonus）查区间，
	# 与有 performer 卡的 attrs（effective:true + sum 单槽）同口径；无槽位也可用。
	# 用法：conditions.player_attrs = {"app": {"min": 5}}（doc「App>=5」亲历判定）。
	var pattrs_v: Variant = conds.get("player_attrs", null)
	if pattrs_v is Dictionary:
		var self_attrs := Player.effective_self_attrs()
		for an in pattrs_v:
			var spec = pattrs_v[an]
			if not (spec is Dictionary):
				continue
			var lo := -2147483648
			var hi := 2147483647
			if spec.has("min"):
				lo = int(spec["min"])
			if spec.has("max"):
				hi = int(spec["max"])
			var val := int(self_attrs.get(String(an), 0))
			if val < lo or val > hi:
				return false

	# num_tags 区间：按 Player.player_num_tags
	var ntags_v: Variant = conds.get("num_tags", null)
	if ntags_v is Dictionary:
		for tn in ntags_v:
			var spec = ntags_v[tn]
			if not (spec is Dictionary):
				continue
			var lo := -2147483648
			var hi := 2147483647
			if spec.has("min"):
				lo = int(spec["min"])
			if spec.has("max"):
				hi = int(spec["max"])
			var val := int(Player.player_num_tags.get(String(tn), 0))
			if val < lo or val > hi:
				return false
	# performer_num_tags 区间（与同伴交流 GDD）：按执行者（performer）槽卡的 num_tags 判定。
	# 主角卡（id=="Hero"）→ player_num_tags；NPC → 其 npc 条目 num_tags（口径与 trigger_popup 一致）。
	# performer 槽未放卡 → 不匹配（门控不通过，落 fallback display）。
	var pntags_v: Variant = conds.get("performer_num_tags", null)
	if pntags_v is Dictionary:
		if performer == null:
			return false
		for tn in pntags_v:
			var spec = pntags_v[tn]
			if not (spec is Dictionary):
				continue
			var lo := -2147483648
			var hi := 2147483647
			if spec.has("min"):
				lo = int(spec["min"])
			if spec.has("max"):
				hi = int(spec["max"])
			var val := _performer_num_tag(performer, String(tn))
			if val < lo or val > hi:
				return false
	# M3（2026-08-27）：nobility 区间 —— 按 Player.nobility（1~5 贵族等级）。
	# 支持 {">":2} / {">=":3} / {"<":4} / {"<=":4} / {"=":3}。
	var nob_v: Variant = conds.get("nobility", null)
	if nob_v is Dictionary:
		var nv: int = int(Player.nobility)
		if nob_v.has(">") and not (nv > int(nob_v[">"])):
			return false
		if nob_v.has(">=") and not (nv >= int(nob_v[">="])):
			return false
		if nob_v.has("<") and not (nv < int(nob_v["<"])):
			return false
		if nob_v.has("<=") and not (nv <= int(nob_v["<="])):
			return false
		if nob_v.has("=") and not (nv == int(nob_v["="])):
			return false
	# 2026-09-25（学校学习）：**跨槽结构条件** —— 现有 `卡牌情况` 是**逐槽**约束，
	# 表达不了「不管孩子放进哪一个槽」/「放了两个及以上」这类判定，故补两个键：
	#   any_slot：存在一张已放卡满足任一分支
	#     names:[...]     卡的 id 或 display_name 命中其一
	#     tags:[...]      卡带所列任一 tag
	#     lack_tags:[...] 卡不带所列任一 tag（兜底否定；只遍历**已放卡**，空槽不算）
	#     slots:[...]     可选，限定槽位范围（省略 = 全部槽）
	#   placed_count：{slots:[...], tag:"child", min:2, max:3}
	#     限定范围内（可选再按 tag 过滤）的已放卡数量落在闭区间内。
	# 用途：学校学习的 6 条具名拒绝 + 「其他非 child 的人」+「两个及以上孩子」守卫。
	var any_slot_v: Variant = conds.get("any_slot", null)
	if any_slot_v is Dictionary:
		if not _any_slot_ok(any_slot_v as Dictionary, placed):
			return false
	var pcount_v: Variant = conds.get("placed_count", null)
	if pcount_v is Dictionary:
		if not _placed_count_ok(pcount_v as Dictionary, placed):
			return false
	# 2026-10-25（治疗）：performer —— 「执行者这一张卡」的身份条件。与 any_slot 的分工：
	#   any_slot = 已放卡中**存在一张**满足（逐条 OR）；performer = **只认 performer 这一张**，
	#   且 names / tags / lack_tags 之间是 **AND** —— 因此能表达 any_slot 表达不了的
	#   「是 child **且**没有 gifted」（治疗台的三种孩子台词）。
	#   写法：conditions.performer = {"names":["Allwin","阿尔温"], "tags":["child"], "lack_tags":["gifted"]}
	#     names      card.id 或 display_name 命中其一即可（等同「点名」）
	#     tags       全部命中
	#     lack_tags  全部不命中
	# 真值来源 = **Player 实时数据**（Hero→player_tags；NPC→Player.npc 条目 tags），
	# 不用 card.tags：卡实例是进手牌那一刻的快照，同一张卡在别的弹窗里加过 tag 就过期了。
	var perf_v: Variant = conds.get("performer", null)
	if perf_v is Dictionary:
		if not _performer_ok(perf_v as Dictionary, performer):
			return false
	# 2026-09-26（孤儿院）：random —— 反 SL 确定性随机门控。
	# 写法：conditions.random = {"key": "orphan_pick", "p": 0.5}
	# 语义：以 Player.make_rng("cond:random:<key>") 掷一次，randf() >= p → 不匹配。
	# 为何用 make_rng：种子含 campaign_seed + 当天 Player.time → **同局同天结果恒定**
	# （读档重来不变、弹窗反复 _refresh 也不抖动），过天后可重抽 —— 与鉴定/吸附同口径。
	# 用法：给「优先档」display 挂 random，另一条同条件、更低 specificity 的 display 作兜底；
	# 命中走随机档，未命中自然落兜底档。select_display 每次 _refresh 重算也不会翻脸。
	var rnd_v: Variant = conds.get("random", null)
	if rnd_v is Dictionary:
		var rspec: Dictionary = rnd_v
		var rkey := String(rspec.get("key", "default"))
		var p := float(rspec.get("p", 0.5))
		if Player.make_rng("cond:random:" + rkey).randf() >= p:
			return false
	return true


## conditions.any_slot：遍历已放卡（可选按 slots 过滤），命中任一分支即匹配。
## 空声明（三个分支都空）→ 视为「至少放了一张卡」，恒真（便于只做槽位范围判定）。
func _any_slot_ok(spec: Dictionary, placed: Dictionary) -> bool:
	var slot_filter: Array = spec.get("slots", [])
	var names: Array = spec.get("names", [])
	var tags: Array = spec.get("tags", [])
	var lack: Array = spec.get("lack_tags", [])
	for sn in placed:
		if not slot_filter.is_empty() and not _has_tag(slot_filter, String(sn)):
			continue
		var card: CardData = placed[sn]
		if card == null:
			continue
		if not names.is_empty():
			for n in names:
				if card.id == String(n) or card.display_name == String(n):
					return true
		if not tags.is_empty():
			for t in tags:
				if _has_tag(card.tags, String(t)):
					return true
		if not lack.is_empty():
			var hit := false
			for t in lack:
				if _has_tag(card.tags, String(t)):
					hit = true
					break
			if not hit:
				return true
	return false


## conditions.placed_count：限定槽位范围（可选按 tag 过滤）内的已放卡数量闭区间判定。
func _placed_count_ok(spec: Dictionary, placed: Dictionary) -> bool:
	var slot_filter: Array = spec.get("slots", [])
	var need_tag := String(spec.get("tag", ""))
	var lo := -2147483648
	var hi := 2147483647
	if spec.has("min"):
		lo = int(spec["min"])
	if spec.has("max"):
		hi = int(spec["max"])
	var n := 0
	for sn in placed:
		if not slot_filter.is_empty() and not _has_tag(slot_filter, String(sn)):
			continue
		var card: CardData = placed[sn]
		if card == null:
			continue
		if need_tag != "" and not _has_tag(card.tags, need_tag):
			continue
		n += 1
	return n >= lo and n <= hi


## 执行者（performer）槽卡某 num_tag 的值（与同伴交流 GDD）。
## 主角卡（id=="Hero"）→ player_num_tags；NPC → 其 npc 条目 num_tags（含中文名反查）。
func _performer_num_tag(performer: CardData, tag: String) -> int:
	if performer == null:
		return 0
	if performer.id == "Hero":
		return int(Player.player_num_tags.get(tag, 0))
	var npc_key := EffectProcessor._npc_key_of(performer)
	var entry: Dictionary = Player.npc.get(npc_key, {})
	return int(entry.get("num_tags", {}).get(tag, 0))


## conditions.performer 判定（2026-10-25 治疗）：执行者这一张卡的身份条件。
## names = OR（命中其一），tags = AND（全部持有），lack_tags = AND（全部未持有）。
## 未放执行者卡 → 不匹配（有要求时不能让兜底档冒充具名档）。
func _performer_ok(spec: Dictionary, performer: CardData) -> bool:
	if performer == null:
		return false
	var names: Variant = spec.get("names", null)
	if names is Array and not (names as Array).is_empty():
		var name_hit := false
		for n in (names as Array):
			if performer.id == String(n) or performer.display_name == String(n):
				name_hit = true
				break
		if not name_hit:
			return false
	var have: Array = _performer_tags(performer)
	var req: Variant = spec.get("tags", null)
	if req is Array:
		for t in (req as Array):
			if not _has_tag(have, String(t)):
				return false
	var lack: Variant = spec.get("lack_tags", null)
	if lack is Array:
		for t in (lack as Array):
			if _has_tag(have, String(t)):
				return false
	return true


## 执行者的实时 tag 列表：主角（Hero）→ player_tags **+ 身份词条**；其余 → Player.npc 条目 tags。
## ⚠️ 主角必须补 Player.HERO_IDENTITY_TAGS（player/主角/hero）：那是 get_hero_card() 现场铺上卡的，
## 不进 player_tags。只取 player_tags 会让 conditions.performer.tags=["player"] 永远不命中。
## ⚠️ NPC 条目还没建（剧情里的角色首次进槽）→ 退回 characters.json 预设的 tags，再退卡实例。
##    只读 Player.npc 会让「手上有卡、档里没条目」的人条件恒假（孩子还没回家时就是这样）。
func _performer_tags(performer: CardData) -> Array:
	if performer == null:
		return []
	var key := EffectProcessor._npc_key_of(performer)
	if key == "Hero":
		var out: Array = Player.player_tags.duplicate()
		for t in Player.HERO_IDENTITY_TAGS:
			if not (t in out):
				out.append(String(t))
		return out
	var ev: Variant = Player.npc.get(key, null)
	if ev is Dictionary:
		var tv: Variant = (ev as Dictionary).get("tags", [])
		if tv is Array and not (tv as Array).is_empty():
			return tv
	var preset: Dictionary = EffectProcessor.preset_npc_quiet(key)
	var ptv: Variant = preset.get("tags", [])
	if ptv is Array and not (ptv as Array).is_empty():
		return ptv
	return performer.tags


func _requires_ok(d: Dictionary, world_tags: Array) -> bool:
	var req: Variant = d.get("requires", null)
	if req == null or not (req is Array):
		return true
	for t in req:
		if not _has_tag(world_tags, String(t)):
			return false
	return true


func _cards_ok(d: Dictionary, placed: Dictionary) -> bool:
	var slots: Dictionary = d.get("slots", {})
	var ka: Array = d.get("卡牌情况", [])
	var slot_names: Array = slots.keys()
	for i in slot_names.size():
		var sn: String = slot_names[i]
		var acceptable: Array = ka[i] if i < ka.size() else []
		var card: CardData = placed.get(sn, null)
		var inserted: Array = card.tags if card != null else []
		if not _slot_accepts(acceptable, inserted):
			return false
	return true


## 逐槽「卡牌情况」判定：acceptable = 该槽的**组列表**，每组是一串 tag（组内 AND、组间 OR），
## 空组 = 该槽无约束。层级是 `[[["tag"]]]`：外层 per-slot → 中层 per-group → 内层 tags。
##
## ⚠️ 2026-10-16：原先对**非数组**元素静默当空组（`g = []` → 恒真）。若数据少写一层
##    （写成 `[["主角"],["child"]]` 而不是 `[[["主角"]],[["child"]]]`），约束会**静默失效**，
##    却照旧进 `_specificity` 计分 —— 带约束的 display 凭虚高分压过所有守卫层。归还孩子踩过这个坑
##    （`卡牌情况` 少一层 ⇒ 非孩子/非主角也能「送回去」）。现在非数组元素一律报 warning 喊出来，
##    行为仍按「空组 = 无约束」保持宽容（宁可吵，不要把触发器直接打死）。
func _slot_accepts(acceptable: Array, inserted_tags: Array) -> bool:
	if acceptable.is_empty():
		return true  # 无约束
	for group in acceptable:
		if not (group is Array):
			push_warning("TriggerLoader._slot_accepts: 卡牌情况的组必须是数组（组内放 tag），收到 '%s' —— 按空组（无约束）处理，请检查数据层级是否少写一层" % str(group))
			return true
		var g: Array = group
		var ok := true
		for t in g:
			if not _has_tag(inserted_tags, String(t)):
				ok = false
				break
		if ok:
			return true
	return false


func _specificity(d: Dictionary) -> int:
	var total := 0
	# 卡牌情况条款权重 ×10：拒绝类 display（带卡牌情况约束）优先于条件类 display
	var ka: Array = d.get("卡牌情况", [])
	for group in ka:
		var g: Array = group if group is Array else []
		total += g.size() * 10
	# M1：conditions 条款各计 1（attrs 每属性 +1、num_tags 每条 +1、performer_tags 每条 +1）
	var conds_v: Variant = d.get("conditions", null)
	if conds_v is Dictionary:
		var conds: Dictionary = conds_v
		var attrs_v: Variant = conds.get("attrs", null)
		if attrs_v is Dictionary:
			total += (attrs_v as Dictionary).size()
		var ntags_v: Variant = conds.get("num_tags", null)
		if ntags_v is Dictionary:
			total += (ntags_v as Dictionary).size()
		# performer_num_tags 条件各计 1（与 attrs/num_tags 同权），保证门控 display 优先于无约束 fallback
		var pntags_v: Variant = conds.get("performer_num_tags", null)
		if pntags_v is Dictionary:
			total += (pntags_v as Dictionary).size()
		# M3（2026-08-27）：nobility 条件计 1（与 attrs/num_tags 同权），保证门控 display 优先于无约束 fallback。
		if conds.has("nobility"):
			total += 1
		# D-DOC21：tags / unless_tags / requires_placed 各计 1，保证 tag 门控层压过无条件兜底层
		var req_tags_v: Variant = conds.get("tags", null)
		if req_tags_v is Array:
			total += (req_tags_v as Array).size()
		var unless_v: Variant = conds.get("unless_tags", null)
		if unless_v is Array:
			total += (unless_v as Array).size()
		if bool(conds.get("requires_placed", false)):
			total += 1
		# D-DOC22：tags_any / player_attrs 各计 1，保证「玩家自身分层」display 压过无条件兜底层
		var tags_any_v: Variant = conds.get("tags_any", null)
		if tags_any_v is Array:
			total += (tags_any_v as Array).size()
		var pattrs_v: Variant = conds.get("player_attrs", null)
		if pattrs_v is Dictionary:
			total += (pattrs_v as Dictionary).size()
		# D-DOC23：player_stuff 条目各计 1（与 tags 同权），保证「持有物品门控」display 压过无条件兜底层
		var stuff_v: Variant = conds.get("player_stuff", null)
		if stuff_v is Array:
			total += (stuff_v as Array).size()
		# 2026-09-25（学校学习）：跨槽结构条件的权重阶梯 ——
		#   any_slot.names（指名）/ any_slot.tags（具类）/ any_slot.lack_tags（兜底否定）= 20：
		#     三者都必须压过「收益层」（卡牌情况 1 条 =10 + conditions 1 条 =1 → 11）。
		#     lack_tags 早期定为 10，会漏掉「一个孩子槽放了孩子、另一个孩子槽放了非孩子」的组合
		#     （收益层 11 > 兜底拒绝 10 → 非孩子被静默忽略、照样结算）。故与具名同权，
		#     并由**声明顺序**决定同分归属：具名拒绝写在兜底拒绝之前 → 具名优先，兜底兜住其余。
		#   placed_count（数量守卫）= 30：最高优先，压过一切单槽约束。
		# 按**分支是否存在**计分（不按条目数），避免「多写一个别名就抬高优先级」的数据侧游戏。
		var any_slot_v: Variant = conds.get("any_slot", null)
		if any_slot_v is Dictionary:
			var aspec: Dictionary = any_slot_v
			var as_names: Variant = aspec.get("names", null)
			if as_names is Array and not (as_names as Array).is_empty():
				total += 20
			var as_tags: Variant = aspec.get("tags", null)
			if as_tags is Array and not (as_tags as Array).is_empty():
				total += 20
			var as_lack: Variant = aspec.get("lack_tags", null)
			if as_lack is Array and not (as_lack as Array).is_empty():
				total += 20
		if conds.get("placed_count", null) is Dictionary:
			total += 30
		# 2026-10-25（治疗）：performer 各分支（names/tags/lack_tags）与 any_slot 同权 20 ——
		# 都是「指人/指类」的具体档，必须压过无 conditions 的兜底档（0）与属性区间档（每属性 1）。
		# 同权下的先后由**声明顺序**决定（孩子两档写在主角/阿尔温之前，兜底写最后）。
		var perf_v: Variant = conds.get("performer", null)
		if perf_v is Dictionary:
			var pspec: Dictionary = perf_v
			for pk in ["names", "tags", "lack_tags"]:
				var pv: Variant = pspec.get(pk, null)
				if pv is Array and not (pv as Array).is_empty():
					total += 20
		# 2026-09-26（孤儿院）：random 计 1（与 tags/unless_tags 同权），保证「随机档」
		# 压过同条件、无 random 的兜底档；未命中时随机档被 _conditions_ok 否掉，兜底档接管。
		if conds.get("random", null) is Dictionary:
			total += 1
	return total


func _has_tag(tags: Array, t: String) -> bool:
	for x in tags:
		if String(x) == t:
			return true
	return false


# ============================================================
#  吸附（D-DOC24：初始化与弹窗装配共用同一入口）
#  - tag 形式（D-DOC13 越狱支援）：Player.npc 动态 tag ∪ CardRegistry 静态 tag；
#  - class 形式（D-DOC23 神秘杂货店商品）：CardRegistry 道具按 card_class 命中。
#  抽取走 Player.make_rng 确定性（同局同天同 seed_key → 同结果，反 SL）。
# ============================================================

## 解析槽位的 auto_attract 声明 → {tag, classes, exclude_sold}（无 / 空声明 → 空字典）。
## 字符串形式 = 按 tag 吸附（D-DOC13 越狱支援）；对象形式 = {class:[...], exclude_sold:true}
## （D-DOC23 神秘杂货店商品池）。供 TriggerManager 回合初始化与 TriggerPopup 装配共用（单一来源）。
func attract_spec(cfg: Dictionary) -> Dictionary:
	var v: Variant = cfg.get("auto_attract", null)
	if v is String and String(v) != "":
		return {"tag": String(v), "classes": [], "exclude_sold": false}
	if v is Dictionary:
		var aa: Dictionary = v
		var classes: Array = []
		var cv: Variant = aa.get("class", null)
		if cv is Array:
			classes = cv
		var tag := String(aa.get("tag", ""))
		if tag != "" or not classes.is_empty():
			return {
				"tag": tag,
				"classes": classes,
				"exclude_sold": bool(aa.get("exclude_sold", false)),
			}
	return {}


## 构建吸附候选池（已按 accept 类型 + classes 过滤，未排除 exclude）。
func build_attract_pool(tag: String, accept: String, classes: Array) -> Array:
	var pool: Array = []
	if tag != "":
		for key in Player.npc:
			var entry: Variant = Player.npc[key]
			if not (entry is Dictionary):
				continue
			if not (tag in (entry.get("tags", []) as Array)):
				continue
			var card: CardData = npc_entry_to_card(String(key), entry)
			if card != null and not pool.has(card):
				pool.append(card)
		for c in CardRegistry.list_by_tag([tag], 1):
			if not pool.has(c):
				pool.append(c)
	elif not classes.is_empty():
		for c in CardRegistry.list_by_type("item"):
			for cl in classes:
				if String(cl) in c.card_class:
					pool.append(c)
					break
	var filtered: Array = []
	for c in pool:
		if accept != "" and accept != "*" and c.card_type != accept:
			continue
		if not classes.is_empty():
			var class_ok := false
			for cl in classes:
				if String(cl) in c.card_class:
					class_ok = true
					break
			if not class_ok:
				continue
		filtered.append(c)
	return filtered


## 吸附一张卡（D-DOC24 确定性版）。
## exclude_ids：跨槽已吸附 id + 本回合已消耗 id（TriggerManager）——命中的卡不参与抽取。
## seed_key 建议 "attract:<触发id>:<槽名>"；同局 + 同天 + 同 seed_key → 同结果（读档重来不变）。
## 池空 → null（调用方据此留空位）。
func attract_card(tag: String, accept: String, classes: Array, exclude_ids: Array,
		seed_key: String, extra: String = "") -> CardData:
	var candidates: Array = []
	for c in build_attract_pool(tag, accept, classes):
		if c.id in exclude_ids:
			continue
		candidates.append(c)
	if candidates.is_empty():
		return null
	var rng: RandomNumberGenerator = Player.make_rng(seed_key, extra)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## 把 Player.npc 条目映射回一张**角色卡**（`build_attract_pool` 用）。
##
## 🔴 2026-10-16（方案 B 同批）：改按**条目实时造卡**（与 `EffectProcessor._npc_entry_card`
##    同口径），不再回落注册表静态卡。原实现先试 `CardRegistry.get_card(key)`，命中就**直接返回
##    共享静态实例** —— 那让「按 tag 从 `Player.npc` 建池」名不副实：挑人用的是条目里的 tag，
##    挑出来的人却带预设属性/tag（主角卡还会显示模板名）。更糟的是**不在注册表里的条目会被
##    整个丢掉**（如孩子卡：id 是 `adopted`、名字是玩家取的 —— 注册表与中文名都查不到 ⇒ 返回 null），
##    于是「带某 tag 的孩子」永远吸引不到。
## ⚠️ 条目字段（name/int/app/str/bod/tags/image/description）与 characters.json 同构，
##    `CardData.from_character` 直接吃；拿不到条目（空字典）才回落注册表。
func npc_entry_to_card(key: String, entry: Dictionary) -> CardData:
	if not entry.is_empty():
		return CardData.from_character(key, entry)
	return CardRegistry.get_card(key)


# ============================================================
#  回合路由 —— 从当前 turn 之后扫描，找首个 require 匹配的 turn/phase
# ============================================================

## 在当前 turn 之后扫描后续 turn，找首个 phase.require 被 world_tags 满足的。
## 返回 {turn_id, phase, turn}；若无匹配返回 {}。
## phase.require == null 的跳过（仅入口 phase 可为 null，不应出现在路由中）。
func find_next_turn(expanded: Dictionary, current_turn_id: String, world_tags: Array) -> Dictionary:
	var turns: Dictionary = expanded.get("turns", {})
	var turn_ids: Array = turns.keys()
	var found_current := false

	for tid in turn_ids:
		if not found_current:
			if tid == current_turn_id:
				found_current = true
			continue

		var turn: Dictionary = turns[tid]
		for ph in turn.get("phases", []):
			var phase: Dictionary = ph
			var req: Variant = phase.get("require", null)
			if req == null:
				continue
			if not (req is Array):
				continue
			if _tags_meet(req, world_tags):
				return {
					"turn_id": String(tid),
					"phase": phase,
					"turn": turn,
				}

	return {}


## 检查 tags 包含 require 全部 tag
func _tags_meet(require_tags: Array, world_tags: Array) -> bool:
	for t in require_tags:
		if not _has_tag(world_tags, String(t)):
			return false
	return true


# ============================================================
#  校验（返回错误字符串数组；空=通过）
# ============================================================

func validate(t: Dictionary) -> Array:
	var errors: Array = []
	var turns: Dictionary = t.get("turns", {})
	var is_protagonist_only: bool = bool(t.get("protagonist_only", false))
	# 全局入口：非 fail turn 中 require:null phase 恰一个（首 turn 入口；后续 turn 靠 require 进）
	var total_null_req := 0
	for turn_id in turns:
		var turn: Dictionary = turns[turn_id]
		var is_fail: bool = String(turn.get("role", "")) == "fail"
		var phases: Array = turn.get("phases", [])
		for ph in phases:
			var phase: Dictionary = ph
			if not is_fail and phase.get("require", "___") == null:
				total_null_req += 1
			var displays: Dictionary = phase.get("displays", {})
			for dname in displays:
				var d: Dictionary = displays[dname]
				var slots: Dictionary = d.get("slots", {})
				var ka: Array = d.get("卡牌情况", [])
				if ka.size() != slots.size():
					errors.append("%s/%s: 卡牌情况长度(%d)!=槽数(%d)" % [turn_id, dname, ka.size(), slots.size()])
				var check_v: Variant = d.get("check", null)
				if check_v is Dictionary:
					var c: Dictionary = check_v
					# D-DOC3（2026-08-24）：multi 模式用 multi_needs，按最大档数校验 branches。
					# D-DOC3（2026-08-25）：combine:"dual" 双骰双阈值固定 5 档。
					var mode: String = String(c.get("mode", ""))
					if mode == "multi" or mode == "multi_all" or mode == "multi_any":
						var branches: Dictionary = c.get("branches", {})
						if String(c.get("combine", "")) == "dual":
							if branches.size() != 5:
								errors.append("%s/%s: dual 模式 branches 数(%d)!=5" % [turn_id, dname, branches.size()])
						else:
							var max_tiers := 0
							var mn: Dictionary = c.get("multi_needs", {})
							for an in mn:
								var th: Array = mn[an] if mn[an] is Array else []
								max_tiers = max(max_tiers, th.size())
							if branches.size() != max_tiers + 1:
								errors.append("%s/%s: multi branches 数(%d)!=最大档数+1(%d)" % [turn_id, dname, branches.size(), max_tiers + 1])
					else:
						var needs: Array = c.get("needs", [])
						var branches: Dictionary = c.get("branches", {})
						if branches.size() != needs.size() + 1:
							errors.append("%s/%s: branches 数(%d)!=needs+1(%d)" % [turn_id, dname, branches.size(), needs.size() + 1])
					# D-C1：亲历鉴定（protagonist_only）必须入场必成功 → check 必须为 null
					if is_protagonist_only and c.get("type", "compare") != "null":
						errors.append("%s/%s: protagonist_only 触发器 check 必须为 null（入场必成功）" % [turn_id, dname])
	if total_null_req != 1:
		errors.append("非 fail turn 须恰一个 require:null phase 作全局入口（实际 %d）" % total_null_req)
	return errors
