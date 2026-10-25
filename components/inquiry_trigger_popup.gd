## 商业街打听触发器弹窗 —— 继承 TriggerPopup（D-DOC14）。
##
## 打听 = resolver「inquiry」+ duration=1 异步：
##   放「执行者」卡 → 点执行 → App 门槛 → 主骰 1d app（骰面=执行者 app 生效值）分三档
##   → 中档(4-6)/高档(≥7) 再 1d10 细分 → 各分支 effect（金钱-1/物品/进打听池/app+1）
##   → 副骰 1d bod <2 疲惫（九除外）→ 冻结过天 → ResultPopup 落地。
##
## 通过 override 父类两个钩子承载专属结算：
##   - _compute_custom_async_result（duration>0 异步，只算不落地）
##   - _resolve_custom（duration=0 即时兜底）
## 其余（卡槽装配/冻结/过天/落地/打听池抽取记录）全部复用父类能力。
class_name InquiryTriggerPopup
extends TriggerPopup

const INQUIRY_POOL_PATH := "res://resoures/inquiry_pool.json"

## 打听池事件缓存（首次读取后复用）。
var _pool_cache: Dictionary = {}
var _pool_ready := false


## D-DOC14：打听异步结算（只算不落地，返回统一结算字典，由父类冻结过天）。
func _compute_custom_async_result(resolver: String, display: Dictionary) -> Dictionary:
	if resolver != "inquiry":
		return {}
	return _compute_inquiry(display)


## D-DOC14：打听即时兜底（duration=0 时由父类 _resolve_special 路由到这里）。
func _resolve_custom(resolver: String, display: Dictionary) -> bool:
	if resolver != "inquiry":
		return false
	var r := _compute_inquiry(display)
	# 即时路径：直接落地 effect + 文本 + 剧情（复用父类能力），再结束流程。
	var eff: Dictionary = r.get("effect", {})
	if not eff.is_empty():
		TriggerManager.apply_effect(eff, _placed)
	_add_item_cards(r)
	var plot_v: Variant = r.get("plot", null)
	if plot_v is Dictionary:
		_land_plot(plot_v)
	_append_result(String(r.get("text", "")))
	_finish_flow()
	return true


## 把结算得到的物品卡（秘氛/困惑/博学等）加入主 UI 手牌区，使「获得物品」落地为可见的卡。
func _add_item_cards(result: Dictionary) -> void:
	var cards: Variant = result.get("item_cards", null)
	if not (cards is Array):
		return
	var ca: CardArea = TriggerManager.get_card_area()
	for c in cards:
		if not (c is CardData):
			continue
		if ca != null:
			ca.add_card(c)
		else:
			# D-HAND1：卡牌区不在场时入账本，回主 UI 自动补发（旧实现直接丢）。
			Player.add_hand_card(c)


## 打听完整结算：返回 {effect, text, plot, item_cards}。
## plot 为打听池抽到的剧情 {"path","name"}；未抽中则为 null。
## item_cards 为 stuff 里可入手的物品卡（秘氛/困惑/博学等，落地时加入手牌区）。
func _compute_inquiry(_display: Dictionary) -> Dictionary:
	var executor: CardData = _placed.get("执行者", null)
	if executor == null:
		return {"effect": {}, "text": "需要一名执行者。", "plot": null}

	var name := executor.display_name
	var eff: Dictionary = Player.effective_attrs_of(executor)
	var app := int(eff.get("app", 0))
	var bod := int(eff.get("bod", 0))

	# —— App 门槛（生效值）——
	if app < 6:
		return {"effect": {}, "text": "%s身上有一种生人勿近的气质，这项任务有点强人所难了。" % name, "plot": null}

	# —— 主骰 1d app（骰面=app 生效值，至少 1 面）——
	var salt := _placed_salt()
	var roll_app := Player.roll_dice("inquiry:app:%s" % _trigger_id, max(1, app), salt)

	var text := ""
	var effect: Dictionary = {}
	var plot_v = null

	if roll_app <= 3:
		# 分支一：在吵嚷的大街，只能收获喧嚣。
		text = "在吵嚷的大街，只能收获喧嚣。"
		effect = _money_minus_one()

	elif roll_app <= 6:
		# 中档 4-6：二次骰 1d10 细分 二/三/四/五
		var roll10 := Player.roll_dice("inquiry:d10:%s" % _trigger_id, 10, salt)
		if roll10 <= 3:
			# 二：光怪陆离…
			text = "光怪陆离，鬼神邪说。街上有人大肆宣扬不可名状之物。预防局的人恐怕也在附近，%s没有逗留太久。" % name
			effect = _money_minus_one({"stuff": ["秘氛"]})
		elif roll10 <= 6:
			# 三：哭声笑声…
			text = "哭声、笑声，悲欢在人间反复重演，谁又能看破这一切？"
			effect = _money_minus_one({"stuff": ["困惑"]})
		elif roll10 <= 9:
			# 四：穿越街巷…
			text = "穿越街巷仿佛穿过了书上的人世道理。"
			effect = _money_minus_one({"stuff": ["博学"]})
		else:
			# 五：进打听池
			text = "溜溜转转，打听到些街坊闲谈。"
			var drawn := _draw_inquiry(salt, executor)
			effect = _money_minus_one(drawn.effect)
			plot_v = drawn.plot

	else:
		# 高档 ≥7：先看是否带「打听大成功」tag（执行者动态 tag）
		var has_success := _executor_has_tag(executor, "打听大成功")
		if not has_success:
			# 九：首次顿悟 —— app+1(封顶10) + 获得「打听大成功」+ 金钱-1
			text = "世事洞明，人情练达。温润如玉，又不卑不亢。所见所闻令%s豁然开朗。" % name
			effect = {
				"money": -1,
				"slot_attrs": {"执行者": {"app": 1}},
				"slot_tags": {"执行者": ["打听大成功"]},
			}
		else:
			# 六/七/八：已有打听大成功，1d10 细分
			var roll10 := Player.roll_dice("inquiry:d10:%s" % _trigger_id, 10, salt)
			if roll10 <= 3:
				# 七：人群突然静默…
				text = "人群突然静默，你听见自己的影子在脚下翻了个身。桥洞深处传来一声若有若无的应答。"
				var drawn := _draw_inquiry(salt, executor)
				effect = _money_minus_one(_merge_drawn(drawn, {"stuff": ["秘氛"]}))
				plot_v = drawn.plot
			elif roll10 <= 6:
				# 六：行者无疆…
				text = "行者无疆，可何处来，又何处去？无尽的前行不会给答案。"
				var drawn := _draw_inquiry(salt, executor)
				effect = _money_minus_one(_merge_drawn(drawn, {"stuff": ["困惑"]}))
				plot_v = drawn.plot
			else:
				# 八：宇宙的尺度…
				text = "宇宙的尺度，美的比例，物质的反应。一路上的见闻让%s受益匪浅。" % name
				var drawn := _draw_inquiry(salt, executor)
				effect = _money_minus_one(_merge_drawn(drawn, {"stuff": ["博学"]}))
				plot_v = drawn.plot

	# —— 副骰 1d bod <2 → 疲惫（九除外）——
	if not (roll_app >= 7 and not _executor_has_tag(executor, "打听大成功")):
		var roll_bod := Player.roll_dice("inquiry:bod:%s" % _trigger_id, max(1, bod), salt)
		if roll_bod < 2:
			effect = _merge_effect(effect, {"fatigue": true})
			text += "繁多的消息让%s身心俱疲。" % name

	return {"effect": effect, "text": text, "plot": plot_v, "item_cards": _stuff_cards(effect)}


## 从结算 effect 的 stuff 里解析出可入手的物品卡（秘氛/困惑/博学等）。
## 只认 CardRegistry 里存在的道具（others.json 已并入注册表）；「book:*」书卡走 book_card 渠道，不在此处理。
func _stuff_cards(effect: Dictionary) -> Array[CardData]:
	var out: Array[CardData] = []
	var stuff: Variant = effect.get("stuff", null)
	if stuff is Array:
		for s in stuff:
			var sn := String(s)
			if sn.begins_with("book:"):
				continue
			var c: CardData = CardRegistry.get_card(sn)
			if c != null:
				out.append(c)
	return out


## 金钱 -1 合并进给定 effect（保留已有键）。
func _money_minus_one(base: Dictionary = {}) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	out["money"] = -1
	return out


## 把打听池抽取结果（effect/plot）合并进给定 effect。
func _merge_drawn(drawn: Dictionary, base: Dictionary) -> Dictionary:
	var out: Dictionary = _merge_effect(base, drawn.get("effect", {}))
	return out


## 打听池抽取：随机抽一条**未抽过**且**条件满足**的剧情；池空 → 随机给 秘氛/困惑/博学。
## 事件含 hero_plot（主角变体）且执行者是主角时，改选 hero_plot。
## 返回 {effect:{}, plot: 或 null}。effect 里的 inquiry_drawn 由落地时写入 Player.inquiry_drawn。
func _draw_inquiry(salt: String, executor: CardData) -> Dictionary:
	var pool := _load_pool()
	var candidates: Array = []
	for id in pool:
		if String(id).begins_with("_"):
			continue
		if Player.inquiry_drawn.has(String(id)):
			continue
		var ev_v: Variant = pool[id]
		if not (ev_v is Dictionary):
			continue
		var ev: Dictionary = ev_v
		if not _inquiry_condition_ok(ev):
			continue
		candidates.append(String(id))

	if candidates.is_empty():
		# 池空兜底：随机三选一
		var items := ["秘氛", "困惑", "博学"]
		var idx := Player.roll_dice("inquiry:empty:%s" % _trigger_id, items.size(), salt) - 1
		return {"effect": {"stuff": [items[idx]]}, "plot": null}

	var idx := Player.roll_dice("inquiry:pick:%s" % _trigger_id, candidates.size(), salt) - 1
	var picked: String = candidates[idx]
	var ev: Dictionary = pool.get(picked, {})
	# 主角变体：执行者是主角（带 player tag）且事件有 hero_plot → 用主角版剧情。
	var plot_v: Variant = ev.get("plot", null)
	if executor != null and executor.id == "Hero":
		var hp: Variant = ev.get("hero_plot", null)
		if hp is Dictionary:
			plot_v = hp
	return {
		"effect": {"inquiry_drawn": [picked]},
		"plot": plot_v if plot_v is Dictionary else null,
	}


## 打听池事件级条件判定（目前支持 day 时间窗：min/max 闭区间，对应打听家事A「前3天」）。
func _inquiry_condition_ok(ev: Dictionary) -> bool:
	var cond: Variant = ev.get("condition", null)
	if not (cond is Dictionary):
		return true
	var c: Dictionary = cond
	var day_v: Variant = c.get("day", null)
	if day_v is Dictionary:
		var d: Dictionary = day_v
		var t := int(Player.time)
		if d.has("min") and t < int(d["min"]):
			return false
		if d.has("max") and t > int(d["max"]):
			return false
	return true


## 执行者（动态 tag）是否带某 tag：Hero → player_tags；其余 → Player.npc 条目 tags。
func _executor_has_tag(executor: CardData, tag: String) -> bool:
	if executor == null:
		return false
	if executor.id == "Hero":
		return tag in Player.player_tags
	var npc_key := EffectProcessor._npc_key_of(executor)
	var entry: Dictionary = Player.npc.get(npc_key, {})
	var tags_v: Variant = entry.get("tags", [])
	return tag in (tags_v if tags_v is Array else [])


## 加载打听池事件表（惰性缓存）。
func _load_pool() -> Dictionary:
	if _pool_ready:
		return _pool_cache
	_pool_ready = true
	var f := FileAccess.open(INQUIRY_POOL_PATH, FileAccess.READ)
	if f == null:
		push_warning("InquiryTriggerPopup: 无法打开 %s" % INQUIRY_POOL_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_pool_cache = parsed
	return _pool_cache
