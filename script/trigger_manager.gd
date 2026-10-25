## TriggerManager — 触发器全局管理器（Autoload）。
## 职责：效果落地（apply_effect）、流程 tag 字典管理（begin/complete/cancel）、
##       触发器便捷入口（open_trigger）。
## 不做 gameplay 逻辑——路由/结算逻辑在 TriggerLoader + TriggerPopup 中。
extends Node

const POPUP_SCENE := preload("res://components/trigger_popup.tscn")
## D-DOC14（打听）：resolver="inquiry" 的触发器弹窗用继承子类场景。
const INQUIRY_POPUP_SCENE := preload("res://components/inquiry_trigger_popup.tscn")
## D-DOC18（读书）：resolver="read_book" 的触发器弹窗用继承子类场景。
const READ_BOOK_POPUP_SCENE := preload("res://components/read_book_trigger_popup.tscn")
## D-DOC23（神秘杂货店）：resolver="grocery" 的触发器弹窗用继承子类场景。
const GROCERY_POPUP_SCENE := preload("res://components/grocery_trigger_popup.tscn")


## 按 trigger 顶层 resolver 选择弹窗场景（默认基类；inquiry → 打听子类、read_book → 读书子类、
## grocery → 神秘杂货店子类）。
## 供 TriggerSpot / open_trigger 统一取用，避免两处各自硬编码 preload。
func popup_scene_for(trigger_id: String) -> PackedScene:
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	match String(raw.get("resolver", "")):
		"inquiry":
			return INQUIRY_POPUP_SCENE
		"read_book":
			return READ_BOOK_POPUP_SCENE
		"grocery":
			return GROCERY_POPUP_SCENE
	return POPUP_SCENE

## 当前触发器流程中获得的 tag 字典（键 = tag 名，值 = true）。
## 与 Player.player_tags（持久存档态）隔离：流程中 tag 只进这里，
## 全流程完成时合并进 player_tags 并清空——避免可重复触发器重复累加 tag，
## 以及流程中途异常退出残留 tag 的 bug。
var _flow_tags: Dictionary = {}

## 待执行的换图目标（D-S7，旅行触发器）。由 apply_effect 登记，
## **延迟到全流程结束（complete_flow 之后）**才真正执行——否则流程未结算完
## 场景就没了，_flow_tags 会丢。空串=无换图。
var _pending_goto_scene: String = ""

## D-DOC10（2026-08-24）：延迟事件队列。effect.delayed_event 登记 {days:N, plot:"键名"}，
## 在 N 天后的 day_changed 触发时播放该剧情。结构：[{fire_day:int, plot_key:String}]。
var _delayed_events: Array = []

# ============================================================
#  D-DOC24（2026-09-13）：触发器初始化（回合边界唯一入口）
#  - 初始化**只在回合边界**执行，不在「打开弹窗」时现场生成内容；
#  - init_scope="static"（默认）→ 游戏开始时初始化一次；
#  - init_scope="turn" → 每个回合边界重建实例；
#  - 弹窗只读实例（见 TriggerPopup._rebuild_slots）。
# ============================================================

## 回合级触发器实例：{trigger_id: {slot_name: card_id}}。
## 由 advance_turn() → _rebuild_turn_instances() 在回合边界生成；
## **不持久化**——吸附抽取确定性（Player.make_rng），
## 丢了可精确重算，读档后由 initialize_for() 兜底重建。
var _turn_instances: Dictionary = {}
## _turn_instances 对应的天数（Player.time）。≠ 当前天 → 实例过期，需重建。
var _turn_instances_day: int = -1

## 结算成功需播放剧情时广播（D-C2 / 亲历鉴定「入剧情」）：参数为 plot 键名。
## 由 TriggerManager 内部接到 PlotImporter.play_by_key 播放；
## 键名 → 文件映射见 resoures/plot/dialogue_registry.json（数据驱动）。
signal plot_requested(plot_key: String)

## 主 UI 卡牌区引用（由 MainUI._ready 注册，见 main_ui.gd）。触发器结算后：
## 未消耗的卡牌经 TriggerPopup.cards_returned、购得的书卡经 book_acquired 塞回此处。
## 未注册（如某些纯代码调试场景）时返回 null，调用方需判空。
var _card_area: CardArea = null

## 主 UI 在 _ready 时调用，注册其卡牌区，供触发器弹窗把结算卡归还手牌。
func register_card_area(a: CardArea) -> void:
	_card_area = a

## 取已注册的主 UI 卡牌区（未注册 / **已随旧场景销毁** → null）。
##
## ⚠️ D-HAND1：旧实现对 `is_instance_valid` 毫无防备。CardArea 是场景内节点，
## 切场景后这里会留着一个**已释放对象的悬空引用** —— 它不是 null，`ca == null` 判不住，
## 于是 `_apply_add_to_hand` / `ActionQueue._land` 会对着僵尸调 add_card。
## 有了手牌账本之后尤其致命：调用方正因为「有 UI」而不走 `Player.add_hand_card` 兜底，
## 结果卡既没进视图、也没进账本，凭空消失。所以这里必须在返回前把失效引用清掉。
func get_card_area() -> CardArea:
	if _card_area != null and not is_instance_valid(_card_area):
		_card_area = null
	return _card_area


## 当前打开的触发器弹窗（供卡牌区「整理」按钮取 priority_attrs / 提示态）。
## 由 open_trigger 注册、弹窗 close 清空。
var _active_popup: TriggerPopup = null

## 注册/清空当前活动触发器弹窗。
func set_active_trigger_popup(p: TriggerPopup) -> void:
	_active_popup = p

## 取当前活动触发器弹窗（无 → null）。卡牌区「整理」按钮凭此决定人物卡数值排序属性。
func get_active_trigger_popup() -> TriggerPopup:
	return _active_popup


## 当前「放在触发器卡槽里、仍算玩家自己的手牌」的卡（2026-10-24，存档补全用）。
##
## 给 `SaveLoader.data_get()` 用：这些卡在拖进槽的那一刻就被 `remove_hand_card` 从账本摘掉了
## （槽里的卡不算手上），若存档只写账本，玩家一读档它们就蒸发。**只读**，不改变任何运行时状态。
## 判据全在弹窗侧（`TriggerPopup.hand_cards_on_hold`）：来自手牌 + 非消耗/未消耗 + 吸附时被摘走的。
func pending_hand_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	if _active_popup == null or not is_instance_valid(_active_popup):
		return out
	if _active_popup.has_method("hand_cards_on_hold"):
		out = _active_popup.hand_cards_on_hold()
	return out



## 开始一个新的触发器流程：清空流程 tag 字典与待执行换图。
func begin_flow() -> void:
	_flow_tags.clear()
	_pending_goto_scene = ""


func _ready() -> void:
	# D-C2：结算成功生成的剧情键统一路由到 PlotImporter 播放（数据驱动）。
	plot_requested.connect(_on_plot_requested)
	# D-DOC10：订阅 day_changed，到期的延迟事件触发播放。
	EventSignal.day_changed.connect(_on_day_changed)
	# D-GRAD1：订阅 dialogue_finished，驱动毕业结局的剧情连播（任何一段对话播完都来问一次，
	# 只有「毕业队列播放中」才动作，见 _on_dialogue_finished）。
	EventSignal.dialogue_finished.connect(_on_dialogue_finished)
	# D-DOC24：游戏开始 = 第 1 回合边界 → 初始化触发器（延迟到所有 Autoload 就绪后执行）。
	_initial_setup.call_deferred()


## D-DOC24 游戏开始初始化：延迟到 Autoload 全部就绪（TriggerLoader / CardRegistry 已加载完表）。
func _initial_setup() -> void:
	init_all_static()


# ============================================================
#  D-DOC24：初始化入口（回合边界）
# ============================================================

## 游戏开始时调用一次（= 第 1 回合边界）。
## 静态作用域触发器当前**无实例状态**（打开弹窗时按当前玩家状态现场计算），故此处只需
## 生成第 1 回合的回合级实例；本方法作为「游戏开始」的规范入口保留，未来静态初始化挂这里。
func init_all_static() -> void:
	advance_turn()


## 回合边界（每次「下一天」）：清空「本回合已消耗」→ 重建回合实例。
##
## 为何两步都放这里（而不是 Player._on_day_changed 清、这里重建）：
## `day_changed` 的订阅顺序是 **TriggerManager 先于 Player**（TriggerManager 在 `_ready` 里直接
## connect，Player 是 `call_deferred` 后才 connect），若清空点留在 Player 就会「先用旧的已消耗表
## 建实例、再清空」——新一天的货架会错误地排除掉昨天卖掉的商品。二者同处一个入口即可与订阅
## 顺序解耦，语义也收敛到「回合边界唯一入口」。
func advance_turn() -> void:
	Player.trigger_consumed.clear()
	_rebuild_turn_instances()


# ============================================================
#  D-随机事件组（2026-10-15 孩子线三事件）：每回合只放行一个
# ============================================================

## 随机事件组仲裁 —— 返回本回合该组**唯一**应当可见的触发器 id（无人命中 → ""）。
##
## 用途 = 「每个回合只能触发一个随机事件」：把若干概率刷新的触发器标上同一个
## `show_when.group`，它们就共用一个坑位、同一天最多冒一个。组内成员各自按 show_when 的
## 自身条件（tags / unless_tags / num_tags / child_tags / chance）判资格，命中的按触发器
## 顶层 `priority` 升序取第一个；priority 相同则按 trigger.json 的声明顺序定先后。
##
## 确定性：判定全走 Player 当前状态 + Player.make_rng_for_day —— **同一天、同一状态 → 同结果**。
## 所以读档 / 重进场景 / 反复 _refresh 都不抖动，也不需要新增任何存档状态。
## **不缓存**：玩家推进（例如点掉霸凌、拿到新 tag）之后必须立刻重算，缓存反而会给出过期结论。
##
## 与 TriggerSpot 的分工：候选资格判定只有一份，就是 `TriggerSpot.show_when_candidate_ok`；
## 本方法只负责「在合格者里按优先级挑唯一一个」，不另立一套条件解释。
func resolve_random_group(group: String) -> String:
	if group == "":
		return ""
	var candidates: Array = []
	for tid in TriggerLoader.all_trigger_ids():
		var t := String(tid)
		var raw: Dictionary = TriggerLoader.get_trigger(t)
		var sw: Dictionary = raw.get("show_when", {})
		if String(sw.get("group", "")) != group:
			continue
		candidates.append({
			"id": t,
			"pri": int(raw.get("priority", 1000000)),
			"ord": candidates.size(),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["pri"]) != int(b["pri"]):
			return int(a["pri"]) < int(b["pri"])
		return int(a["ord"]) < int(b["ord"]))
	for c in candidates:
		var raw2: Dictionary = TriggerLoader.get_trigger(String(c["id"]))
		if TriggerSpot.show_when_candidate_ok(raw2):
			return String(c["id"])
	return ""


## 按声明重建所有 init_scope="turn" 的触发器实例（**不改**已消耗表）。
## init_scope="static" 的触发器不参与（内容不随回合变化）。
func _rebuild_turn_instances() -> void:
	_turn_instances.clear()
	for tid in TriggerLoader.list_by_init_scope(TriggerLoader.INIT_SCOPE_TURN):
		_turn_instances[String(tid)] = _build_turn_instance(String(tid))
	_turn_instances_day = Player.time
	print("[TriggerManager] 回合初始化（第%d天）：%d 个回合级触发器实例" % [Player.time, _turn_instances.size()])


## 幂等兜底：弹窗打开前确保该触发器的回合实例存在。
##  - 非回合级触发器 → 直接返回（走打开时现场计算）；
##  - 实例天数 ≠ 当前天（未初始化 / 已跨天 / 读档换了天）→ 全量重建。
##    **不在此清空「已消耗」**：读档时该表来自存档、正对应存档当天，清掉会让已买走的商品复活。
func initialize_for(trigger_id: String) -> void:
	if not TriggerLoader.is_turn_scoped(trigger_id):
		return
	if _turn_instances_day != Player.time:
		_rebuild_turn_instances()
		return
	if _turn_instances.has(trigger_id):
		return
	_turn_instances[trigger_id] = _build_turn_instance(trigger_id)


## 取某触发器的回合实例 {slot_name: card_id}（无 → 空字典）。
func get_turn_instance(trigger_id: String) -> Dictionary:
	var v: Variant = _turn_instances.get(trigger_id, null)
	return v if v is Dictionary else {}


## 该触发器本回合是否已消耗该卡。
func is_consumed(trigger_id: String, card_id: String) -> bool:
	return card_id in consumed_ids(trigger_id)


## 标记该触发器本回合已消耗该卡（幂等）。
func mark_consumed(trigger_id: String, card_id: String) -> void:
	if trigger_id == "" or card_id == "":
		return
	if not Player.trigger_consumed.has(trigger_id):
		Player.trigger_consumed[trigger_id] = []
	var bucket: Array = Player.trigger_consumed[trigger_id]
	if not bucket.has(card_id):
		bucket.append(card_id)


## 该触发器本回合已消耗的卡 id 列表（无 → 空数组）。
func consumed_ids(trigger_id: String) -> Array:
	var v: Variant = Player.trigger_consumed.get(trigger_id, null)
	return (v as Array).duplicate() if v is Array else []


## 生成回合级触发器实例：遍历其**所有 display** 的 slots，对带 auto_attract 的槽预抽一次。
## 「哪个槽抽什么」仍由 JSON 声明驱动，引擎通用执行——**无子类特判**
## （初始化发生在弹窗创建之前，不可能放在 UI 子类里）。
## 跨槽去重（同一件货不占两个槽）+ 排除本回合已消耗（被买走的商品不再上架）。
func _build_turn_instance(trigger_id: String) -> Dictionary:
	var out: Dictionary = {}
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	if raw.is_empty():
		return out
	var expanded: Dictionary = TriggerLoader.expand(raw)
	var turns: Dictionary = expanded.get("turns", {})
	var attracted_ids: Array = []
	for turn_id in turns:
		var turn: Dictionary = turns[turn_id]
		for ph in turn.get("phases", []):
			var phase: Dictionary = ph
			var displays: Dictionary = phase.get("displays", {})
			for dname in displays:
				var d: Dictionary = displays[dname]
				var slots: Dictionary = d.get("slots", {})
				for slot_name in slots:
					var key := String(slot_name)
					if out.has(key):
						continue  # 同名槽在多个 display 间共享同一实例
					var cfg: Dictionary = slots[slot_name]
					var spec: Dictionary = TriggerLoader.attract_spec(cfg)
					if spec.is_empty():
						continue
					var exclude: Array = attracted_ids.duplicate()
					exclude.append_array(consumed_ids(trigger_id))
					var card: CardData = TriggerLoader.attract_card(
						String(spec.get("tag", "")),
						String(cfg.get("accept", "")),
						spec.get("classes", []),
						exclude,
						"attract:%s:%s" % [trigger_id, key]
					)
					if card != null:
						out[key] = card.id
						attracted_ids.append(card.id)
	return out


func _on_plot_requested(plot_key: String) -> void:
	PlotImporter.play_by_key(plot_key)


## 当前流程中获得的 tag（数组形式，供 UI/调试显示）。
func get_flow_tags() -> Array:
	return _flow_tags.keys()


## 路由判定用的 tag 集合 = 持久 player_tags + 本流程 _flow_tags。
## 既保留之前流程提交的 tag，又让本流程新获得的 tag 立即参与路由。
func get_routing_tags() -> Array:
	var out: Array = []
	for t in Player.player_tags:
		out.append(t)
	for k in _flow_tags.keys():
		out.append(k)
	return out


## 应用效果到 Player 状态。effect 结构与 dialogue deal_effect 一致：
## {tags:[], num_tags:{}, stuff:[], money:int, attrs:{}, equipment:[], goto_scene:String,
##  remove_tags:[], remove_num_tags:{}, slot_tags:{}, slot_attrs:{}}
## 注意：tags 进入 _flow_tags（流程字典），不直接写 player_tags。
## remove_tags / remove_num_tags（D-F2）：移除玩家级 tag / 可堆叠词条。
## goto_scene（D-S7，旅行触发器）仅**登记**，延迟到全流程结束才执行。
## slot_tags / slot_attrs（D-DOC9，2026-08-24）：对当前流程中某槽位的角色卡施加 tag / 属性增量。
##   placed 为 {slot_name: CardData}，由 TriggerPopup 传入。
func apply_effect(effect: Dictionary, placed: Dictionary = {}) -> void:
	if effect.is_empty():
		return
	# 触发器系统 effect 处理统一转发 EffectProcessor（三系统共用同一套 effect 契约）。
	# 触发器特有行为由 context 控制：
	#   - flow_tags：tags 进流程态字典 _flow_tags（全流程结束 complete_flow 才提交 player_tags，
	#     避免可重复触发器重复累加 tag、流程中途异常退出残留 tag）。
	#   - collect_goto：goto_scene 仅登记到 ctx["goto_scene"]，由本方法取回存入 _pending_goto_scene，
	#     延迟到 complete_flow 之后才真正换图（D-S7，否则流程未结算完场景就没了，_flow_tags 会丢）。
	#   - placed（D-DOC9）：{slot_name: CardData}，供 slot_tags/slot_attrs 定位施加对象。
	# 其余字段（num_tags/stuff/money/attrs/npc/child/equipment/remove_tags/remove_num_tags）
	# 由 EffectProcessor 即时落地 Player，与旧实现等价。
	var ctx: Dictionary = {
		"flow_tags": _flow_tags,
		"collect_goto": true,
		"placed": placed,
	}
	EffectProcessor.apply(effect, ctx)
	var goto_v: Variant = ctx.get("goto_scene", null)
	if goto_v is String and goto_v != "":
		_pending_goto_scene = String(goto_v)
	# D-DOC10：延迟事件登记（不入 Player，仅入队列等 day_changed 触发）
	var de_v: Variant = effect.get("delayed_event", null)
	if de_v is Dictionary:
		var de: Dictionary = de_v
		register_delayed_event(int(de.get("days", 1)), String(de.get("plot", "")))


## D-DOC10（2026-10-11 扩展）：登记一条延迟事件。
## 唯一入口——触发器 effect（apply_effect）与**剧情 effect**（EffectProcessor.apply）都走这里，
## 保证 fire_day = 当天 + days 只有一份实现（孩子线「这几天」的 3 回合倒计时走的是剧情侧）。
## plot_key 为空则忽略；键名须登记在 resoures/plot/dialogue_registry.json 才会真正播出来。
func register_delayed_event(days: int, plot_key: String) -> void:
	if plot_key == "":
		return
	_delayed_events.append({"fire_day": Player.time + days, "plot_key": plot_key})
	print("[TriggerManager] 登记延迟事件：第%d天播 '%s'" % [Player.time + days, plot_key])


## D-DOC10：day_changed 回调——到期事件触发 plot_requested 播放。
## D-DOC24：同时是「回合边界」→ 先推进触发器回合（清已消耗 + 重建回合实例），再处理延迟事件。
func _on_day_changed(day: int) -> void:
	advance_turn()
	var remaining: Array = []
	for ev in _delayed_events:
		if int(ev["fire_day"]) <= day:
			plot_requested.emit(String(ev["plot_key"]))
			print("[TriggerManager] 延迟事件触发：第%d天播 '%s'" % [day, String(ev["plot_key"])])
		else:
			remaining.append(ev)
	_delayed_events = remaining
	# D-GRAD1：毕业结局判定放在延迟事件之后 —— 同一天既有倒计时剧情又有毕业时，
	# 先播倒计时（它会把 is_dialogue_exist 占住），毕业队列随后被 dialogue_finished 接上。
	_check_graduation()


# ============================================================
#  D-GRAD1（2026-10-16）：毕业结局 ——「之后游戏结束」的接线
#
#  口径（用户 2026-10-16 原话）：「把毕业的剧情接入游戏：在存在 child 且完成了三次上学后
#  在第 20 回合触发，之后游戏结束」。
#
#  · 触发点 = 回合边界（_on_day_changed 末尾，与延迟事件同一入口），**不占地图坑位**：
#    结局是时点事件，不该要求玩家「走到某个点去点」。
#  · 条件 = Player.time ≥ 20 且 有孩子（Player.child_name != ""）且
#    player_num_tags["学校学习"] ≥ 3（trigger.json「学校学习」每次送学 +1、cap 3）。
#    取 **≥20** 而非 ==20：三次送学每次 duration=2 天， pacing 上完全可能踩过第 20 天，
#    判等会让结局永久错过（软锁）。第 20 天之前绝不触发。
#  · 剧情 = 按天赋二选一（design/孩子线剧情导入_2026-10-11.md §四第 3 条既定口径）：
#    gifted → 毕业作品-选择方向 → 毕业作品-毕业展（两段连播）；
#    common → 毕业和礼物。
#  · 收场 = 存档（stage=done 落盘）→ 清覆盖层 → 过场回标题（scene/loading.tscn）。
#    标题「继续游戏」读回的是已收场的档，不会再播一遍。
#  · 状态全持久化（Player.graduation_stage / graduation_queue）：结局播到一半存档/读档，
#    由 Player.plot 锚点续播 + dialogue_finished 接链，不会断也不会重播。
# ============================================================

## 毕业剧情最早触发回合。
const GRADUATION_DAY := 20
## 「送学」计数键（玩家级 num_tag）与毕业门槛。
const GRADUATION_SCHOOL_TAG := "学校学习"
const GRADUATION_SCHOOL_MIN := 3
## 收场目标场景：**通关结算页**（D-END2，2026-10-23 起）。
## 旧值是标题页 `res://scene/loading.tscn` —— 结局播完直接跳回主菜单，中间没有任何收束。
## 现在先落到 `scene/ending.tscn`（近黑底 +「感谢你的游玩」+ 解锁通关成就），
## 玩家点一下就回标题；标题页仍是那条链的终点，只是不再是**第一落点**。
const GRADUATION_END_SCENE := "res://scene/ending.tscn"

## 探针接缝：默认空 = 走真实收场。debug/_graduation_probe.gd 会塞一个记录用 Callable，
## 避免探针真写存档、真切场景。**生产代码永远不要设置它。**
var ending_action: Callable = Callable()


## D-GRAD1：毕业结局触发判定。已触发过（playing/done）→ 永不重复。
func _check_graduation() -> void:
	if String(Player.graduation_stage) != "":
		return
	if int(Player.time) < GRADUATION_DAY:
		return
	if Player.child_name == "":
		return
	if int(Player.player_num_tags.get(GRADUATION_SCHOOL_TAG, 0)) < GRADUATION_SCHOOL_MIN:
		return
	Player.graduation_stage = "playing"
	Player.graduation_queue = _graduation_plot_keys()
	SaveLoader.save_game()
	print("[TriggerManager] 毕业结局触发（第%d天）：队列 %s" % [Player.time, str(Player.graduation_queue)])
	_play_next_graduation()


## D-GRAD1：毕业剧情队列按天赋分流（孩子线导入文档 §四第 3 条）。
## gifted → 毕业作品两段连播；common（或未标档）→ 毕业和礼物。
func _graduation_plot_keys() -> Array:
	var child: Dictionary = _graduation_child_entry()
	var tags: Array = child.get("tags", [])
	if "gifted" in tags:
		return ["毕业作品-选择方向", "毕业作品-毕业展"]
	return ["毕业和礼物"]


## 当前唯一孩子的 npc 条目（无 → 空字典）。与 Player.child_name 同一扫描口径。
func _graduation_child_entry() -> Dictionary:
	for key in Player.npc:
		var entry: Variant = Player.npc[key]
		if entry is Dictionary and "child" in (entry as Dictionary).get("tags", []):
			return entry
	return {}


## D-GRAD1：播队列里下一段毕业剧情；队列空 → 收场。
## 两个设计点保证「被别的对话占着」时安全等待、坏数据不卡死：
##   ① 起播前看 Player.is_dialogue_exist —— 被占（如当天的延迟事件剧情）就原样退回，
##      那段对话自己的 dialogue_finished 会再来敲门，键不丢；
##   ② 先用 PlotImporter.can_play 滤掉坏键（未注册/文件缺失/段落为空 → 直接出队并警告），
##      真起来了才出队 + 存档（半路读档靠这个把队列位置接回去）。
func _play_next_graduation() -> void:
	while not Player.graduation_queue.is_empty():
		var key: String = String(Player.graduation_queue[0])
		if not PlotImporter.can_play(key):
			push_warning("TriggerManager: 毕业剧情键 '%s' 不可播（未注册/文件缺失/段落为空），跳过" % key)
			Player.graduation_queue.pop_front()
			continue
		if Player.is_dialogue_exist:
			return
		PlotImporter.play_by_key(key)
		Player.graduation_queue.pop_front()
		SaveLoader.save_game()
		print("[TriggerManager] 毕业剧情起播：'%s'（剩余 %s）" % [key, str(Player.graduation_queue)])
		return
	_finish_graduation()


## D-GRAD1：任何一段对话播完都来问一次——只有毕业队列播放中（stage=playing）才继续播下一段
## 或收场。其它对话（随机事件、报纸、触发器剧情）一律不影响，也不会被误收场。
func _on_dialogue_finished() -> void:
	if String(Player.graduation_stage) != "playing":
		return
	_play_next_graduation()


## D-GRAD1：队列播空 → 游戏结束。stage 先落 "done" 再收场：之后任何
## dialogue_finished / day_changed 都直接跳过（含「结局后继续游戏」的档）。
func _finish_graduation() -> void:
	if String(Player.graduation_stage) != "playing":
		return
	Player.graduation_stage = "done"
	print("[TriggerManager] 毕业剧情播完，游戏结束")
	_perform_game_ending()


## 真实收场动作：存档（把 stage=done 落盘）→ 清覆盖层（overlay 不随场景销毁，
## 不清会跟着报纸/弹窗到结算页）→ 过场进**通关结算页** `scene/ending.tscn`。
## 通关成就「谢谢你体验完完整游戏」不在这里解锁，由结算页自己 `_ready` 发
## （见 `scene/ending.gd` 文件头：放在这里会被过场快照盖掉开头 0.45s）。
## 探针经 ending_action 接缝替换本方法体。
func _perform_game_ending() -> void:
	if ending_action.is_valid():
		ending_action.call()
		return
	SaveLoader.save_game()
	OverlayRoot.clear_all()
	SceneTransition.change_scene(GRADUATION_END_SCENE)


## 全流程完成：把流程字典里的 tag 提交进 Player.player_tags（去重），清空字典。
## 返回该触发器是否可重复（repeatable）——供 TriggerSpot 决定是否禁用自身。
func complete_flow(trigger_id: String) -> bool:
	for tag in _flow_tags.keys():
		# 提交进 player_tags 并顺带登记 turn 计时（带 turn 的 tag），与直落路径共用 Player.grant_tag
		Player.grant_tag(String(tag))
	_flow_tags.clear()
	return TriggerLoader.is_repeatable(trigger_id)


## D-S7：全流程结束后执行待定的换图（旅行触发器）。固定顺序，不可调换：
##   complete_flow（已提交 tag）→ 关弹窗 → 写 Player.path → change_scene → emit scene_entered
## 由 TriggerPopup._finish_flow 在 complete_flow 之后调用。无待定项则空操作。
## 路径无效 / 切换失败 → push_error + 停留原地，不崩溃不黑屏。
func execute_pending_goto_scene(popup: Node) -> void:
	if _pending_goto_scene == "":
		return
	var target: String = _pending_goto_scene
	_pending_goto_scene = ""

	# 1. 先关弹窗（顺序不可调换：否则覆盖层随旧场景销毁但模态栈残留）
	if is_instance_valid(popup) and OverlayRoot.has_overlay(popup):
		OverlayRoot.close_overlay(popup)

	# 2. 路径校验（降级：停留原地）
	if not ResourceLoader.exists(target):
		push_error("TriggerManager: goto_scene 目标场景不存在：%s，停留原地（D-S7）" % target)
		return

	# 3. 写回档锚点
	Player.path = target

	# 4. 切场景
	var err := get_tree().change_scene_to_file(target)
	if err != OK:
		push_error("TriggerManager: goto_scene 切换失败 %s（err=%d），停留原地（D-S7）" % [target, err])
		return

	# 5. 广播进入事件
	EventSignal.scene_entered.emit(target)


## 中途取消/关闭：丢弃流程字典（不提交），清空。
func cancel_flow() -> void:
	_flow_tags.clear()


## 便捷入口：打开指定触发器弹窗。返回 TriggerPopup 实例（已 add 到 root）。
## 配合 TriggerSpot 使用，也可从代码任意位置调用：
##   TriggerManager.open_trigger("盗窃贵族宅邸")
func open_trigger(trigger_id: String) -> TriggerPopup:
	# 防重复。弹窗由 OverlayRoot 托管（D-UI6），不再是 tree.root 的直接子节点，
	# 所以改为向覆盖层管理器查询。
	for overlay in OverlayRoot.get_overlays():
		if overlay is TriggerPopup:
			push_warning("TriggerManager: 已有触发器弹窗打开中，跳过")
			return null

	# E-独占（默认 true）：该触发器有进行中 / 待结算的异步行动时禁用打开。
	if TriggerLoader.is_exclusive(trigger_id) and ActionQueue.has_active(trigger_id):
		push_warning("TriggerManager: %s 有进行中行动，跳过（exclusive）" % trigger_id)
		return null

	var popup := popup_scene_for(trigger_id).instantiate() as TriggerPopup
	if popup == null:
		push_error("TriggerManager: 无法实例化 TriggerPopup")
		return null
	set_active_trigger_popup(popup)

	# 统一交给覆盖层管理器（D-UI6）。仍走 call_deferred：本函数可能在某个节点的
	# _ready 阶段被调用。setup 也在 deferred 里调用（保证 _ready 跑完、
	# @onready/@export 节点就位），失败处理由 TriggerPopup 自己在 setup 内部
	# 负责（push_warning），这里不再做同步的返回校验。
	OverlayRoot.push_overlay.call_deferred(popup, {
		# 非模态：触发器弹窗需从卡牌区拖卡入卡槽，故不可插全屏输入拦截层
		# （否则 ModalBlocker 会吞掉卡牌区的鼠标事件，卡无法拖拽）。
		"modal": false,
		"esc_closes": true,
		"close_method": "close",
	})
	# 购得的书卡经 book_acquired 进卡牌区 —— 也不能绑死视图，理由同上。
	popup.book_acquired.connect(deliver_card)
	var setup_callable: Callable = popup.setup
	setup_callable.call_deferred(trigger_id)

	return popup


## D-HAND2：把一张「玩家新获得」的卡落进手牌。
## **每次都现问**当前卡牌区：它可能不是开弹窗那张视图了（甚至暂时不在场——此时直落账本，
## 等玩家回到带手牌的场景由 `_restore_hand` 兑现）。add_card 内部已经同步账本，
## 这里不能再补一次 `Player.add_hand_card`（可堆叠卡会被记两遍）。
func deliver_card(card: CardData) -> void:
	if card == null:
		return
	var ca: CardArea = get_card_area()
	if ca != null:
		ca.add_card(card)
	else:
		Player.add_hand_card(card)


## 亲历鉴定（D-C1/D-C2）：主角专属触发器快捷入口。
## 与 open_trigger 不同——不开拖卡弹窗，自动主角入槽 + 直接结算（check 必为 null，由 D-C1 保证必成功），
## 成功后触发「入剧情」（plot_requested，键名取自 harvest.dialogue）。
## spot 可选：传入则由其管理禁用 / 反重入（非重复→永久消耗；重复→对话播放期禁用、结束后恢复）。
## 返回 true=已发起并成功结算；false=未找到 / 非 protagonist_only / 配置校验失败。
func open_protagonist_trigger(trigger_id: String, spot: TriggerSpot = null) -> bool:
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	if raw.is_empty():
		push_error("TriggerManager: 未找到触发器 %s" % trigger_id)
		return false
	if not bool(raw.get("protagonist_only", false)):
		push_error("TriggerManager: %s 不是 protagonist_only 触发器，拒绝 open_protagonist_trigger（请用 open_trigger）" % trigger_id)
		return false

	var expanded: Dictionary = TriggerLoader.expand(raw)
	var errs: Array = TriggerLoader.validate(expanded)
	if not errs.is_empty():
		push_error("TriggerManager: 触发器 %s 校验失败：\n%s" % [trigger_id, "\n".join(errs)])
		return false

	begin_flow()
	# D-C1 保证 check==null → 无随机 / 比大小，必成功。直接应用 harvest 效果 + 入剧情。
	var harvest: Dictionary = expanded.get("harvest", {})
	var harvest_effect: Dictionary = harvest.get("effect", {})
	if not harvest_effect.is_empty():
		apply_effect(harvest_effect)
	var plot_key: String = String(harvest.get("dialogue", ""))
	complete_flow(trigger_id)

	# spot 联动：非重复→永久消耗；重复→对话播放期禁用（恢复由 dialogue_finished 触发）
	if spot != null:
		if not TriggerLoader.is_repeatable(trigger_id):
			spot.consume()
		else:
			spot.mark_dialogue_active()

	# 发射入剧情信号（键名为空则仅结算，不播剧情）
	plot_requested.emit(plot_key)
	print("[TriggerManager] 亲历鉴定 %s 完成，入剧情键='%s'" % [trigger_id, plot_key])
	return true
