## text_vars.gd — 文本变量替换库（纯函数，无节点依赖）。
##
## 占位符语法： {命名空间.键}  或  {裸键}
## 解析顺序：
##   1) ctx 覆盖（调用方注入的动态变量：卡牌名、流程 tag、计算提示等）
##   2) 队伍属性占位符：{int}/{bod}/{app}/{str}
##      —— 解析为「调查者」中该属性最高者之名；
##         一人只占用一个槽位（贪心去重）；{tags:xxx} 持有者不参与排序。
##   3) 标签指代占位符：{tags:xxx}
##      —— 解析为「持有标签 xxx 之人」之名；
##         同时该（些）人从 {int}/{bod}/{app}/{str} 的排序池中排除。
##   4) 全局命名空间：player.* / executor.* / npc.* / child.*
##      —— {player_name}/{player.*} = 主角；{executor_name} = 执行者（触发器「执行者」槽卡名，缺省回退主角名）
##   5) 未命中 → push_warning 并替换为空串。
##
## 「调查者」集合默认 = 主角 + 带「追随」标签的 npc；
## 调用方亦可通过 ctx["_investigators"] 注入自定义名单
##   （每项：{name, int, app, str, bod, tags}）。
extends RefCounted

const PATTERN := "\\{([^{}]+)\\}"

## 队伍属性占位符的键（去重排序用，决定处理优先级）
const RANK_ATTRS := ["int", "bod", "app", "str"]

## 解析文本中的占位符，返回替换后的字符串。
static func resolve(raw, ctx: Dictionary) -> String:
	if raw == null or raw == "":
		return ""
	var re := RegEx.create_from_string(PATTERN)
	var s := String(raw)

	# 1) 预扫描：收集 {tags:xxx} 指令 -> 排除标签 + 标签->人名
	var excluded_tags: Array = []
	var tag_name := {}        # tag -> 首位持有者之名
	var investigators := _build_investigators(ctx)
	for m in re.search_all(s):
		var tok := _norm_token(m.get_string(1))
		if tok.begins_with("tags:"):
			var t := tok.substr(5).strip_edges()
			if t == "":
				continue
			if t not in excluded_tags:
				excluded_tags.append(t)
			if not tag_name.has(t):
				tag_name[t] = _find_tag_holder(investigators, t)

	# 2) 仅对文本中实际出现的属性计算槽位（避免为未用属性空占一人）
	var present_attrs: Array = []
	for a in RANK_ATTRS:
		if s.find("{%s}" % a) != -1:
			present_attrs.append(a)
	var slots := _compute_slots(investigators, excluded_tags, present_attrs)

	# 3) 逐占位符替换
	var out := s
	var done: Dictionary = {}
	for m in re.search_all(s):
		var token: String = m.get_string(1)
		if done.has(token):
			continue
		done[token] = true
		var val := _lookup(token, ctx, slots, tag_name)
		out = out.replace("{%s}" % token, val)
	return out


## 占位符 -> 字符串
static func _lookup(token: String, ctx: Dictionary, slots: Dictionary, tag_name: Dictionary) -> String:
	var norm := _norm_token(token)
	# 2) 队伍属性占位符
	if norm in RANK_ATTRS:
		return str(slots.get(norm, ""))
	# 3) 标签指代占位符 -> 持有者之名
	if norm.begins_with("tags:"):
		var t := norm.substr(5).strip_edges()
		return str(tag_name.get(t, ""))
	# 4) 调用方注入的动态变量
	if ctx.has(token):
		return str(ctx[token])
	# 4.5) D-DOC11：{executor_name1}/{executor_name2}/... 从 ctx 取（触发器注入）
	if norm.begins_with("executor_name"):
		if ctx.has(norm):
			return str(ctx[norm])
		if ctx.has(token):
			return str(ctx[token])
	# 4.6) 裸键直接对应玩家/孩子字段
	match token:
		"player_name":
			# 兜底**只收在 Player.player_display_name() 这一处**：空名 / 历史占位串
			# 都变「主角」。以前这里直接返回原值，剧情正文会把「请输入你的名字」印出来。
			return Player.player_display_name()
		"executor_name":
			# 执行者名：优先从 ctx 取（触发器注入），未命中回退主角名（主角默认即执行者）
			return Player.player_display_name()
		"child_name":
			return str(Player.child_name)
		"nobility":
			return Player.player_nobility_title()
	# 5) 全局命名空间
	var parts: PackedStringArray = token.split(".", false)
	if parts.size() >= 2:
		match parts[0]:
			"player":
				return _player_var(parts[1])
			"executor":
				return _executor_var(parts[1], ctx)
			"npc":
				if parts.size() >= 3:
					return _npc_var(parts[1], parts[2])
			"child":
				# 单孩子设计：{child.name} / {child.tags} 取唯一（首个）孩子条目
				if parts.size() == 2:
					return _child_var(parts[1])
	# 6) 未命中
	push_warning("TextVars: 未解析的占位符 {%s}" % token)
	return ""


# ---------- 调查者集合 & 槽位计算 ----------

## 构建调查者名单：ctx 覆盖优先，否则 主角 + 带「追随」标签的 npc
static func _build_investigators(ctx: Dictionary) -> Array:
	if ctx.has("_investigators"):
		return ctx["_investigators"]
	var list := []
	# 主角
	var p_tags: Array = []
	for t in Player.player_tags:
		p_tags.append(String(t))
	list.append({
		"name": Player.player_display_name(),
		"int": int(Player.player_int),
		"app": int(Player.player_app),
		"str": int(Player.player_str),
		"bod": int(Player.player_bod),
		"tags": p_tags,
	})
	# 伙伴：npc 中带「追随」标签者
	for key in Player.npc.keys():
		var d = Player.npc[key]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var tgs: Array = []
		for t in d.get("tags", []):
			tgs.append(String(t))
		if "追随" in tgs:
			list.append({
				"name": str(d.get("name", key)),
				"int": int(d.get("int", 0)),
				"app": int(d.get("app", 0)),
				"str": int(d.get("str", 0)),
				"bod": int(d.get("bod", 0)),
				"tags": tgs,
			})
	return list


## 返回持有标签 tag 的首位调查者之名（无则 ""）
static func _find_tag_holder(investigators: Array, tag: String) -> String:
	for m in investigators:
		if tag in m["tags"]:
			return str(m["name"])
	return ""


## 计算各属性槽位：在排除名单者之外，贪心取最高者，一人一槽。
static func _compute_slots(investigators: Array, excluded: Array, attrs: Array) -> Dictionary:
	var eligible := []
	for m in investigators:
		var excl := false
		for t in m["tags"]:
			if t in excluded:
				excl = true
				break
		if not excl:
			eligible.append(m)
	var used: Array = []
	var slots := {}
	for attr in attrs:
		var best = null
		var best_val = -INF
		for m in eligible:
			if m["name"] in used:
				continue
			var v = m[attr]
			if v > best_val:
				best_val = v
				best = m
		if best != null:
			slots[attr] = str(best["name"])
			used.append(best["name"])
		else:
			slots[attr] = ""
	return slots


## 归一化占位符 token：全角冒号转半角、去除首尾空白
static func _norm_token(token: String) -> String:
	return token.replace("：", ":").strip_edges()


# ---------- 原有命名空间解析（保留） ----------

## 执行者命名空间：{executor.name}/{executor.int}/{executor.tags}/... 从 ctx 取执行者卡字段，
## 缺省回退主角字段（_player_var）。ctx 由 trigger_popup._build_slot_context/_build_plot_context
## 注入 executor.*（执行者卡 display_name/attrs/tags/description）。
static func _executor_var(field: String, ctx: Dictionary) -> String:
	if ctx.has("executor." + field):
		return str(ctx["executor." + field])
	return _player_var(field)


static func _player_var(field: String) -> String:
	match field:
		"name":
			return str(Player.player_name)
		"money":
			return str(Player.player_money)
		"age":
			return str(Player.player_age)
		"int":
			return str(Player.player_int)
		"app":
			return str(Player.player_app)
		"str":
			return str(Player.player_str)
		"bod":
			return str(Player.player_bod)
		"edu":
			return str(Player.player_edu)
		"att":
			return str(Player.player_att)
		"nobility":
			return str(Player.nobility)
		"tags":
			return ", ".join(Player.player_tags)
		_:
			return ""


static func _npc_var(name: String, field: String) -> String:
	var data: Dictionary = Player.npc.get(name, {})
	match field:
		"name":
			return str(data.get("name", name))
		"int":
			return str(data.get("int", 0))
		"app":
			return str(data.get("app", 0))
		"str":
			return str(data.get("str", 0))
		"bod":
			return str(data.get("bod", 0))
		"tags":
			return ", ".join(data.get("tags", []))
		_:
			return ""


static func _child_var(field: String) -> String:
	# child 现已并入 npc（统一带 "child" 标签）。游戏默认只收养一个孩子，
	# 直接取首个带 child 标签的 npc 条目；无孩子时返回空串（占位符未命中，由调用方兜底）。
	for key in Player.npc.keys():
		var entry: Variant = Player.npc.get(key, null)
		if not (entry is Dictionary and "child" in entry.get("tags", [])):
			continue
		match field:
			"name":
				return str(entry.get("name", key))
			"tags":
				return ", ".join(entry.get("tags", []))
		return ""
	return ""
