## ActionQueue —— 进行中 / 待结算行动队列（Autoload）。
##
## 动词占用式异步流程（密教模拟器 / 苏丹的游戏式）：触发器执行后提交一个行动，
## 等待 duration 个回合（由 EventSignal.day_changed 倒计时），归零后变为「已完成」，
## 由 UI 打开结算弹窗、点「确定」落地效果。
##
## 每个行动条目结构：
##   { id, trigger_id, slots:Dictionary{槽名:CardData}, result:Dictionary, wait:int, total:int, completed:bool,
##     from_hand:Array[CardData] }
##   - slots：占用卡快照（结算时依 from_hand 归还；效果/剧情仍对全槽生效）。
##   - result：统一结算字典 {effect, text, plot, book_card?}（由 TriggerPopup 算好、未落地）。
##   - from_hand（D-HAND2，2026-10-14）：**哪些占用卡当初是玩家从手牌拖进去的**。
##     结算时只归还这一部分 —— auto_fill / auto_attract 注入的卡（如送学的理性/感性/知觉）
##     从来不在玩家手上，不能当成行动收益发下去。
##
## 注：本期为内存版（不随存档持久化）；如需跨读档保留进行中行动，需在 SaveLoader 增加
##     序列化（CardData 引用需改为 id + 重建）。见 design 文档 TODO。

extends Node

const RESULT_POPUP := preload("res://components/result_popup.tscn")

## 行动列表变化（增 / 减 / 倒计时）时广播，UI 据此刷新面板。
signal actions_changed
## 某个行动倒计时归零、变为「已完成」时广播。
signal action_completed(action_id: String)

var _actions: Array = []


func _ready() -> void:
	if EventSignal.has_signal("day_changed"):
		EventSignal.day_changed.connect(_on_day_changed)


func _on_day_changed(_day: int) -> void:
	var changed := false
	for a in _actions:
		if not a.get("completed", false) and int(a.get("wait", 0)) > 0:
			a["wait"] = int(a["wait"]) - 1
			if int(a["wait"]) <= 0:
				a["wait"] = 0
				a["completed"] = true
				changed = true
				action_completed.emit(String(a["id"]))
	if changed:
		actions_changed.emit()


## 提交一个进行中行动。返回行动 id。
##   trigger_id：触发器名（用于「同触发器进行中时禁用打开」）。
##   slots：{槽名: CardData} 快照（占用卡，**含**引擎注入的 auto_fill 等，效果/剧情要按它定位）。
##   result：统一结算字典（未落地）。
##   duration：等待回合数（>=1）。
##   from_hand：D-HAND2 —— 上述占用卡里**来自玩家手牌**的那些，结算时只归还它们。
func enqueue(trigger_id: String, slots: Dictionary, result: Dictionary, duration: int,
		from_hand: Array[CardData] = []) -> String:
	var d: int = max(1, duration)
	var id := "%s_%d" % [trigger_id, Time.get_ticks_msec()]
	var entry := {
		"id": id,
		"trigger_id": trigger_id,
		"slots": slots,
		"result": result,
		"wait": d,
		"total": d,
		"completed": false,
		"from_hand": from_hand.duplicate(),
	}
	_actions.append(entry)
	actions_changed.emit()
	return id


## 是否存在某触发器的进行中 / 待结算行动（用于禁用再次打开）。
func has_active(trigger_id: String) -> bool:
	for a in _actions:
		if String(a.get("trigger_id", "")) == trigger_id:
			return true
	return false


func get_actions() -> Array:
	return _actions


func get_by_id(id: String) -> Dictionary:
	for a in _actions:
		if String(a.get("id", "")) == id:
			return a
	return {}


## 移除行动（结算完成后调用）。
func remove(id: String) -> void:
	for i in _actions.size():
		if String(_actions[i].get("id", "")) == id:
			_actions.remove_at(i)
			actions_changed.emit()
			return


## 取某触发器已完成（待结算）的行动；没有则返回空字典。
## 供 TriggerSpot 点击原触发点结算用（区分于 has_active：has_active 连「进行中」也算）。
func get_completed_by_trigger(trigger_id: String) -> Dictionary:
	for a in _actions:
		if String(a.get("trigger_id", "")) == trigger_id and bool(a.get("completed", false)):
			return a
	return {}


## 取某触发器「进行中」（尚未完成、倒计时未归零）的行动；没有则返回空字典。
## 供 TriggerSpot 显示「执行中：剩余 N 回合」灰态（区分于 has_active：只算未完成；
## 也区分于 get_completed_by_trigger：只算未归零）。条目含 wait（剩余回合数）。
func get_pending_by_trigger(trigger_id: String) -> Dictionary:
	for a in _actions:
		if String(a.get("trigger_id", "")) == trigger_id and not bool(a.get("completed", false)):
			return a
	return {}


## 结算已完成行动：弹 ResultPopup，点「确定」后落地。
## ActionPanel「结算」按钮与 TriggerSpot 点击原触发点共用此入口（结算语义单一来源）。
func settle(action_id: String) -> void:
	var a: Dictionary = get_by_id(action_id)
	if a.is_empty() or not bool(a.get("completed", false)):
		return
	var popup := RESULT_POPUP.instantiate() as ResultPopup
	OverlayRoot.push_overlay.call_deferred(popup, {"modal": true, "esc_closes": true})
	popup.setup.call_deferred(a.get("result", {}), _land.bind(action_id), "行动结算")


## ResultPopup「确定」回调：落地 effect + 归还卡 + plot + 移除行动 + 换图。
func _land(result: Dictionary, action_id: String) -> void:
	var a: Dictionary = get_by_id(action_id)
	if a.is_empty():
		return
	var slots: Dictionary = a.get("slots", {})
	var effect: Dictionary = result.get("effect", {})
	if not effect.is_empty():
		# 异步结算语义：流程早已结束，tags 直落 player_tags（不走 flow_tags）
		# D-DOC13（越狱）：传 placed 使 slot_tags / slot_remove_tags / slot_num_tags 等槽位效果可落地。
		EffectProcessor.apply(effect, {"placed": slots})
	var ca: CardArea = TriggerManager.get_card_area()
	# 归还占用卡：D-HAND2 —— **只还当初从手牌拿出来的卡**。
	# 人物卡一律归还；道具卡里**消耗品**（consumable 字段或 tag「消耗」）不归还
	# —— 使用后即消耗，无论行动成功与否（2026-09-08）。同步分支在 _consume_placed_consumables
	# 提前移出 _placed，异步占用模型则在此结算时「不加入返还列表」实现消耗。
	# 引擎注入的卡（auto_fill / auto_attract / 回合实例）不在 from_hand 里，
	# 它们从未属于玩家，不能当成行动收益发下去（送学的理性/感性/知觉正是这个坑）。
	var handed: Array = []
	for hc in a.get("from_hand", []):
		if hc is CardData:
			handed.append(hc)
	var returned: Array[CardData] = []
	for sn in slots:
		var c: CardData = slots[sn]
		if c == null or returned.has(c):
			continue
		if not handed.has(c):
			continue
		if c.card_type == "item" and c.is_consumable():
			continue
		returned.append(c)
	if ca != null and not returned.is_empty():
		ca.add_cards(returned)
	elif not returned.is_empty():
		# D-HAND1：卡牌区不在场时照样入账本，否则一次性丢失（旧实现直接静默丢）。
		for c in returned:
			if c is CardData:
				Player.add_hand_card(c)
	# 书卡（书店等）
	var book_v: Variant = result.get("book_card", null)
	if book_v is CardData:
		if ca != null:
			ca.add_card(book_v)
		else:
			Player.add_hand_card(book_v)
	# 物品卡（打听「获得物品」等）：结算得到的杂项物品（秘氛/困惑/博学）入卡牌区。
	var item_cards_v: Variant = result.get("item_cards", null)
	if item_cards_v is Array:
		for c in item_cards_v:
			if not (c is CardData):
				continue
			if ca != null:
				ca.add_card(c)
			else:
				Player.add_hand_card(c)
	# M4：plot {"path","name"}
	_land_plot(result.get("plot", null), slots)
	remove(action_id)
	# 异步结算后切场景（新手教程「回家」→ 家业）。goto_scene 在 result 顶层（非 effect 内）。
	var goto_v: Variant = result.get("goto_scene", "")
	if goto_v is String and String(goto_v) != "":
		Player.path = String(goto_v)
		get_tree().change_scene_to_file(String(goto_v))
		EventSignal.scene_entered.emit(String(goto_v))


## plot {"path","name"} 落地（书店/打工等异步结算剧情）。
## D-夜探（2026-09-08）：异步结算时放置卡已归还，剧情里的队伍占位符
## （{int}/{bod}/{app}/{str}/{tags:xx}/{executor_name1..N}）无法从 Player 追随池还原 ——
## 此处把结算快照 slots 的角色卡构建为 ctx（executor_nameN + _investigators）后传入，
## TextVars 据此解析「该次行动实际派出的人」。
func _land_plot(plot: Variant, slots: Dictionary = {}) -> void:
	if not (plot is Dictionary):
		return
	var p: Dictionary = plot
	var pp: String = String(p.get("path", ""))
	var pn: String = String(p.get("name", ""))
	if pp != "" and pn != "":
		PlotImporter.add_plot(pp, pn, _build_plot_context(slots))


## 由放置卡快照构建 plot 上下文（与 trigger_popup._build_plot_context 同口径：
## 首个角色卡注入 executor_name/executor.*，全部角色卡按槽序注入 executor_name1..N，
## 并以 _investigators 覆盖 TextVars 默认「主角+追随 npc」调查者池）。
func _build_plot_context(slots: Dictionary) -> Dictionary:
	var ctx: Dictionary = {}
	var investigators: Array = []
	var idx := 1
	for sn in slots:
		var c: CardData = slots[sn]
		if c == null or c.card_type != "character":
			continue
		var eff := Player.effective_attrs_of(c)
		investigators.append({
			"name": c.display_name,
			"int": int(eff.get("int", 0)),
			"app": int(eff.get("app", 0)),
			"str": int(eff.get("str", 0)),
			"bod": int(eff.get("bod", 0)),
			"tags": c.tags,
		})
		if idx == 1:
			ctx["executor_name"] = c.display_name
			ctx["executor.name"] = c.display_name
			ctx["executor.tags"] = ", ".join(c.tags)
			ctx["executor.desc"] = c.description
			for a in ["int", "app", "str", "bod"]:
				ctx["executor." + a] = eff.get(a, 0)
		ctx["executor_name%d" % idx] = c.display_name
		idx += 1
	ctx["_investigators"] = investigators
	return ctx
