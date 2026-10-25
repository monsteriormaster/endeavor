## 读书触发器弹窗 —— 继承 TriggerPopup（resolver="read_book"）。
##
## 读书 = resolver「read_book」+ duration=1 异步：
##   放「执行者」（人物）+「书」（item/book）两槽 → 点执行：
##     · 不满足书的 condition → 立即显示 condition_text，结束流程（不占回合）。
##     · 满足 → 显示 before_read（阅读前文本），冻结过天（占 1 回合）。
##   过天后结算：ResultPopup 播 read_description（阅读完文本）+ 落地 after_read
##     （属性加成 slot_attrs + 授 tag slot_tags，作用于执行者）。
##
## 通过 override 父类两个钩子承载专属结算：
##   - _compute_custom_async_result（duration>0 异步，只算不落地）
##   - _resolve_custom（duration=0 即时兜底 / 不满足条件的立即结束）
class_name ReadBookTriggerPopup
extends TriggerPopup

const EXECUTOR_SLOT := "执行者"
const BOOK_SLOT := "书"


## 异步结算（只算不落地）。condition 不满足 → 返回空（退回即时 _resolve_custom）。
func _compute_custom_async_result(resolver: String, _display: Dictionary) -> Dictionary:
	if resolver != "read_book":
		return {}
	var r := _compute_read_book()
	if not bool(r.get("condition_met", false)):
		return {}
	return {
		"effect": r.get("effect", {}),
		"text": r.get("read_description", ""),
		"before": r.get("before_read", ""),
		"plot": null,
	}


## 即时结算兜底（duration=0 / condition 不满足时由父类路由到这里）。
func _resolve_custom(resolver: String, _display: Dictionary) -> bool:
	if resolver != "read_book":
		return false
	var r := _compute_read_book()
	if bool(r.get("condition_met", false)):
		var eff: Dictionary = r.get("effect", {})
		if not eff.is_empty():
			TriggerManager.apply_effect(eff, _placed)
		_append_result(String(r.get("read_description", "")))
	else:
		_append_result(String(r.get("condition_text", "")))
	_finish_flow()
	return true


## 放书后的动态行（2026-10-17 图书馆）：能读 → 该书的 before_read；读不了 → 该书的
## condition_text（forbid_executors 命中 → forbid_text）。文本全部来自 books.json 本身，
## 这里不做文案创作 —— 用户口径「对应书籍的对应显示文本（能阅读/不能阅读）」。
## 返回空 = 保留基础文案（_derive_dynamic_text 的既有语义：非空则整行替换）。
## ⚠️ 只对触发器「图书馆」生效：书房「读书」共用本子类，放书后的显示行为不能被顺带改掉。
func _derive_dynamic_text(_display: Dictionary) -> String:
	# 2026-10-25：已读判定**不分入口**（图书馆 / 书房「读书」都认）——只看书槽放了什么。
	# 放在最前面，是因为这条规则与「能不能读」（属性/学识门槛）无关：读过的书就是读过了。
	var book_card0: CardData = _placed.get(BOOK_SLOT, null)
	if book_card0 != null:
		var b0: Dictionary = _load_books().get(_book_id_of(book_card0), {})
		if not b0.is_empty() and _already_read(b0):
			return "我已经看过这本书了。"
	if String(_trigger_id) != "图书馆":
		return ""
	var executor: CardData = _placed.get(EXECUTOR_SLOT, null)
	var book_card: CardData = _placed.get(BOOK_SLOT, null)
	if executor == null or book_card == null:
		return ""
	var book: Dictionary = _load_books().get(_book_id_of(book_card), {})
	if book.is_empty():
		# 学生证 = 入馆凭证（2026-10-25）：保留 display 那句「可以进去了 —— 只是手里还空着」，
		# 不要替换成「图书馆没有收录」——它不是书，是证件。
		if _is_student_pass(book_card):
			return ""
		return "这本《%s》图书馆没有收录。" % book_card.display_name
	if _condition_met(book, executor):
		return _resolve_book_text(String(book.get("before_read", "")), executor)
	return _resolve_book_text(_fail_text_for(book, executor), executor)


## 读书完整结算：返回 {condition_met, condition_text, before_read, read_description, effect}。
func _compute_read_book() -> Dictionary:
	var executor: CardData = _placed.get(EXECUTOR_SLOT, null)
	var book_card: CardData = _placed.get(BOOK_SLOT, null)
	if executor == null:
		return _fail("需要一名执行者。")
	if book_card == null:
		return _fail("需要一本书。")
	var book_id := _book_id_of(book_card)
	var book: Dictionary = _load_books().get(book_id, {})
	if book.is_empty():
		# 学生证（2026-10-25）：图书馆「凭证入馆」档就是为它开的 —— 让玩家进得去、
		# 拿到一句「还得自己去挑书」的方向，而不是「这本《学生证》读不了」。
		# 走 _fail → 父类即时结算（不占回合、不给属性），与「读不了」同一条路径。
		if _is_student_pass(book_card):
			return _fail("学生证只够进这道门，读什么还得去架子上挑一本。")
		return _fail("这本《%s》读不了。" % book_card.display_name)

	# 2026-10-25：一本书只算一次。判据 = after_read.player_tags 落下的「已读《X》」
	# （玩家级标记，见 _after_read_effect）。已有 → 不再给属性/词条，也不让点确定。
	if _already_read(book):
		return _fail("我已经看过这本书了。")

	if not _condition_met(book, executor):
		return _fail(_fail_text_for(book, executor))

	return {
		"condition_met": true,
		"before_read": _resolve_book_text(String(book.get("before_read", "")), executor),
		"read_description": _resolve_book_text(String(book.get("read_description", "")), executor),
		"effect": _after_read_effect(book, book_id),
	}


## 书卡 id → books.json 键（兼容 "book:X" 前缀）。
func _book_id_of(book_card: CardData) -> String:
	var id := String(book_card.id)
	if id.begins_with("book:"):
		return id.substr(5)
	return id


## 书槽里放的是不是「学生证」（2026-10-25 用户报障：图书馆不能用学生证看书）。
## 学生证带 tag「学生」、不带「书」，不给特例就会落到「非书」那条 lock_execute 档 ——
## 玩家被「如果来这里不是学习可是会被赶出去的」+ 灰掉的确定键卡住。
## 触发器「图书馆」为它单开了一档「凭证入馆」（any_slot.names=学生证，权重 40 > 非书 30）。
func _is_student_pass(card: CardData) -> bool:
	if card == null:
		return false
	return String(card.id) == "学生证" or String(card.display_name) == "学生证"


## 书条件判定：condition.forbid_executors 命中执行者 → 恒不可读（硬禁，压过 attrs/or_tags）；
## 否则 {} / 缺失 → 恒真；(attrs 全过) OR (任一 or_tags 命中)。
## attrs 用执行者「生效值」（与 compare 同口径）。
func _condition_met(book: Dictionary, executor: CardData) -> bool:
	var cond_v: Variant = book.get("condition", null)
	if not (cond_v is Dictionary):
		return true
	var cond: Dictionary = cond_v
	if cond.is_empty():
		return true

	# 硬禁：主角这类「设定上读不了」的执行者，即使后面满足属性/学识门槛也不放行。
	if _executor_forbidden(cond, executor):
		return false

	var attrs_ok := true
	var has_attrs := false
	var attrs_v: Variant = cond.get("attrs", null)
	if attrs_v is Dictionary and not (attrs_v as Dictionary).is_empty():
		has_attrs = true
		var eff: Dictionary = Player.effective_attrs_of(executor)
		for an in (attrs_v as Dictionary):
			var spec: Variant = (attrs_v as Dictionary)[an]
			if not (spec is Dictionary):
				continue
			var s: Dictionary = spec
			var lo := int(s.get("min", -2147483648))
			var hi := int(s.get("max", 2147483647))
			var val := int(eff.get(String(an), 0))
			if val < lo or val > hi:
				attrs_ok = false

	var tags_ok := true
	var has_tags := false
	var or_tags_v: Variant = cond.get("or_tags", null)
	if or_tags_v is Array and not (or_tags_v as Array).is_empty():
		has_tags = true
		tags_ok = _executor_has_any_tag(executor, or_tags_v)

	if has_attrs and has_tags:
		return attrs_ok or tags_ok
	if has_attrs:
		return attrs_ok
	if has_tags:
		return tags_ok
	return true


## 读不了时该说哪句：命中 condition.forbid_executors → forbid_text（该角色专属台词）；
## 否则退回 condition_text；两者都空才有通用兜底。
func _fail_text_for(book: Dictionary, executor: CardData) -> String:
	var cond_v: Variant = book.get("condition", null)
	if cond_v is Dictionary and _executor_forbidden(cond_v, executor):
		var ft := String((cond_v as Dictionary).get("forbid_text", ""))
		if ft != "":
			return _resolve_book_text(ft, executor)
	var ct := String(book.get("condition_text", ""))
	return _resolve_book_text(ct if ct != "" else "现在的你还读不懂这本书。", executor)


## 执行者是否被 condition.forbid_executors 点名（值 = 角色 id，如 "Hero"）。
## 与 `forbid_tags` 的区别：这里按 **id** 认人，不受执行者当前 tag 变化影响（硬禁）。
func _executor_forbidden(cond: Dictionary, executor: CardData) -> bool:
	if executor == null:
		return false
	var fv: Variant = cond.get("forbid_executors", null)
	if not (fv is Array) or (fv as Array).is_empty():
		return false
	var eid := String(executor.id)
	for i in (fv as Array):
		if String(i) == eid:
			return true
	return false


## 读书后效果 → slot_attrs / slot_tags / slot_enqueue_talk（作用于「执行者」槽的角色），
## 外加 **player_tags**（2026-10-16 犹格索托斯之所）：整户人家共享的「已读《X》」标记。
##
## 与 slot_tags 的分工：slot_tags 记「**谁**读的」（执行者自己的 tag），player_tags 记
## 「**这本书**读过了」（玩家级，书在谁手里读都算数）。书店闭店判定与调查书店的门控都认后者。
func _after_read_effect(book: Dictionary, book_id: String) -> Dictionary:
	var ar_v: Variant = book.get("after_read", null)
	if not (ar_v is Dictionary):
		return {}
	var ar: Dictionary = ar_v
	var effect: Dictionary = {}
	var attrs_v: Variant = ar.get("attrs", null)
	if attrs_v is Dictionary and not (attrs_v as Dictionary).is_empty():
		effect["slot_attrs"] = {EXECUTOR_SLOT: attrs_v}
	var tags_v: Variant = ar.get("tags", null)
	if tags_v is Array and not (tags_v as Array).is_empty():
		effect["slot_tags"] = {EXECUTOR_SLOT: tags_v}
	# player_tags：玩家级已读标记（books.json 的 after_read.player_tags）。
	var marks: Array = []
	var pt_v: Variant = ar.get("player_tags", null)
	if pt_v is Array and not (pt_v as Array).is_empty():
		marks = (pt_v as Array).duplicate()
	# 书架读尽：这次读完后再没有没读的书 → 附赠「书肆读尽」。
	# 判据由父类 `_books_all_read()` 从 books.json 派生，不在这里写死书单。
	if _books_all_read(book_id):
		marks.append(ALL_BOOKS_TAG)
	if not marks.is_empty():
		effect["tags"] = marks
	# 读完有话想说（周游线，2026-10-10）：after_read.enqueue_talk（{path,name}）→ 入队到
	# **读书人自己**的 talk_queue（effect 键 slot_enqueue_talk，值仍按槽位定位执行者）。
	# 书里不能写死读者是谁，故这里只做「键名转换」，落地口径交给 EffectProcessor（单一来源）。
	var enq_v: Variant = ar.get("enqueue_talk", null)
	if enq_v != null:
		effect["slot_enqueue_talk"] = {EXECUTOR_SLOT: enq_v}
	return effect


## 这本书是否已经被读过（2026-10-25）：判据 = books.json 的 after_read.player_tags
## （「已读《X》」，_after_read_effect 落在 player_tags）。是**玩家级**标记 —— 谁读的都算，
## 换个人再读也不会给第二遍属性。未配 player_tags 的书 → 恒 false（宁可允许多读，不误拦）。
func _already_read(book: Dictionary) -> bool:
	var ar_v: Variant = book.get("after_read", null)
	if not (ar_v is Dictionary):
		return false
	var marks: Variant = (ar_v as Dictionary).get("player_tags", null)
	if not (marks is Array) or (marks as Array).is_empty():
		return false
	return Player.player_has_tags(marks, 1)


## 已读的书不许再按确定：父类的 _is_execute_disabled 只认 display.lock_execute（静态数据），
## 这里补一层**动态**判定（放上书槽就锁，不需要先放执行者）。
func _is_execute_disabled(display: Dictionary) -> bool:
	if super._is_execute_disabled(display):
		return true
	if String(_expanded.get("resolver", "")) != "read_book":
		return false
	var book_card: CardData = _placed.get(BOOK_SLOT, null)
	if book_card == null:
		return false
	var book: Dictionary = _load_books().get(_book_id_of(book_card), {})
	if book.is_empty():
		return false
	return _already_read(book)


## 执行者（动态 tag）是否带任一 tag：Hero → player_tags；其余 → npc 条目 tags。
func _executor_has_any_tag(executor: CardData, tags: Array) -> bool:
	for t in tags:
		if _executor_has_tag(executor, String(t)):
			return true
	return false


func _executor_has_tag(executor: CardData, tag: String) -> bool:
	if executor.id == "Hero":
		return tag in Player.player_tags
	var npc_key := EffectProcessor._npc_key_of(executor)
	var entry: Dictionary = Player.npc.get(npc_key, {})
	var tags_v: Variant = entry.get("tags", [])
	return tag in (tags_v if tags_v is Array else [])


## 替换 {执行者} 占位符。
func _resolve_book_text(text: String, executor: CardData) -> String:
	if executor == null:
		return text
	return text.replace("{执行者}", executor.display_name)


func _fail(text: String) -> Dictionary:
	return {
		"condition_met": false,
		"condition_text": text,
		"before_read": "",
		"read_description": "",
		"effect": {},
	}
