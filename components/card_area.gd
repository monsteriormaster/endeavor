## 卡牌区组件 —— 玩家的"手牌"区：展示一组已获卡牌，作为拖拽来源；
## 同时是放置目标（从卡槽把卡拖回时归还）。
## 规则：默认每张卡只能出现一次；带 "可堆叠" tag 的卡可重复添加。
## 点击卡牌发出 card_clicked(card) 信号；取回卡牌发出 cards_returned。
## 本组件只管展示+规则，不含详情弹窗、不含获取来源（由上层喂数据）。
##
## 本次扩展（卡牌槽优化）：
##   - 手牌内拖动重排（拖动来源为自身时按落点插入，不丢卡不重复）。
##   - 「整理」排序（tidy_hand）：手牌始终从左到右有序；大类(人物→道具) + 道具子类(武器/防具/饰品/书/其他)
##     + 品质档(level，SSR>SR>S>R，无=0 排最后)；人物卡按上下文 priority_attrs 数值区间档(1-3/4-6/7-9/10)
##     高→低，属性主次按声明顺序；同档/同序用原始相对位置保持稳定（"原本靠左的仍靠左"）。
##   - 提示态（begin_hint/end_hint）：把可选卡按排序聚到最左并上移，首卡金边高亮；双击空槽入首卡、
##     点槽/卡牌区/卡以外还原。
## 节点树（卡牌游戏手牌布局）：CardArea 为 Control；
##   - 底栏**已透明化**（2026-10-08 用户要求）：原先「纸底 + 2px 铜描边 + 顶部内阴影」的极简托盘
##     —— TrayPaper(paper_tile 平铺) / ShelfEdge(2px 铜框) / InnerTop(顶缘内阴影) —— **三个节点全部删除**，
##     卡牌直接浮在场景地图之上，不再有米黄纸面遮挡背景。CardArea 本体不自绘任何背景 → 透明即来源于此。
##     （历史：2026-09-26 曾删掉九宫格雕花铜框 frame_strip_ink.png 与 RailPaper/RailEdge 改成纸底托盘；本次连纸底一并去掉。）
##     ⚠️ paper_tile 的 ext_resource 与 G_inner/T_inner/SB_edge 子资源也一并移除，别再往这里加回纸面。
##   - 两条 2px 铜色细分割线（RailRule / DockRule，铜色 Alpha 0.325）把底栏切成「筛选栏 | 卡位 | 泊位」三段：
##     RailRule 在 x 102~104，DockRule 在 x 1638~1640。右侧 240px 泊位留给 main_ui 的「下一天」主操作
##     （按钮 1692~1868，与货架垂直居中）——这样底部右侧不再是孤零零浮着的元素。
##   - Scroll 直接子 HBox（Godot4.7 不容许中间节点，只能单层级）；HBox alignment=0 左对齐、separation=18 舒展、
##     custom_minimum_size.y=195（= 卡片 159 + 提示态上移净空 36）。横向滚动为主方案：
##     horizontal_scroll_mode=1（AUTO：卡少时不显示拖动条）、vertical_scroll_mode=0（禁竖向）；
##     clip_contents=true 使卡牌滚动不越出底栏货架（卡牌滑动不超过该范围）。
##     Scroll 左缘 120（避让 104px 筛选栏）/右缘 -264（避让 240px 泊位）→ 卡位约 1496px，可容 13 张。
##   - 底部拖动条 = ScrollContainer 内置 HScrollBar（经 TH_scroll 主题美化：半透明深铜轨道 + 铜金圆角抓柄、去箭头）。
##   - 卡片 size_flags_vertical=SHRINK_END → 贴 HBox 底部并保持 159 高，顶部腾出 36px 供提示态上移（仍在裁切区内可见）。
##     实测落位：卡片 y 39~198（货架高 238），上下留白 39 / 40，视觉居中。
##   - 整理按钮与 5 个筛选按钮（全部/人物/装备/书/其他，toggle 单选互斥）竖排于左侧筛选栏
##     （x 10~94，28px 高，y 18~220，上下留白 18）；样式来自 CardArea 根上的 TH_card 本地主题
##     （羊皮纸底 + 铜描边；pressed=铜底浅字）。
class_name CardArea
extends Control

## 点击卡牌时发出（参数：被点的卡）。
signal card_clicked(card: CardData)
## 卡牌区内容变化时发出（增/删/清空/排序/重排）。
signal changed
## 添加被拒时发出（参数：卡、原因）。
signal card_rejected(card: CardData, reason: String)
## 从卡槽取回卡牌时发出（参数：归还的卡）。
signal cards_returned(card: CardData)
## 提示态首卡变化（高亮目标，参数：首卡或 null）。
signal hint_best_changed(card: CardData)

## 「可重复持有」判据不再在本文件另写一份字面量 —— 统一走 `CardData.is_stackable()`
## （D-HAND1：CardArea 唯一性 与 Player.hand 账本去重必须同口径，否则两边会长短不齐）。
const CHIP_SCENE := preload("res://components/card_chip.tscn")

## 手牌上移基准（提示态，非首卡）。
const HINT_LIFT := 18.0
## 首卡额外上移（提示态，在 HINT_LIFT 之上再上移）。
const HINT_BEST_EXTRA := 18.0
## 首卡放大（提示态高亮）。
const HINT_BEST_SCALE := 1.06

## HBox 为 Scroll 直接子（单层级）；Scroll 开启裁切（clip_contents=true）使卡牌滑动不越出底栏货架；
## 卡片 size_flags_vertical=SHRINK_END 贴 HBox 底部，HBox 高 195 预留顶部 36px 净空，容纳提示态上移
## （首卡 36px + 1.06 放大），不被裁切。横向滚动为主方案：horizontal_scroll_mode=1（AUTO）。
@onready var hbox: HBoxContainer = $Scroll/HBox
## 整理按钮（筛选栏最上，x 10~94 / y 18~46，由 card_area.tscn 提供）。
@onready var tidy_btn: Button = $整理Button
## 5 个筛选按钮（整理下方）：全部/人物/装备/书/其他，toggle 单选互斥。
@onready var filter_all: Button = $FilterAll
@onready var filter_char: Button = $FilterChar
@onready var filter_equip: Button = $FilterEquip
@onready var filter_book: Button = $FilterBook
@onready var filter_other: Button = $FilterOther

## 筛选按钮 → 类别键 映射（_ready 中填充，@onready 变量在 const 初始化时尚不可用）。
var _filter_buttons: Dictionary = {}
## 当前筛选类别："all"=全部；"character"/"equip"/"book"/"other"。仅影响 chip.visible，
## 不动底层 _cards / 顺序 / hint 逻辑。
var _current_filter: String = "all"

## 当前卡牌区所有卡牌 id（含堆叠重复；卡无 id 时用 display_name 当 id）。
var _card_ids: Array[String] = []
## 当前卡牌区所有卡牌实例（与 _card_ids 一一对应）。
var _cards: Array[CardData] = []
## D-HAND1：批量恢复期间（restore_from）暂停「自动整理」与账本回写，结束后统一写一次。
var _restoring := false

## 视图是否**已作废**（读档时由 `SaveLoader` 打上，见 `mark_stale()`）。
## 作废的视图在离场时**绝不许**把自己的 `_cards` 写回账本。
var _stale := false
## 本视图出生时的手牌账本世代（`Player.hand_gen`）。离场时若世代已变 = 账本被读档整个换过，
## 手里这份是上一局的快照 → 不写回（与 `_stale` 互为双保险，见 player.gd 的 hand_gen 说明）。
var _born_hand_gen := -1

## 整理/提示态的人物卡数值排序属性上下文（声明序；空=只按原始序）。
var _priority_attrs: Array = []

## 提示态：当前激活的空槽与其上下文。
var _hint_active: bool = false
var _hint_slot: CardSlot = null
## 提示态开始前的手牌顺序快照（CardData 数组，用于还原）。
var _hint_snapshot: Array[CardData] = []
## 提示态首卡（高亮 + 双击入槽目标）。
var _hint_best: CardData = null
## 提示态中被上移的 chip 列表（用于还原 position/scale/高亮）。
var _hint_lifted: Array[CardChip] = []
## 提示态上移前各 chip 的原始 y（精确还原，避免被 HBox 重新布局影响）。
var _hint_orig_y: Dictionary = {}


# ============================================================
#  整理排序（稳定：原始相对位置作 tiebreaker）
# ============================================================

## 比较器（纯函数，便于无头测试）：a/b = {card, idx}。
## 返回 true 表示 a 应排在 b 前。
## 大类：人物(0) < 道具(1)。道具内按 category_minor(武器1/防具2/饰品3/书4/其他5) + level_rank 高→低。
## 人物内：按 priority_attrs 各属性区间档(attr_tier) 高→低（声明序=主次），同档保持原序。
static func compare_for_sort(a: Dictionary, b: Dictionary, priority_attrs: Array) -> bool:
	var ca: CardData = a["card"]
	var cb: CardData = b["card"]
	var ra := _major(ca)
	var rb := _major(cb)
	if ra != rb:
		return ra < rb
	if ra == 0:
		# 人物卡：按上下文数值档
		for attr in priority_attrs:
			var an: String = String(attr)
			var ta := CardData.attr_tier(int(ca.attrs.get(an, 0)))
			var tb := CardData.attr_tier(int(cb.attrs.get(an, 0)))
			if ta != tb:
				return ta > tb  # 高→低
		return a["idx"] < b["idx"]
	# 道具卡：子类 + 品质
	var ma := ca.category_minor()
	var mb := cb.category_minor()
	if ma != mb:
		return ma < mb
	var la := ca.level_rank()
	var lb := cb.level_rank()
	if la != lb:
		return la > lb  # 高→低
	return a["idx"] < b["idx"]


## 大类序号：人物=0，道具=1。
static func _major(card: CardData) -> int:
	return 0 if card.card_type == "character" else 1


## 按「整理」规则重排手牌（持久；亦供新增卡自动归位）。priority_attrs 为人物卡数值排序所需的属性名（按声明顺序），
## 无触发器上下文时传空数组（人物卡只按原始序）。
func tidy_hand(priority_attrs: Array = []) -> void:
	if _cards.size() <= 1:
		return
	_priority_attrs = priority_attrs
	var paired: Array[Dictionary] = []
	for i in _cards.size():
		paired.append({"card": _cards[i], "idx": i})
	paired.sort_custom(Callable.create(self, "_cmp_wrapper"))
	_apply_order(paired)


## sort_custom 的包装（Godot 比较器签名为 (a, b) -> bool，priority_attrs 走实例变量）。
func _cmp_wrapper(a: Dictionary, b: Dictionary) -> bool:
	return compare_for_sort(a, b, _priority_attrs)


## 按 paired 顺序重排内部数组与 HBox 节点（不增删）。
func _apply_order(paired: Array) -> void:
	_cards.clear()
	_card_ids.clear()
	for p in paired:
		var c: CardData = p["card"]
		_cards.append(c)
		_card_ids.append(_card_id_of(c))
	for i in _cards.size():
		var chip := _chip_of(_cards[i])
		if chip != null:
			hbox.move_child(chip, i)
	_sync_hand()   # D-HAND1：整理产生的顺序也是玩家手牌顺序，要进账本
func _apply_order_from_list(order: Array) -> void:
	_cards.clear()
	_card_ids.clear()
	for c in order:
		if c == null:
			continue
		_cards.append(c)
		_card_ids.append(_card_id_of(c))
	for i in _cards.size():
		var chip := _chip_of(_cards[i])
		if chip != null:
			hbox.move_child(chip, i)


## 当前 HBox 内所有 CardChip（按当前显示顺序）。
func _chips_in_order() -> Array[CardChip]:
	var out: Array[CardChip] = []
	for ch in hbox.get_children():
		if ch is CardChip:
			out.append(ch as CardChip)
	return out


## 找到表示某卡实例的 chip（一 chip 一实例）。
func _chip_of(card: CardData) -> CardChip:
	for ch in hbox.get_children():
		var chip := ch as CardChip
		if chip != null and chip.card == card:
			return chip
	return null


# ============================================================
#  手牌账本同步（D-HAND1，2026-10-14）
# ============================================================

## 把当前手牌（含顺序）写回 `Player.hand` 持久账本。
##
## 本组件是场景内节点、切场景就被销毁；账本才是「玩家手上有什么」的真值。凡是手牌**集合**
## 或**顺序**发生变化都必须同步一次，否则那次改动会随场景一起蒸发。
## ⚠️ 提示态（hint）的聚拢排序**不入账** —— 那只是「可选卡往左站」的一次临时可视化，
##    松手会还原（`end_hint` 把顺序改回快照），把中间态写进账本等于把一次性动画存成了档案。
func _sync_hand() -> void:
	if _hint_active or _restoring:
		return
	Player.set_hand_from(_cards)


## 按持久账本重建整区（场景就绪后由 `main_ui._restore_hand()` 调用）。
##
## ⚠️ 为什么账本里有重复也得兼容：上一版曾按「按进度重放」补卡，老档迁移出来可能带脏重复项。
##    这里静默跳过（不 `add_card`），否则每进一次场景就会为同一张卡播一串「被拒」音效。
## ⚠️ 为什么不自动整理：整理会把新卡按默认规则插到它该在的位置。恢复时如果每张都整理，
##    玩家上一次手动拖出来的顺序就被抹平成默认序了 —— 账本存的顺序也就失去意义。
func restore_from(cards: Array) -> void:
	_restoring = true
	for c in cards:
		if not (c is CardData):
			continue
		var cd := c as CardData
		var cid := _card_id_of(cd)
		if _card_ids.has(cid) and not cd.is_stackable():
			continue
		add_card(cd)
	_restoring = false
	_sync_hand()


## 按数据源重解引用手牌里的**角色卡**：按 id 从 `Player.npc`（主角走 `Player`）重建实例，
## 替换 `_cards` 里的旧实例，并让对应 `CardChip` 换卡重绘。
##
## 🔴 为什么需要（2026-10-16 用户拍板的「方案 B」）：卡实例是「进手牌那一刻的快照」
##    （`CardData.from_character` 逐项拷贝 tags/attrs），触发器结算写入 `Player.npc`
##    （如护卫「受伤」）后，手牌里那张旧实例的 tags 不会跟着变 —— 而卡槽 `forbid_tags`
##    判的正是这张旧实例。统一在「打开触发器弹窗」时从 `Player.npc` 重建一遍，判定就只认
##    `Player.npc` 一份真值，卡面与条目不再各说各话。
##
## ⚠️ 只重建「能查到实时源」的角色卡，其余**保持原实例**：
##    · 道具卡一律不刷 —— `CardRegistry.get_card` 返回**共享静态实例**，换成它会污染注册表；
##    · 书卡 / 不在 `Player.npc` 里的角色卡：`live_card_for_id` 拿不到就跳过（快照兜底）。
## 批量换实例期间置 `_restoring`（不自动整理、不回写账本），收尾统一 `_sync_hand()` 一次。
## 返回 true=至少换掉了一张。
func refresh_from_source() -> bool:
	if _cards.is_empty():
		return false
	var replaced := false
	_restoring = true
	for i in _cards.size():
		var old := _cards[i]
		if old == null or old.card_type != "character":
			continue
		var fresh: CardData = EffectProcessor.live_card_for_id(_card_id_of(old))
		if fresh == null or fresh == old:
			continue
		_cards[i] = fresh
		_card_ids[i] = _card_id_of(fresh)
		var chip := _chip_of(old)
		if chip != null:
			# set_card 内部重绘卡面（含「有话可说」等实时字段）；origin/drop_target 不受影响。
			chip.set_card(fresh)
		replaced = true
	_restoring = false
	if replaced:
		_apply_filter()
		_sync_hand()
		changed.emit()
	return replaced


# ============================================================
#  公共 API
# ============================================================

## 添加一张卡（生成可拖 CardChip，origin/drop_target 指向本卡牌区）。
## 返回 true=接受，false=拒绝（已存在且不可堆叠）。
func add_card(card: CardData) -> bool:
	if card == null:
		return false
	var cid := _card_id_of(card)
	if _card_ids.has(cid) and not card.is_stackable():
		var reason := "已存在且不可堆叠：%s" % card.display_name
		push_warning("[CardArea] 拒绝添加：" + reason)
		# 被拒音（设计圣经 §3.6 `ui_card_reject`：闷响、**无金属**，像卡被挡住）
		AudioManager.play_sfx("ui_card_reject")
		card_rejected.emit(card, reason)
		return false
	var to_add: CardData = card
	if _card_ids.has(cid):
		for existing in _cards:
			if existing == card:
				to_add = card.duplicate() as CardData
				break
	_card_ids.append(cid)
	_cards.append(to_add)
	var chip := _make_card_node(to_add)
	hbox.add_child(chip)
	# 自动整理：新卡按「整理」规则插入正确位置，手牌始终保持从左到右有序；
	# 提示态进行中不重排（避免打断可选卡聚到最左的布局），仅刷新显隐。
	# D-HAND1：批量恢复期间同样不重排 —— 那时顺序由账本说了算。
	if not _hint_active and not _restoring:
		tidy_hand(_priority_attrs)
	_apply_filter()
	changed.emit()
	_sync_hand()
	return true


## 批量添加（用于归还多张已用卡）。
func add_cards(cards: Array[CardData]) -> void:
	for c in cards:
		add_card(c)


## 从卡牌区移除一张卡（被拖入卡槽时调用）。返回 true=移除成功。
func remove_card(card: CardData) -> bool:
	if card == null:
		return false
	var idx := -1
	for i in _cards.size():
		if _cards[i] == card:
			idx = i
			break
	if idx < 0:
		return false
	_card_ids.remove_at(idx)
	_cards.remove_at(idx)
	for ch in hbox.get_children():
		var chip := ch as CardChip
		if chip != null and chip.card == card:
			chip.queue_free()
			break
	_apply_filter()
	changed.emit()
	_sync_hand()
	return true


## 清空卡牌区（手牌账本同步为空）。
func clear() -> void:
	_card_ids.clear()
	_cards.clear()
	for c in hbox.get_children():
		c.queue_free()
	changed.emit()
	_sync_hand()


## 当前卡牌数（含堆叠）。
func count() -> int:
	return _cards.size()


## 当前卡牌区所有 id（含堆叠重复）的副本。
func get_card_ids() -> Array[String]:
	return _card_ids.duplicate()


## 当前卡牌区所有卡牌（含堆叠）的副本。
func get_cards() -> Array[CardData]:
	return _cards.duplicate()


## 取某卡在手牌中的显示序号（-1=不在）。
func index_of(card: CardData) -> int:
	return _cards.find(card)


## 屏幕坐标 `global_pos` 处的手牌卡（不在任何一张上 → null）。
##
## 谁在用：`OverlayRoot.close_with_click_through()` —— 面板被「点外收起」时，若那一下正好
## 落在某张卡上，就把点击转给它，一次点击完成「换面板」。
##
## ⚠️ 必须先按 `Scroll` 的可视矩形裁一次：`get_global_rect()` 是 chip 的**完整**矩形，
##    横向滚出可视区的卡它照样有坐标（只是被 `clip_contents` 挡掉了），不裁就会命中一张
##    玩家根本看不见的卡。同理跳过 `visible=false`（被筛选按钮藏掉的）。
func chip_at(global_pos: Vector2) -> CardChip:
	if not is_visible_in_tree():
		return null
	var view := $Scroll as Control
	if view == null or not view.get_global_rect().has_point(global_pos):
		return null
	for chip in _chips_in_order():
		if chip.card == null or not chip.visible:
			continue
		if chip.get_global_rect().has_point(global_pos):
			return chip
	return null


# ============================================================
#  放置目标（从卡槽取回卡牌 / 手牌内重排）
# ============================================================

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not data.has("card"):
		return false
	if not (data["card"] is CardData):
		return false
	# 🔴 引擎注入卡（auto_fill / auto_attract / 回合实例货）**不允许拖回手牌** —— 它们不是玩家的卡。
	#    判据 = 来源槽的溯源标记 `_from_hand`（玩家从手牌拖进去的才是 true）。
	#    没有这道闸，玩家可以把神秘杂货店货架空着拖一张货卡进手牌白嫖（2026-10-23 修）。
	var origin: Variant = data.get("origin", null)
	if origin is CardSlot and origin.has_method("did_come_from_hand") and not origin.did_come_from_hand():
		return false
	return true


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary) or not data.has("card"):
		return
	var c: CardData = data["card"]
	if not (c is CardData):
		return
	var origin: Variant = data.get("origin", null)
	# 与 _can_drop_data 同一道闸（兜底）：引擎注入卡不许进手牌。
	if origin is CardSlot and origin.has_method("did_come_from_hand") and not origin.did_come_from_hand():
		return
	# 来源是卡槽 → 先清空那个卡槽（return_to_hand=false，不自行归还），再由下方 add_card 归还到手牌。
	if origin is CardSlot and origin.has_method("clear_card"):
		origin.clear_card(false)
		add_card(c)
		cards_returned.emit(c)
		return
	# 来源是手牌区自身 → 先看是不是「装备卡落到人物卡上」（装备/替换），否则手牌内拖动重排。
	if origin is CardArea and origin == self:
		if _try_equip_at_drop(c):
			return
		_reorder_to(c, _drop_index_at(c))
		return
	add_card(c)


## 计算落点插入位：找 HBox 中第一个中心 x 超过落点全局 x 的 chip（排除被拖卡）之前。
func _drop_index_at(dragged: CardData) -> int:
	var gp := get_global_mouse_position()
	var idx := 0
	for ch in hbox.get_children():
		var chip := ch as CardChip
		if chip == null or chip.card == dragged:
			continue
		var cx := chip.global_position.x + chip.size.x / 2.0
		if gp.x > cx:
			idx += 1
		else:
			break
	return idx


## 把手牌中某卡移动到目标显示位（其余相对顺序不变）。
func _reorder_to(card: CardData, target_idx: int) -> void:
	var cur := _cards.find(card)
	if cur < 0:
		return
	if target_idx < 0:
		target_idx = 0
	if target_idx > _cards.size():
		target_idx = _cards.size()
	if cur == target_idx:
		return
	_card_ids.remove_at(cur)
	_cards.remove_at(cur)
	# 移除后索引平移：若目标在原位置之后，需 -1
	var ins := target_idx if target_idx <= cur else target_idx - 1
	ins = clampi(ins, 0, _cards.size())
	_card_ids.insert(ins, _card_id_of(card))
	_cards.insert(ins, card)
	var chip := _chip_of(card)
	if chip != null:
		hbox.move_child(chip, ins)
	changed.emit()
	_sync_hand()   # D-HAND1：玩家手动拖出的顺序要跨场景保留


# ============================================================
#  装备（拖装备卡到人物卡上 → 添加 / 替换，2026-10-24）
# ============================================================

## 拖拽落点压在一张**人物卡**上、且被拖的是装备卡 → 装给那个角色（同类替换）。
## 返回 true = 已消费这次放置（调用方不再走「手牌重排」）。
##
## 🔴 为什么落点做在手牌区：人物面板是 modal（`exclusive:false` + `outside_click_closes`），
##    开着时按住手牌会被 OverlayRoot 的拦截层判成「点面板外」→ 面板先收起来，
##    卡根本拖不进面板上的装备槽。而手牌里每张人物卡本来就是那个人，往它身上一放最顺手。
##
## 规则：
##   · 被拖的卡必须是装备（`card_class` 命中 weapon/armor/jewelry）；
##   · 目标必须是人物卡，且不是这张卡自己；
##   · 同一槽已有装备 → **替换**，旧装备回手牌（不销毁：还能装给别人）；
##   · 这一槽本来就是这件 → 交回重排逻辑（免得手牌里那张被凭空吞掉）。
## `at` = 落点（屏幕坐标）。生产路径传 null（= 当前鼠标位置），探针传坐标以便无鼠标验证。
func _try_equip_at_drop(item: CardData, at: Variant = null) -> bool:
	if Player.equip_slot_of(item) == "":
		return false
	var gp := get_global_mouse_position()
	if at is Vector2:
		gp = at
	var target := chip_at(gp)
	if target == null or target.card == null:
		return false
	if target.card.card_type != "character" or target.card == item:
		return false
	var owner_key := EffectProcessor._npc_key_of(target.card)
	var res: Dictionary = Player.equip_card(owner_key, item)
	if not bool(res.get("ok", false)):
		return false
	# 装备卡离开手牌（它现在挂在角色身上，不再是一张手牌）。
	remove_card(item)
	var replaced := String(res.get("replaced", ""))
	if replaced != "":
		var old_card := _item_card_by_name(replaced)
		if old_card != null:
			add_card(old_card)   # 被换下来的装备回手牌
	AudioManager.play_sfx("ui_card_place_ok")
	return true


## 按物品名取一张道具卡：优先注册表；注册表里没有（剧情临时授予的装备）就用
## TagRegistry 的 items 缓存现造一张 —— 否则「换下来的旧装备」会凭空蒸发。
func _item_card_by_name(item_name: String) -> CardData:
	var card: CardData = CardRegistry.get_card(item_name)
	if card != null:
		return card
	var d: Dictionary = TagRegistry.get_equipment(item_name)
	if d.is_empty():
		push_warning("[CardArea] 找不到物品「%s」，无法回手牌" % item_name)
		return null
	return CardData.from_item(item_name, d)


## 拖拽落点提示：拖着装备卡移动时，鼠标下那张**人物卡**亮金边 ——
## 「松手就装到这个人身上」，别让玩家自己猜。
##
## 与 CardSlot 的 DRAG_HINT 同一语义（金色 = 可以放），也同样是**每帧读视口拖拽状态**
## 的驱动方式：卡可能是从另一个卡槽拖出来的，接不到本区的 card_drag_started 信号。
## 高亮复用提示态那一支（`_add_highlight` / `_remove_highlight`），视觉不必再造一套。
var _equip_hint_chip: CardChip = null


func _process(_delta: float) -> void:
	_refresh_equip_hint()


func _refresh_equip_hint() -> void:
	var target: CardChip = null
	if get_viewport().gui_is_dragging():
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("card") is CardData:
			var c: CardData = data["card"]
			if Player.equip_slot_of(c) != "":
				var hit := chip_at(get_global_mouse_position())
				if hit != null and hit.card != null and hit.card.card_type == "character" and hit.card != c:
					target = hit
	if target == _equip_hint_chip:
		return
	if _equip_hint_chip != null and is_instance_valid(_equip_hint_chip):
		_remove_highlight(_equip_hint_chip)
	_equip_hint_chip = target
	if _equip_hint_chip != null and is_instance_valid(_equip_hint_chip):
		_add_highlight(_equip_hint_chip)


## 当前是否亮着装备落点高亮（探针/调试用）。
func is_equip_hint_visible() -> bool:
	return _equip_hint_chip != null and is_instance_valid(_equip_hint_chip) \
		and _equip_hint_chip.has_node("HintHighlight")


# ============================================================
#  提示态（hint）
# ============================================================

## 进入提示态：slot 为被点击的空槽；priority_attrs 为当前 phase 数值属性（声明序）。
## 把所有"可选"（slot.accepts 通过）的手牌按整理排序聚到最左、其余保持原序在右，
## 并整体上移；首卡（最左）金边高亮 + 放大。
func begin_hint(slot: CardSlot, priority_attrs: Array = []) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	if _hint_active:
		end_hint(false)  # 切换目标槽前先净场
	_hint_slot = slot
	_hint_snapshot = _cards.duplicate()
	_hint_active = true
	_priority_attrs = priority_attrs
	# 过滤可选卡
	var selectable: Array[CardData] = []
	for c in _cards:
		if slot.accepts(c):
			selectable.append(c)
	# 排序可选卡
	var paired: Array[Dictionary] = []
	for i in selectable.size():
		paired.append({"card": selectable[i], "idx": i})
	paired.sort_custom(Callable.create(self, "_cmp_wrapper"))
	var sorted_sel: Array[CardData] = []
	for p in paired:
		sorted_sel.append(p["card"])
	# 其余卡保持原序（排除已选）
	var others: Array[CardData] = []
	for c in _cards:
		if not selectable.has(c):
			others.append(c)
	# 应用到手牌顺序（可选左、其余右）
	_apply_order_from_list(sorted_sel + others)
	# 视觉上移 + 首卡高亮
	_lift_and_highlight(sorted_sel)
	_apply_filter()
	changed.emit()


## 上移可选卡、首卡高亮 + 放大（提示态）。等一帧让 HBox 完成重排，再施加 position 偏移。
func _lift_and_highlight(selectable: Array[CardData]) -> void:
	_hint_lifted.clear()
	_hint_orig_y.clear()
	_hint_best = null
	if selectable.is_empty():
		hint_best_changed.emit(null)
		return
	await get_tree().process_frame
	if not _hint_active:
		return
	for i in selectable.size():
		var chip := _chip_of(selectable[i])
		if chip == null:
			continue
		_hint_lifted.append(chip)
		_hint_orig_y[chip] = chip.position.y
		var lift := HINT_LIFT + (HINT_BEST_EXTRA if i == 0 else 0.0)
		chip.position.y -= lift
		if i == 0:
			chip.pivot_offset = chip.size / 2.0
			chip.scale = Vector2(HINT_BEST_SCALE, HINT_BEST_SCALE)
			_add_highlight(chip)
	_hint_best = selectable[0]
	hint_best_changed.emit(_hint_best)


## 给 chip 加金色高亮描边（提示态首卡），命名为 HintHighlight 便于移除。
func _add_highlight(chip: CardChip) -> void:
	if chip.has_node("HintHighlight"):
		return
	var border := Panel.new()
	border.name = "HintHighlight"
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxLine.new()
	sb.color = Color(0.95, 0.78, 0.3)
	sb.thickness = 3
	border.add_theme_stylebox_override("panel", sb)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.size_flags_horizontal = Control.SIZE_FILL
	border.size_flags_vertical = Control.SIZE_FILL
	chip.add_child(border)


func _remove_highlight(chip: CardChip) -> void:
	var h := chip.get_node_or_null("HintHighlight")
	if h != null:
		h.queue_free()


## 仅清除提示态视觉（position/scale/高亮），不动顺序。
func _end_hint_visual_only() -> void:
	for chip in _hint_lifted:
		if is_instance_valid(chip):
			if _hint_orig_y.has(chip):
				chip.position.y = _hint_orig_y[chip]
			chip.scale = Vector2.ONE
			chip.pivot_offset = Vector2.ZERO
			_remove_highlight(chip)
	_hint_lifted.clear()
	_hint_orig_y.clear()
	_hint_best = null


## 结束提示态。
## place_best=true：把首卡放入 _hint_slot 并卸载（其余卡按快照还原）；
## place_best=false：所有卡按快照还原到变化前位置。
func end_hint(place_best: bool) -> void:
	if not _hint_active:
		return
	var slot: CardSlot = _hint_slot
	var best: CardData = _hint_best
	_hint_active = false
	_hint_slot = null
	_end_hint_visual_only()
	if place_best and slot != null and best != null and is_instance_valid(slot):
		# 经由槽的放置路径入槽（与拖放一致：origin=手牌区，可归还），内部会把手牌里的卡移除
		if slot.has_method("accept_and_place"):
			slot.accept_and_place(best, self)
	# 还原其余卡到快照顺序（若已入槽则排除首卡）
	var order: Array = _hint_snapshot.duplicate()
	if place_best and best != null:
		order.erase(best)
	_apply_order_from_list(order)
	_hint_snapshot.clear()
	_apply_filter()
	changed.emit()


## 提示态是否激活。
func is_hint_active() -> bool:
	return _hint_active


## 提示态首卡（无则 null）。
func get_hint_best() -> CardData:
	return _hint_best


## 取消提示态（点击槽/卡牌区/卡以外时由上层调用）。
func cancel_hint() -> void:
	end_hint(false)


# ============================================================
#  离场：最后兜底写回账本
# ============================================================

## 切场景 / 退出时把手牌最终状态写进 `Player.hand`。
##
## 平时各变更点已经逐次同步了，这一道是最后的兜底网 —— 只要有一条路径漏同步，
## 损失也止步于「最后那次改动」，不至于整个手牌蒸发。
## ⚠️ 离开时若仍在提示态：先 `cancel_hint()` 把临时排序还原成进入前的快照再写，
##    否则会把「可选卡聚到最左」这个一次性动画当成玩家的手牌顺序存进存档。
## ⚠️ **只有「登记在册」的那部才有资格写回**（2026-10-14 探针抓出的第二个坑）。
##
## 第一版这里是无差别 `Player.set_hand_from(_cards)`。听起来无害 —— 实际有个致命反例：
## 若账本在**本视图不在场期间**被别人改过（`add_to_hand` 在无主 UI 的场景落账、
## `grocery` 的 `Player.remove_hand_card` 兜底……），而某个更早创建的 CardArea 此时才被释放，
## 它就会拿自己那份**过时快照**把新账本整个盖掉 —— 那些新来的卡凭空消失，且毫无报错。
## 所以这里要先认身份：当前 TriggerManager 登记的是不是自己。不是（说明它是残留实例，
## 已经有更新的视图接手了）→ 一个字都不写。
func _exit_tree() -> void:
	# 登记在册的是自己 → 有权整理最后状态；否则是残留实例，一个字都不写（见上方说明）
	if TriggerManager.get_card_area() != self:
		return
	# 读档把账本整个换掉了（`_stale` / 世代不符）→ 手里这份是上一局的快照，写回去就是
	# 「点继续游戏后卡片全没」。这条与下一个 if 互相独立，缺一条都会被读档时序钻空子。
	if _stale or Player.hand_gen != _born_hand_gen:
		return
	flush_hand()
	# D-HAND1：注销自己。不要让 TriggerManager 攥着一个已释放对象的引用
	# （get_card_area 有失效兜底，但主动清干净更不容易出岔子）。
	TriggerManager.register_card_area(null)


## 把手牌最终状态写进账本（切场景兜底 / 存档前 flush 共用）。
##
## ⚠️ 离场时若仍在提示态：先还原成进入前的快照再写，否则会把「可选卡聚到最左」这个
##    一次性动画当成玩家的手牌顺序存进账本。
func flush_hand() -> void:
	if _hint_active:
		_hint_active = false
		_end_hint_visual_only()
		_apply_order_from_list(_hint_snapshot)
		_hint_snapshot.clear()
		_apply_filter()
	Player.set_hand_from(_cards)


## 标记本视图作废（`SaveLoader.load_game` 用）：之后无论怎么离场都不再写账本。
func mark_stale() -> void:
	_stale = true



# ============================================================
#  整理按钮（卡牌区左缘）
# ============================================================

func _ready() -> void:
	# 记下出生时的账本世代：离场时世代变了 = 账本被读档换过，本视图无权写回。
	_born_hand_gen = Player.hand_gen
	if tidy_btn != null:
		tidy_btn.pressed.connect(_on_tidy_pressed)
	# 筛选按钮：单选互斥（toggle 组）
	_filter_buttons = {
		"all": filter_all,
		"character": filter_char,
		"equip": filter_equip,
		"book": filter_book,
		"other": filter_other,
	}
	for key in _filter_buttons:
		var btn: Button = _filter_buttons[key]
		if btn != null:
			btn.pressed.connect(_on_filter_pressed.bind(key))
	_current_filter = "all"
	_apply_filter()


func _on_tidy_pressed() -> void:
	# 整理前若有激活的提示态，先净场还原（避免上移视觉与重排冲突）。
	if is_hint_active():
		cancel_hint()
	var attrs: Array = []
	var tp = TriggerManager.get_active_trigger_popup()
	if tp != null and tp.has_method("get_current_priority_attrs"):
		attrs = tp.get_current_priority_attrs()
	tidy_hand(attrs)
	changed.emit()


# ============================================================
#  类别筛选（整理下方 5 按钮：全部/人物/装备/书/其他）
# ============================================================

## 按下某筛选按钮：单选互斥（强制只有本键按下）+ 应用显隐。
func _on_filter_pressed(which: String) -> void:
	_current_filter = which
	for key in _filter_buttons:
		var btn: Button = _filter_buttons[key]
		if btn != null:
			btn.button_pressed = (key == which)
	_apply_filter()


## 卡牌类别键（用于筛选）：人物 / 装备 / 书 / 其他。
## 人物=character 卡；道具中 category_minor 1/2/3=装备(武器/防具/饰品)、4=书、其余=其他。
static func _card_category(card: CardData) -> String:
	if card.card_type == "character":
		return "character"
	var m: int = card.category_minor()
	if m == 4:
		return "book"
	if m == 1 or m == 2 or m == 3:
		return "equip"
	return "other"


## 按当前筛选类别显隐 chip（仅影响 visible，不动底层 _cards / 顺序 / hint 逻辑）。
func _apply_filter() -> void:
	for chip in _chips_in_order():
		var c: CardData = chip.card
		if c == null:
			continue
		var show: bool = (_current_filter == "all") or (_card_category(c) == _current_filter)
		chip.visible = show


# ============================================================
#  构建单张卡牌节点（可拖 CardChip）
# ============================================================

func _make_card_node(card: CardData) -> CardChip:
	var chip := CHIP_SCENE.instantiate() as CardChip
	chip.set_card(card)
	chip.set_draggable(true)
	# 贴 HBox 底部：HBox 高 195（卡片159 + 上移净空36），卡片靠底 → 顶部留出提示态上移区，且被 SHRINK_END 保持 159 高不拉伸。
	chip.size_flags_vertical = Control.SIZE_SHRINK_END
	chip.origin = self
	chip.drop_target = self
	chip.clicked.connect(_on_chip_clicked)
	chip.card_drag_started.connect(_on_chip_drag_started)
	return chip


func _on_chip_clicked(card: CardData) -> void:
	card_clicked.emit(card)


## 手牌内发起拖拽即取消提示态（玩家改手动操作），其余卡按快照还原。
func _on_chip_drag_started(_card: CardData) -> void:
	# 拾起音（设计圣经 §3.6 `ui_card_pickup`）：纸张/硬卡离桌的轻「啵」+ 微摩擦。
	AudioManager.play_sfx("ui_card_pickup")
	if _hint_active:
		end_hint(false)


func _card_id_of(card: CardData) -> String:
	return card.id if card.id != "" else card.display_name
