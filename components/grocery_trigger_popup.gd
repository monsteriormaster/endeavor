## 神秘杂货店触发器弹窗 —— 继承 TriggerPopup（D-DOC23，2026-09-10；D-DOC24 回合级改造，2026-09-13）。
##
## resolver「grocery」+ 立即执行（trigger 不写 duration → 0 → 父类走 _resolve_special 即时路径）。
## **init_scope = "turn"（D-DOC24）**：货架内容在**回合边界**由 TriggerManager.advance_turn 生成，
## 本回合内固定不变（多次打开看到同一套三件货）；弹窗只读实例，不再现场随机。
## 结构（商业街.doc 神秘杂货店）：
##   - 货一~货三（第1行）：读回合实例上架（声明 auto_attract {class:["good"], exclude_sold:true}，
##     商品池 resoures/items/goods.json，price 字段记售价）。被买走的商品记入
##     Player.trigger_consumed["神秘杂货店"]（**仅本回合**：本回合再开该槽保持空位，池不足就空着；
##     过天由 TriggerManager.advance_turn 清空回池 + 重建实例，重新抽三件）。
##   - 货四~货六（第2行）：放**任意人物卡** = 购买对应 货一/货二/货三（配对 4→1、5→2、6→3）。
##     结算：金钱-对应价格、获得对应物品（stuff + 手牌卡）、商品记入 trigger_consumed（下架）。
##     钱不够 → 该对不成交（无文案，不写失败情景口径）。
##   - 阶段2（清单交换）：Player.player_stuff 持有「越狱工具清单」**或** 清单卡放入右侧槽
##     （按物品 tag 识别）→「交易愉快」：失去清单、获得越狱工具、金钱-5。
##     放入的清单卡在交换时消耗（不回流手牌）；stuff 轨道触发时同步移除手牌清单卡。
##   - 右侧槽：accept=item。清单交换走这里；其余物品按 tag 加分支为后续扩展。
##   - 成交的货槽当场清空；由于该商品已进「已消耗」表，本回合重开该槽保持空位（基类实例路径
##     自动过滤，无需子类钩子）。配对购买槽再放人 → 右栏「该商品已售罄」+ 禁执行。
##     口径（2026-09-13 用户拍板）：**不能购买没有的物品，能购买还有的物品**——混合场景仍可执行，
##     只买有货的那对；已放购买槽**全部**无货才禁「确定」。
##   - 确认态：执行完成后正文整体替换为结算文本、槽位锁定、底栏只留「确定」（点它关闭）。
## 文案纪律（2026-09-10 用户要求）：只使用 doc 给定文案——「物美价廉，童叟无欺。」/
## 「交易愉快。」/「该商品已售罄」；不擅自添加任何文字。
## 其余（卡槽装配/吸附/display 选择/流程字典）全部复用父类能力。
class_name GroceryTriggerPopup
extends TriggerPopup

## 购买槽 → 货槽配对（货四买货一，以此类推）。
const BUY_PAIRS := {"货四": "货一", "货五": "货二", "货六": "货三"}
## 商品槽（吸附来的库存卡，不属于玩家手牌，关闭时不归还）。
const GOODS_SLOTS: Array[String] = ["货一", "货二", "货三"]
const SOLD_OUT_TEXT := "该商品已售罄"
const SPECIAL_SLOT := "右侧"
const LIST_ITEM := "越狱工具清单"
const TOOL_ITEM := "越狱工具"

## 确认态（2026-09-10 用户需求）：执行完成后 true——正文=结算文本、槽位锁定、
## 底栏只留「确定」，点确定关闭弹窗；期间 _refresh 一律忽略。
##
## 注（D-DOC24）：原「本店已售罄货位」会话表 `_sold_slots` 与 `_slot_attract_locked` override 已删除——
## 该触发器改为回合级后，货槽走**回合实例**读取，被买走的商品进 Player.trigger_consumed，
## 基类实例路径自动跳过（保持空位），跨打开/跨读档一致（旧实现在同一次打开内才有效）。
var _confirming := false


## 即时结算入口（父类 _resolve_special 的 default 分支钩子）。
func _resolve_custom(resolver: String, _display: Dictionary) -> bool:
	if resolver != "grocery":
		return false
	_resolve_grocery()
	return true


## 完整结算：配对购买 + 阶段2 清单交换。文案只含 doc 给定三句（见类头文案纪律）。
func _resolve_grocery() -> void:
	var lines: Array[String] = []
	var effect: Dictionary = {}
	var bought_cards: Array[CardData] = []
	var bought_ids: Array = []
	var sold_out_buys := 0
	var spent := 0

	# —— 阶段1 分支A：货四~六 有人物卡 → 逐对购买 ——
	for buy_slot in BUY_PAIRS:
		var goods_slot: String = String(BUY_PAIRS[buy_slot])
		var buyer: CardData = _placed.get(String(buy_slot), null)
		if buyer == null:
			continue
		var goods: CardData = _placed.get(goods_slot, null)
		if goods == null:
			sold_out_buys += 1
			continue
		var price := int(goods.price)
		if Player.player_money - spent < price:
			continue  # 钱不够 = 该对不成交，无文案（不写失败情景口径）
		spent += price
		bought_cards.append(goods)
		bought_ids.append(goods.id)
		# 成交即下架：商品进「本回合已消耗」表（D-DOC24）+ 清空货槽（_placed 移除 + 静默清 UI，
		# 不触发 _refresh）。货位本回合剩余时间保持空位——基类读回合实例时会跳过已消耗卡，
		# 配对购买槽再放人 → 「已售罄」+ 禁执行。
		_placed.erase(goods_slot)
		for s in _slots:
			if s.slot_name == goods_slot and s.get_card() != null:
				s.set_card(null)

	# —— 阶段2：清单交换（买了货之后继续，或没买货直接交换）——
	# 触发口径（2026-09-10 用户修正）：stuff 持有清单 **或** 清单卡放入右侧槽（按物品 tag 识别）。
	var right_card: CardData = _placed.get(SPECIAL_SLOT, null)
	var list_placed: bool = right_card != null and right_card.has_tags([LIST_ITEM], 1)
	var has_list: bool = Player.player_stuff.has(LIST_ITEM) or list_placed
	if not bought_ids.is_empty():
		lines.append("物美价廉，童叟无欺。")
	if has_list:
		lines.append("交易愉快。")
	if sold_out_buys > 0:
		lines.append(SOLD_OUT_TEXT)

	# 注意：**一次性构造** effect，不走 _merge_effect —— 共享版对 money 是覆盖不是累加，
	# 会把购买扣款覆盖成 -5（D-DOC23 测试抓到过）。
	if bought_ids.is_empty() and not has_list:
		effect = {}
	else:
		var stuff_ids: Array = bought_ids.duplicate()
		if has_list:
			stuff_ids.append(TOOL_ITEM)
		effect = {"money": -(spent + (5 if has_list else 0))}
		if not bought_ids.is_empty():
			# 本回合已消耗（D-DOC24）：{触发id: [卡id]} —— 基类读回合实例时据此保持货槽空位
			# （旧键 goods_sold 已由通用键取代，2026-09-13）。
			effect["trigger_consumed"] = {_trigger_id: bought_ids.duplicate()}
		if not stuff_ids.is_empty():
			effect["stuff"] = stuff_ids
		if has_list:
			effect["remove_stuff"] = [LIST_ITEM]

	# —— 落地：effect → 购得商品卡/越狱工具卡进手牌 → 清单卡两轨清理 → 确认态 ——
	if not effect.is_empty():
		TriggerManager.apply_effect(effect, _placed)
	for g in bought_cards:
		book_acquired.emit(g)
	if has_list:
		var tool_card: CardData = CardRegistry.get_card(TOOL_ITEM)
		if tool_card != null:
			book_acquired.emit(tool_card)
		if list_placed:
			# 放入的清单卡 = 交换时消耗：移出 _placed + 静默清槽 UI，关闭时不回流手牌
			_placed.erase(SPECIAL_SLOT)
			for s in _slots:
				if s.slot_name == SPECIAL_SLOT and s.get_card() != null:
					s.set_card(null)
		else:
			# 清单卡还在手牌（stuff 轨道触发）：同步移除，避免「stuff 已失去、卡还在手」
			_remove_hand_card_by_id(LIST_ITEM)
	# 确认态（2026-09-10 用户需求）：正文整体替换为结算文本，右下角唯一可点按钮变「确定」
	_enter_confirm_state("\n".join(lines))
	_finish_flow()


## 确认态：执行完成后正文变化（整体替换为结算文本）、锁定全部卡槽、
## 底栏只留右下角「确定」（执行/取消隐藏），点确定 = 关闭弹窗（卡照常归还）。
func _enter_confirm_state(result_text: String) -> void:
	_confirming = true
	if result_text != "":
		text_label.text = result_text
	for s in _slots:
		s.set_interactive(false)
	execute_btn.visible = false
	cancel_btn.visible = false
	close_btn.text = "确定"


## 确认态下禁止任何刷新（槽位已锁定不会触发；防御 plot/外部路径调用覆盖结算文本）。
func _refresh() -> void:
	if _confirming:
		return
	super._refresh()


## 按物品 id 从手牌区移除一张卡（stuff 轨道交换后同步手牌轨道）。
func _remove_hand_card_by_id(item_id: String) -> void:
	var ca: CardArea = TriggerManager.get_card_area()
	if ca == null:
		# D-HAND1：视图不在场就改账本本身，否则这类消耗不会跨场景生效。
		Player.remove_hand_card(item_id)
		return
	for c in ca.get_cards():
		if c != null and c.id == item_id:
			ca.remove_card(c)   # 内部同步摘账本
			return


## 关闭归还卡牌：商品槽的货卡是**商店库存**（注册表单例吸附来的），不归还手牌；
## 已购的货卡已经由 book_acquired 进过手牌，同样跳过。其余（购买用人物卡、右侧槽物品卡）照常归还。
func _return_cards() -> void:
	var saved := {}
	for gs in GOODS_SLOTS:
		if _placed.has(gs):
			saved[gs] = _placed[gs]
			_placed.erase(gs)
	super._return_cards()


## 配对货槽为空的已放购买槽列表（货被买走/无货 → 该对不可购买）。
func _sold_out_buy_slots(_display: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for buy_slot in BUY_PAIRS:
		if not _placed.has(String(buy_slot)) or _placed[String(buy_slot)] == null:
			continue
		if _placed.get(String(BUY_PAIRS[buy_slot]), null) == null:
			out.append(String(buy_slot))
	return out


## 右栏动态文案：已放人物对应的货位空了 → 「该商品已售罄」（整体替换迎客文案，
## 与父类 _derive_dynamic_text 的「放卡后整体替换」模型一致）。
func _derive_dynamic_text(display: Dictionary) -> String:
	var sold := _sold_out_buy_slots(display)
	if sold.is_empty():
		return ""
	var lines: Array[String] = []
	for _bs in sold:
		lines.append(SOLD_OUT_TEXT)
	return "\n".join(lines)


## 执行按钮：已放购买槽**全部**配对空货（例：只放了货四的人而货一已售罄）→ 禁止执行。
## 混合场景（一对售罄、另一对有货）仍可执行，只买有货的那对，售罄对由结算文本提示。
func _is_execute_disabled(display: Dictionary) -> bool:
	if super._is_execute_disabled(display):
		return true
	var placed_buys := 0
	var sold_out := 0
	for buy_slot in BUY_PAIRS:
		if not _placed.has(String(buy_slot)) or _placed[String(buy_slot)] == null:
			continue
		placed_buys += 1
		if _placed.get(String(BUY_PAIRS[buy_slot]), null) == null:
			sold_out += 1
	return placed_buys > 0 and sold_out == placed_buys
