"""
剧情管理器 - 负责加载JSON对话数据并控制对话流程
使用方法：
调用 add_plot(file_path:String, plot_name:String) 加载特定剧情 
依赖：
DialogueGroup 和 Dialogue 资源类
dialogue_ui.tscn 场景文件
"""
extends Node

const UI = 'res://components/dialogue_ui.tscn'

## top_attr 并列时的取用顺序（2026-10-15 孩子线二轮）。
## 与 `script/text_vars.gd` 的 RANK_ATTRS 同序，保证「最高属性」在文本占位符与条件判定里
## 是同一套结论；int 排第一 = 原文「（相同按 int 最高算）」。
const TOP_ATTR_ORDER := ["int", "bod", "app", "str"]

## 播放一段剧情。
##   start_index = **续播起点**（D-SV10），默认 **-1 = 从头正常播放**（不抑制任何 effect）。
##                 ≥0 表示「读档续播到该句」：0..start_index 的节点 effect 视为已执行。
##   extra_context = 触发器/异步结算注入的文本变量上下文（槽位→名字等）。
## ⚠️ 别把默认值写成 0：那样正常起播也会把第 0 句标成「effect 已执行」→ 第一句的
##    数值 / 标签静默丢失（探针 `debug/_plot_resume_probe.gd` 抓到过这一条）。
func add_plot(file_path:String, plot_name:String, extra_context: Dictionary = {}, start_index: int = -1):
	if Player.is_dialogue_exist:
		return
	# D-SV10：先确认剧情真的存在再进对话态。剧情名写错 / 文件为空时，原实现会拿空字典
	# 进 DialogueUI → dialogue_list[0] 越界崩；读档续播也走这条，宁可放弃续播、清掉锚点，
	# 不可把读档带崩。
	var all_plot: Dictionary = load_json(file_path)
	var plot_v: Variant = find_plot(all_plot, plot_name)
	if not (plot_v is Dictionary) or (plot_v as Dictionary).is_empty():
		push_warning("PlotImporter: 剧情 '%s' 不存在于 %s，跳过播放" % [plot_name, file_path])
		Player.plot = {}
		return
	var plot: Dictionary = plot_v
	Player.is_dialogue_exist = true
	# 孤儿院首次判定（2026-09-26）：进入任何剧情都算玩家已经历过事件 →
	# 摘除「与小七相遇」（首次到访标记）。注意触发器的 display 分流在此刻**之前**已选定，
	# 故孤儿院自己的「首次」剧情不受影响（它正是被选中的那一段）。
	Player.remove_tag(TutorialManager.FIRST_VISIT_TAG)
	# D-DOC11（2026-08-24）：把触发器传入的 extra_context（槽位→名字映射等）
	# 注入到每个对话节点的 context 中，使 {executor_name1} 等占位符可解析。
	if not extra_context.is_empty():
		_inject_context(plot, extra_context)
	# D-SV10：登记剧情位置锚点（存档写盘时带上它，读档据此续播）。
	# start_index<0（正常起播）时锚点 index 记 0 —— 即「正停在第 0 句」。
	_set_plot_anchor(file_path, plot_name, maxi(start_index, 0), extra_context)
	execute_dialogue(plot, start_index)


## D-SV10：写入剧情位置锚点。ctx 深拷贝，避免与调用方后续改动共享引用。
func _set_plot_anchor(file_path: String, plot_name: String, index: int, ctx: Dictionary) -> void:
	Player.plot = {
		"path": file_path,
		"name": plot_name,
		"index": index,
		"ctx": ctx.duplicate(true),
	}


## D-SV10：读档后恢复被中断的剧情 —— 从存档记下的句号续播到中断的那一句。
##
## 判据全靠 `Player.plot`：非空字典 = 存档时正处在一段剧情里。
## 三种情况不起续播（保持安全，不崩、不抢）：
##   ① 锚点为空 / 缺 path 或 name（清掉锚点，避免反复尝试）
##   ② 场景自己已经在 `_ready` 里起了别的剧情（is_dialogue_exist=true）→ 让位，锚点保留
##   ③ 剧情文件已不存在 / 剧情名已改（由 add_plot 内部兜底并清锚点）
## 返回是否真的起了续播。
func resume_plot_if_any() -> bool:
	var anchor_v: Variant = Player.plot
	if not (anchor_v is Dictionary) or (anchor_v as Dictionary).is_empty():
		return false
	var anchor: Dictionary = anchor_v
	var pp: String = String(anchor.get("path", ""))
	var pn: String = String(anchor.get("name", ""))
	if pp == "" or pn == "":
		Player.plot = {}
		return false
	if Player.is_dialogue_exist:
		return false
	var idx: int = int(anchor.get("index", 0))
	var ctx_v: Variant = anchor.get("ctx", {})
	var ctx: Dictionary = ctx_v if ctx_v is Dictionary else {}
	add_plot(pp, pn, ctx, idx)
	return true


## D-DOC11：把 extra_context 合并进 plot 每个节点的 context 字段。
func _inject_context(plot: Dictionary, extra_context: Dictionary) -> void:
	for key in plot:
		var node: Variant = plot[key]
		if not (node is Dictionary):
			continue
		var existing: Dictionary = node.get("context", {})
		# extra_context 优先（触发器侧动态值覆盖剧情静态值）
		var merged: Dictionary = extra_context.duplicate()
		for k in existing:
			merged[k] = existing[k]
		node["context"] = merged
	

## 读剧情 JSON。任何一步失败都返回 {} 并 push_warning，**绝不崩** ——
## 读档续播（resume_plot_if_any）依赖这条：存档里的剧情文件若已被改名/删除，
## 失败的只会是「这一段续播」，不会把读档本身带崩。
func load_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_warning("PlotImporter: 剧情文件不存在 %s" % file_path)
		return {}
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_warning("PlotImporter: 无法打开剧情文件 %s" % file_path)
		return {}
	var reply: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (reply is Dictionary):
		push_warning("PlotImporter: 剧情文件解析失败（非 JSON 对象）%s" % file_path)
		return {}
	return reply


func find_plot(all_plot, plot_name:String):
	return all_plot.get(plot_name, {})
	
	
## 由 plot 字典建成 DialogueGroup 并交给 DialogueUI 播放。
## `start_index` = 续播起点（D-SV10）：**≥0** 时把断点及之前的节点标成「effect 已执行」；
## -1（默认）= 从头正常播，不抑制任何 effect。
func execute_dialogue(plot: Dictionary, start_index: int = -1):
	var dialogue_scene = load(UI)
	var dialogue_ui = dialogue_scene.instantiate()

	# 交给覆盖层管理器（D-UI6）。对白挂在专用 CanvasLayer 上，不再直接塞进 root：
	#   - 层级确定（业务覆盖层，压住地图与 HUD，但在教学层之下）
	#   - Esc 不关对白（esc_closes=false），对白要走自己的推进/结束流程
	#   - 切场景时自动清理，不会留在下一幕
	# 这里保持 deferred：add_plot 经常被 scene/_ready（如 guide 的开场）串到调用，
	# 此刻同步挂载会撞上 "Parent node is busy setting up children"。
	OverlayRoot.push_overlay.call_deferred(dialogue_ui, {
		"modal": true,
		"esc_closes": false,
	})
	
	var dialogue_group = DialogueGroup.new()
	dialogue_group.layout = String(plot.get("layout", "default"))
	
	for i in range(1000):  
		var key = str(i) + "th"
		if plot.has(key):
			var dialogue_data = plot[key]
			
			var dialogue = Dialogue.new()
			dialogue.character_name = dialogue_data.get("name", "")
			dialogue.content = dialogue_data.get("text", "")
			# 立绘：可选字段，缺省按 character_name 自动反查（见 PortraitRegistry）
			dialogue.portrait = dialogue_data.get("portrait", "")
			dialogue.is_option = dialogue_data.get("is_option",false)
			dialogue.next =dialogue_data.get("next",-1)
			dialogue.effect = dialogue_data.get("effect",{})
			# 条件跳转 nexts：[{"condition": <条件>, "next": <int>}]，首个命中条件的 next 生效
			var raw_nexts = dialogue_data.get("nexts", [])
			dialogue.nexts = []
			for ne in raw_nexts:
				dialogue.nexts.append({
					"condition": ne.get("condition", {}),
					"next": ne.get("next", -1)
				})
			var ctx: Variant = dialogue_data.get("context", {})
			if ctx is Dictionary:
				dialogue.context = ctx
			dialogue.options = []
			if dialogue_data.has("options"):
				for option_data in dialogue_data["options"]:
					var option = {
						"text": option_data.get("text", ""),
						"next": option_data.get("next", -1),
						"effect": option_data.get("effect", {}),
						"condition": option_data.get("condition", {})
					}
					option['is_ava'] = deal_condition(option["condition"], dialogue_data.get("context", {}))
					dialogue.options.append(option)
						
			# D-SV10：续播时，断点**及其之前**的节点 effect 已在存档前落地（数值/标签/卡
			# 都已写进存档的 Player 状态）→ 提前标成「已执行」，重播不会二次结算。
			# ⚠️ 必须含 i == start_index：存档那一刻当前句的 effect 早已同步执行过
			#    （见 dialogue_ui.display_next_dialogue 的执行顺序）。
			# ⚠️ 必须带 start_index >= 0 的闸：正常起播（-1）时一句都不能抑制。
			if start_index >= 0 and i <= start_index:
				dialogue.is_effect_excute = true
			dialogue_group.dialogue_list.append(dialogue)
		else:
			break

	# 同样 deferred：保证 _ready 跑完、@export 节点就位再调用。
	dialogue_ui.show_dialogue_group.call_deferred(dialogue_group, start_index)
	

func deal_condition(condition, ctx: Dictionary = {})-> bool:
	if condition == {}:
		return true
	else:
		if sentence_condition(condition, ctx):
			return true
	return false


## 2026-09-09 触发器总数值口径（用户拍板）：触发器里数值鉴定一律 = 总数值
## （当前卡槽里人物属性之和 + bonus，即生效值）。剧情由触发器带卡槽触发时，
## ctx 注入 `_investigators`（已放人物卡的生效属性 + tags，见 action_queue._build_plot_context）：
## - attrs 条件 → 按 _investigators 生效属性求和判定（多槽=求和，单槽=该人物）；
## - tags 条件 → 玩家 OR 队伍任一成员命中（并集，故事 tag 门控不受影响）；
## 无队伍上下文（普通剧情/选项）→ 回退玩家判定（历史行为，零变化）。
func sentence_condition(condition, ctx: Dictionary = {})-> bool:

	if "money" in condition:
		var money_condition = condition.money
		var left = money_condition.get("left", 0)
		var right = money_condition.get("right", 9999999)

		# 检查玩家金钱是否在[left, right]范围内
		if Player.player_money < left or Player.player_money > right:
			return false

	if "tags" in condition:
		var tags = condition.tags

		# 玩家拥有指定标签，或（触发器队伍上下文）队伍任一成员拥有
		if not _ctx_tags_meet(ctx, tags):
			return false
	
	if "num_tags" in condition:
		var num_tags = condition.num_tags
		for num_tag in num_tags:
			if not Player.player_meet_num_tag(num_tags[num_tag].name,num_tags[num_tag].left,num_tags[num_tag].right):
				return false
	
	if "npc" in condition:
		var npc_conditions = condition.npc
		
		for npc_name in npc_conditions:
			var npc_condition = npc_conditions[npc_name]
			var tags = npc_condition.get("tags", [])
			var num_tags = npc_condition.get("num_tags", {})
			# 检查NPC是否拥有指定标签
			if not Player.npc_has_tags(npc_name, tags, 1):
				return false
			
			for num_tag_name in num_tags:
				if not Player.npc_meet_num_tag(num_tags[num_tag_name].name,npc_name,num_tags[num_tag_name].left,num_tags[num_tag_name].right):
					return false

	if "attrs" in condition:
		var attrs = condition.attrs
		for attr_name in attrs:
			var attr_cond = attrs[attr_name]
			for compare in attr_cond:
				var value := int(attr_cond[compare])
				if not _ctx_attr_meet(ctx, attr_name, compare, value):
					return false

	# any_attrs（2026-10-11 孩子线）：写法同 attrs，但**任一属性命中即算过**。
	# 用于原文里「str，bod：」这种「两个属性哪个够都行」的门槛（`{"str":{">":5},"bod":{">":5}}`）。
	if "any_attrs" in condition:
		var any_attrs = condition.any_attrs
		var any_hit := false
		for attr_name in any_attrs:
			var ok := true
			for compare in any_attrs[attr_name]:
				if not _ctx_attr_meet(ctx, attr_name, compare, int(any_attrs[attr_name][compare])):
					ok = false
					break
			if ok:
				any_hit = true
				break
		if not any_hit:
			return false

	# attr_sum（2026-10-11 孩子线）：几个主体的**生效属性之和**区间判定。
	# 写法 {"attr":"bod", "of":["player","child"], ">":11}；比较语义同 attrs（">"=≥、"<"=≤、"="相等）。
	# 用于「你与孩子加起来的体魄」这类原文条件（单个主体的 attrs 无法表达求和）。
	if "attr_sum" in condition:
		var sum_spec = condition.attr_sum
		var sum_attr := String(sum_spec.get("attr", ""))
		var sum_total := 0
		for who in sum_spec.get("of", []):
			sum_total += _subject_attr(String(who), sum_attr)
		for compare in sum_spec:
			if compare == "attr" or compare == "of":
				continue
			if not _cmp_meet(sum_total, compare, int(sum_spec[compare])):
				return false

	# D-NOB：贵族等级门控。写法同 attrs：{"nobility": {">": 2}} / {"=": 3} / {"<": 4}
	# 语义与 player_attr_meet 一致：">"=≥(noble>=value)，"<"=≤，"="=相等。
	if "nobility" in condition:
		var noble_cond = condition.nobility
		var noble := int(Player.nobility)
		for compare in noble_cond:
			var value := int(noble_cond[compare])
			match compare:
				"=":
					if noble != value:
						return false
				">":
					if noble < value:
						return false
				"<":
					if noble > value:
						return false

	# top_attr（2026-10-15 孩子线二轮）：判定某主体的**最高属性**是否落在给定集合里。
	# 写法 {"top_attr": {"who": "player"|"child"|<npc键>, "one_of": ["int", ...], "tie_order": [...]}}
	#   who 缺省 "player"；one_of 必填（最高属性属于其中任一即过）。
	#   并列时按 tie_order 取先者，缺省 ["int","bod","app","str"]（与 text_vars.RANK_ATTRS 同序，
	#   满足原文「相同按 int 最高算」—— int 排第一，故并列时 int 胜出）。
	#   主体不存在（无孩子 / npc 无此条目）→ 判否（宁可落兜底分支，不给「无主体也算命中」）。
	# 用途：「找老师（当 int 位最高的属性值时）」这类**按最优属性分流**的门槛，单靠 attrs
	#   的绝对阈值表达不了（阈值问的是「够不够」，这里问的是「是不是你最强的那一项」）。
	if "top_attr" in condition:
		var top_spec: Dictionary = condition.top_attr
		var top_one_of: Array = top_spec.get("one_of", [])
		var top_order: Array = top_spec.get("tie_order", TOP_ATTR_ORDER)
		var top_attrs := _subject_attrs(String(top_spec.get("who", "player")))
		if top_attrs.is_empty():
			return false
		var top_best := ""
		var top_best_val := -2147483648
		for a in top_order:
			var v := int(top_attrs.get(String(a), 0))
			if v > top_best_val:
				top_best_val = v
				top_best = String(a)
		if not (top_best in top_one_of):
			return false

	if "child" in condition:
		var child_conditions = condition.child
		for child_id in child_conditions:
			var child_condition = child_conditions[child_id]
			var tags = child_condition.get("tags", [])
			var num_tags = child_condition.get("num_tags", {})
			var attrs = child_condition.get("attrs", {})
			var matched := false
			if child_id == "*" or child_id == "":
				for cid in Player.npc.keys():
					if _npc_is_child(cid) and Player.npc_has_tags(cid, tags, 1) \
							and _npc_meet_num_tag_for(cid, num_tags) and _npc_meet_attrs_for(cid, attrs):
						matched = true
						break
			elif Player.npc.has(child_id) and _npc_is_child(child_id):
				if Player.npc_has_tags(child_id, tags, 1) and _npc_meet_num_tag_for(child_id, num_tags) \
						and _npc_meet_attrs_for(child_id, attrs):
					matched = true
			if not matched:
				return false

	return true


# ============================================================
#  触发器队伍上下文判定（2026-09-09 总数值口径）
# ============================================================

## ctx 是否带触发器队伍（_investigators 非空 = 剧情由触发器带卡槽触发）。
func _ctx_has_team(ctx: Dictionary) -> bool:
	var invs: Variant = ctx.get("_investigators", null)
	return invs is Array and not (invs as Array).is_empty()


## attrs 判定：有队伍 → 总数值 = Σ _investigators 生效属性（effective 已含 bonus）；
## 无队伍 → 玩家属性（player_attr_meet，比较语义一致：">"=≥、"<"=≤、"="=相等）。
func _ctx_attr_meet(ctx: Dictionary, attr_name: String, compare: String, value: int) -> bool:
	if _ctx_has_team(ctx):
		var total := 0
		for inv in ctx["_investigators"]:
			total += int((inv as Dictionary).get(attr_name, 0))
		match compare:
			"=":
				return total == value
			">":
				return total >= value
			"<":
				return total <= value
			_:
				return false
	return Player.player_attr_meet(attr_name, compare, value)


## tags 判定：有队伍 → 玩家全满足 或 队伍任一成员全满足（并集）；
## 无队伍 → 仅玩家（历史行为）。
func _ctx_tags_meet(ctx: Dictionary, tags: Array) -> bool:
	if not _ctx_has_team(ctx):
		return Player.player_has_tags(tags, 1)
	if Player.player_has_tags(tags, 1):
		return true
	for inv in ctx["_investigators"]:
		var itags: Array = (inv as Dictionary).get("tags", [])
		var all_hit := true
		for t in tags:
			if not (t in itags):
				all_hit = false
				break
		if all_hit:
			return true
	return false


## 孩子判定辅助：指定 npc 条目是否带 "child" 标签（孩子已并入 npc 系统）。
static func _npc_is_child(cid: String) -> bool:
	var entry: Variant = Player.npc.get(cid, null)
	return entry is Dictionary and "child" in entry.get("tags", [])


## 孩子数值标签区间判定：检查指定孩子 npc 的 num_tags 是否全部落在 [left, right]。
static func _npc_meet_num_tag_for(cid: String, num_tags: Dictionary) -> bool:
	for nt_name in num_tags:
		var spec = num_tags[nt_name]
		var name = spec.get("name", nt_name)
		var left = int(spec.get("left", 0))
		var right = int(spec.get("right", 9999999))
		if not Player.npc_meet_num_tag(name, cid, left, right):
			return false
	return true


# ============================================================
#  孩子属性条件（2026-10-11 孩子线）
# ============================================================

## 比较语义统一入口（与 player_attr_meet / _ctx_attr_meet 一致）：
## ">" = 大于等于、"<" = 小于等于、"=" = 相等。
static func _cmp_meet(actual: int, compare: String, value: int) -> bool:
	match compare:
		"=":
			return actual == value
		">":
			return actual >= value
		"<":
			return actual <= value
	return false


## 「唯一孩子」的 npc 键（首个带 "child" 标签的条目）；没有孩子时返回 ""。
## 单孩子设计（孤儿院三选一）下即是那个孩子，剧情 effect 不必写死 July / Electra。
static func child_key_of() -> String:
	for key in Player.npc.keys():
		if _npc_is_child(String(key)):
			return String(key)
	return ""


## 孩子属性区间判定：查该孩子**生效属性**（裸值 + tag/装备 bonus，与鉴定同口径）。
## attrs 写法与其它地方一致：{"str": {">": 5}}。
static func _npc_meet_attrs_for(cid: String, attrs: Dictionary) -> bool:
	if attrs.is_empty():
		return true
	var eff := Player.effective_npc_attrs(cid)
	for attr_name in attrs:
		var actual := int(eff.get(str(attr_name), 0))
		for compare in attrs[attr_name]:
			if not _cmp_meet(actual, compare, int(attrs[attr_name][compare])):
				return false
	return true


## attr_sum 的主体取值：player=主角生效属性 / child=唯一孩子生效属性 / 其他=当 npc 键查。
func _subject_attr(who: String, attr: String) -> int:
	match who:
		"player":
			return int(Player.effective_self_attrs().get(attr, 0))
		"child":
			var cid := child_key_of()
			if cid == "":
				return 0
			return int(Player.effective_npc_attrs(cid).get(attr, 0))
	if Player.npc.has(who):
		return int(Player.effective_npc_attrs(who).get(attr, 0))
	return 0


## top_attr 的主体整套生效属性（2026-10-15 孩子线二轮）。主体取值同 _subject_attr，
## 差别只在取「一整套」而非单个属性。主体不存在 → 空字典（调用方据此判否）。
static func _subject_attrs(who: String) -> Dictionary:
	match who:
		"player":
			return Player.effective_self_attrs()
		"child":
			var cid := child_key_of()
			if cid == "":
				return {}
			return Player.effective_npc_attrs(cid)
	if Player.npc.has(who):
		return Player.effective_npc_attrs(who)
	return {}


# ============================================================
#  按键名播放剧情（D-C2 / 亲历鉴定「入剧情」）
# ============================================================

## 对话框键名 → 剧情文件路径 的注册表（数据驱动，集中配置）。
## 位于 resoures/plot/dialogue_registry.json，结构 {"剧情键名": "res://...json路径"}。
## 设计意图：触发器 harvest.dialogue 只写「键名」，由本注册表解析到具体文件，
## 实现「绝大部分剧情播放可通过配置 JSON 完成」。
var _dialogue_registry: Dictionary = {}


## 按对话键名播放剧情（D-C2）。键名取自触发器 harvest.dialogue / fail_harvest.dialogue。
## 未注册 / 指向文件不存在 → 安全 no-op（仅 push_warning），不报错不崩溃，
## 便于尚未配置剧情时照常推进（如 demo 阶段很多 dialogue 键仅占位）。
func play_by_key(plot_key: String) -> void:
	if plot_key == "":
		return
	_ensure_registry()
	var path: Variant = _dialogue_registry.get(plot_key, null)
	if path == null or not (path is String):
		push_warning("PlotImporter: 未注册剧情键 '%s'，跳过播放（如需播放请在 dialogue_registry.json 登记）" % plot_key)
		return
	if not ResourceLoader.exists(path):
		push_warning("PlotImporter: 剧情键 '%s' 指向文件不存在：%s" % [plot_key, path])
		return
	add_plot(path, plot_key)


## 该剧情键当前是否可播（D-GRAD1 毕业结局队列用）：注册表有键 + 文件存在 + 段落非空。
## 与 play_by_key 同一份判据（复用 _ensure_registry / load_json / find_plot），避免两处漂移——
## 调用方（毕业队列）必须「先确认能播再入队/起播」，否则坏键会让结局永远等不到
## dialogue_finished、卡在 playing。
func can_play(plot_key: String) -> bool:
	if plot_key == "":
		return false
	_ensure_registry()
	var path: Variant = _dialogue_registry.get(plot_key, null)
	if not (path is String) or not ResourceLoader.exists(path):
		return false
	var seg: Variant = find_plot(load_json(path), plot_key)
	return seg is Dictionary and not (seg as Dictionary).is_empty()


## 惰性加载注册表（首次使用时读，之后缓存）。
func _ensure_registry() -> void:
	if not _dialogue_registry.is_empty():
		return
	var f := FileAccess.open("res://resoures/plot/dialogue_registry.json", FileAccess.READ)
	if f == null:
		push_warning("PlotImporter: 找不到 dialogue_registry.json（res://resoures/plot/dialogue_registry.json），剧情键播放将全部 no-op")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_dialogue_registry = parsed
	else:
		push_warning("PlotImporter: dialogue_registry.json 解析失败（非字典）")
