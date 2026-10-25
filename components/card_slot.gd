## 卡槽组件 —— 拖放目标：从卡牌区把卡拖入，右击清空，执行前可拖出取回。
## 放置后内部显示 CardChip（可拖，drop_target=自身，支持替换/取回）。
## 拖拽载荷为 dict：{"card": CardData, "origin": CardArea|CardSlot}。
##   - 来源于 CardArea：放置成功后从卡牌区移除该卡（进入卡槽）。
##   - 来源于另一 CardSlot：放置成功后清空来源卡槽（在卡槽间移动）。
## 发 card_changed(slot_name, card) 信号（card=null 表示清空）。
## set_card 为静默设置（不发信号），用于 display 切换后恢复已放置的卡（兼容 e2e 测试）。
class_name CardSlot
extends VBoxContainer

## 卡内容变化时发出。card 为 null 表示该槽清空。
signal card_changed(slot_name: String, card: CardData)
## 空槽被左键单击（提示态触发用）。
signal empty_slot_clicked(slot: CardSlot)
## 空槽被左键双击（直接把最合适卡入槽用）。
signal empty_slot_double_clicked(slot: CardSlot)

@onready var name_label: Label = $NameLabel
@onready var drop_zone: Panel = $DropZone
@onready var chip_holder: Control = $DropZone/ChipHolder

var slot_name: String = ""
var accept: String = ""
var required: bool = false
## 禁止放入的 tag 列表（家业经营 D-F1：带「受伤」tag 的护卫卡禁入出航槽）。
## 空数组 = 无限制。
var forbid_tags: Array[String] = []
## 限定只接受特定名字/ID 的 NPC（D-DOC6，2026-08-24）。
## 空数组 = 无限制。非空时卡牌 display_name 或 id 命中其一才允许放入。
var accept_name: Array[String] = []
## 限定只接受特定类别（card_class，如 ["book"]）的道具卡（D-DOC18，2026-08-26，读书）。
## 空数组 = 无限制。非空时卡牌 card_class 命中其一才允许放入。
var accept_class: Array[String] = []
var _current: CardData = null
## 卡牌来源（CardArea 或 CardSlot）；取回/清空时据此归还（仅 CardArea 原点才回手牌）。
var _origin: Variant = null
## D-HAND2：这张卡最初是不是玩家从手牌拖进来的（见 `did_come_from_hand`）。
var _from_hand := false
## 交互锁（冻结态：触发器执行后等待结算期间禁用拖放/右键取回）。
var _interactive := true
## D-ATTRACT-LOCK（2026-10-24）：吸附锁 —— 槽里的卡是引擎吸附上来的（auto_attract / 回合实例）。
## 锁死后玩家不能把它拖走、拖别的卡来替换、右键取走、提示态放入；引擎路径
##（set_card / clear_card）不受限 ——「只能通过其他方式来操控」。
var _locked := false

## card_chip 的实例化场景（**惰性 load，不要改回 `preload`**）。
##
## 为什么不是 const preload（2026-10-24 实测）：`card_slot.gd` 的编译时机可能早于
## `card_chip.tscn` 的资源就绪（编辑器在跑、`.godot` 导入/uid 缓存被并发写过时尤其明显）。
## 那一刻 `preload` 拿到的是**空的 PackedScene**，而 GDScript 会把这个空值钉进常量表 ——
## 于是整个进程内每次 `_refresh_view()` 的 `instantiate()` 都失败（引擎报
## `Failed to instantiate scene state of "", node count is 0`），**卡槽永远画不出卡**。
## 同一进程里 `load()` 这个路径是好的（实测：`preload` 常量为空、`load()` 能实例化），
## 所以这里改成运行期取、并缓存一次。
static var _chip_scene: PackedScene = null


static func chip_scene() -> PackedScene:
	if _chip_scene == null:
		_chip_scene = load("res://components/card_chip.tscn")
	return _chip_scene

## 拖拽落点高亮（审计 C3，2026-10-14 实装）。
## 拖着一张卡移动时，**所有会接受它的槽位**各亮一圈淡金描边 —— 玩家一眼看出哪儿放得进，
## 不必一个一个试；不亮的槽位就是「这里放不进」的回答。
## 金色取 `card_area._add_highlight` 同一支（提示态首卡那圈），同一个「可以选它」的语义。
const DRAG_HINT_COLOR := Color(0.95, 0.78, 0.3)

## 边框压在槽位最上面；只有描边与一层极淡底，不会挡住槽里的卡面。
var _highlight: Panel = null
## 上一帧是不是在拖拽中。
var _drag_watching := false
## 这份高亮是**为哪张卡**算的。载荷在一次拖拽里不变，所以只在「开始拖」与「换了一张卡」
## 这两个时刻重算，不是每帧算。
var _hint_card: CardData = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 空槽占位标签改为穿透，否则挡住左键、空槽点击（提示态）收不到 gui_input。
	var ph := drop_zone.get_node_or_null("Placeholder")
	if ph is Control:
		(ph as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_highlight()
	gui_input.connect(_on_slot_gui_input)
	_refresh_view()


## 建拖拽落点高亮层。挂在 `DropZone` 名下、排在最后 ⇒ 画在占位字与卡面之上。
func _build_highlight() -> void:
	_highlight = Panel.new()
	_highlight.name = "DragHighlight"
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(DRAG_HINT_COLOR.r, DRAG_HINT_COLOR.g, DRAG_HINT_COLOR.b, 0.10)
	sb.set_border_width_all(3)
	sb.border_color = Color(DRAG_HINT_COLOR.r, DRAG_HINT_COLOR.g, DRAG_HINT_COLOR.b, 0.85)
	sb.set_corner_radius_all(3)
	_highlight.add_theme_stylebox_override("panel", sb)
	_highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highlight.visible = false
	drop_zone.add_child(_highlight)


## 拖拽期间每帧看一眼**根视口的拖拽状态**，用它的翻边沿驱动高亮。
##
## 为什么不去接 `card_chip.card_drag_started`：那条信号只有卡牌区在听（`card_area.gd`），
## 而且卡可以从**另一个卡槽**被拖出来 —— 本槽与那张卡未必有从属关系，接不到信号。
## 拖拽状态本来就是视口级的，问视口最不容易漏。代价只是每帧读一个 bool。
## ⚠️ 判据里带上「卡是不是换了」（`_hint_card`）：只看「在拖 / 没在拖」的翻边沿，
##    一旦有谁在拖拽中途换掉载荷，高亮就会停在上一次那张卡的答案上。这条踩过。
func _process(_delta: float) -> void:
	if not get_viewport().gui_is_dragging():
		if _drag_watching:
			_drag_watching = false
			_hint_card = null
			if _highlight != null:
				_highlight.visible = false
		return
	var c := _dragged_card()
	if _drag_watching and c == _hint_card:
		return
	_drag_watching = true
	_hint_card = c
	_refresh_drag_hint()


## 当前拖拽载荷里的卡。不是卡牌拖拽（或还没开始）一律 null。
func _dragged_card() -> CardData:
	var data: Variant = get_viewport().gui_get_drag_data()
	if data is Dictionary and data.has("card"):
		var c: Variant = data["card"]
		if c is CardData:
			return c
	return null


## 按 `_hint_card` 决定本槽亮不亮。冻结态（等待结算）下一律不亮 —— 那时连拖放都被禁了。
func _refresh_drag_hint() -> void:
	if _highlight == null:
		return
	_highlight.visible = _interactive and not _locked and _hint_card != null and accepts(_hint_card)


## 高亮层当前是不是亮着（探针用）。
func is_drag_hint_visible() -> bool:
	return _highlight != null and _highlight.visible


## 配置槽位。槽位标签恒显示槽位名，required 加 *。forbid_tags 为禁止放入的 tag。
## accept_name（D-DOC6）：限定只接受特定名字/ID 的 NPC，空数组=无限制。
## 2026-09-25：`hint` 参数与 JSON 里的 hint 字段已**彻底移除**（历史沿革见 CODE_MAP 触发器条；用户「从来不需要显示 hint」）。
func setup(p_name: String, p_accept: String, p_required: bool, p_forbid_tags: Array = [], p_accept_name: Array = [], p_accept_class: Array = []) -> void:
	slot_name = p_name
	accept = p_accept
	required = p_required
	forbid_tags = _to_string_array(p_forbid_tags)
	accept_name = _to_string_array(p_accept_name)
	accept_class = _to_string_array(p_accept_class)
	name_label.text = "%s%s" % [p_name, " *" if p_required else ""]
	_refresh_view()


## 该卡是否因携带禁止 tag 而被拒（D-F1）。
func is_forbidden(card: CardData) -> bool:
	if card == null or forbid_tags.is_empty():
		return false
	return card.has_tags(forbid_tags, 1)


## 该卡是否因名字不匹配 accept_name 而被拒（D-DOC6）。
func is_name_rejected(card: CardData) -> bool:
	if card == null or accept_name.is_empty():
		return false
	var dn := String(card.display_name)
	var cid := String(card.id)
	for n in accept_name:
		if dn == String(n) or cid == String(n):
			return false
	return true


## 该卡是否因类别不匹配 accept_class 而被拒（书槽只收 book 类，D-DOC18）。
func is_class_rejected(card: CardData) -> bool:
	if card == null or accept_class.is_empty():
		return false
	for cl in accept_class:
		if cl in card.card_class:
			return false
	return true


static func _to_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for v in raw:
			out.append(String(v))
	return out


func _refresh_view() -> void:
	for ch in chip_holder.get_children():
		ch.queue_free()
	var placeholder := drop_zone.get_node("Placeholder") as Label
	if _current != null:
		var scene := chip_scene()
		if scene == null:
			push_error("[CardSlot] card_chip.tscn 取不到，槽位无法显示卡牌")
			return
		var chip := scene.instantiate() as CardChip
		chip.set_card(_current)
		# 已放置的卡可拖出取回；drop_target 指向本卡槽（替换/取回时由其处理放置）
		chip.set_draggable(true)
		chip.origin = self
		chip.drop_target = self
		if _locked:
			chip.set_lock_move(true)   # D-ATTRACT-LOCK：吸附卡禁拖，单击查看保留
		chip_holder.add_child(chip)
		if placeholder != null:
			placeholder.visible = false
		# 放入卡片后隐藏槽名提示标签（如「执行者」）：卡面已能自明，提示不再需要。
		# 用 modulate.a=0 而非 visible=false，避免隐藏后 VBox 重排导致卡槽/卡牌上移（保持布局稳定）。
		name_label.modulate.a = 0.0
	else:
		if placeholder != null:
			placeholder.visible = true
		name_label.modulate.a = 1.0


# ============================================================
#  拖放目标
# ============================================================

## 公开判定：某卡是否可放入本槽（供触发器弹窗「提示态」按 accept/forbid/accept_name/accept_class 过滤手牌）。
## 不含 _interactive 校验（提示态在冻结态下本就由调用方拦截）。
func accepts(card: CardData) -> bool:
	if card == null or not (card is CardData):
		return false
	if is_forbidden(card):
		return false
	if is_name_rejected(card):
		return false
	if is_class_rejected(card):
		return false
	if accept == "" or accept == "*":
		return true
	return card.card_type == accept


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not _interactive:
		return false
	if _locked:
		return false   # D-ATTRACT-LOCK：吸附槽不接受玩家放置（替换 = 把锁死的卡挪走）
	if not (data is Dictionary) or not data.has("card"):
		return false
	var c: CardData = data["card"]
	if not (c is CardData):
		return false
	return accepts(c)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not _interactive:
		return
	if _locked:
		return   # D-ATTRACT-LOCK：同 _can_drop_data，兜底再拦一次
	if not (data is Dictionary) or not data.has("card"):
		return
	var c: CardData = data["card"]
	if not (c is CardData):
		return
	if is_forbidden(c):  # D-F1：保险再拦一次（拖拽载荷可能绕过 _can_drop_data 边界情况）
		push_warning("CardSlot[%s]: 拒绝放入携带禁止标签 %s 的卡" % [slot_name, str(forbid_tags)])
		return
	if is_name_rejected(c):  # D-DOC6：名字不匹配再拦一次
		push_warning("CardSlot[%s]: 拒绝放入名字不匹配 accept_name %s 的卡" % [slot_name, str(accept_name)])
		return
	if is_class_rejected(c):  # D-DOC18：类别不匹配再拦一次
		push_warning("CardSlot[%s]: 拒绝放入类别不匹配 accept_class %s 的卡" % [slot_name, str(accept_class)])
		return
	var origin: Variant = data.get("origin", null)
	# 🔴 替换：槽里原本那张卡不能被静默覆盖。它从手牌来的时候既不在槽里、也没回手牌 =
	#    凭空蒸发（老档里丢了卡就是这个）。先静默送回手牌，再放新卡（2026-10-23 修）。
	# 🔴 2026-10-24 再修：清位必须**先于**下方继承 `origin._from_hand` —— 那条赋值会改写
	#    本槽的 `_from_hand`，若先继承再清位，`_detach_current_to_hand` 读到的是**新卡**的
	#    溯源：被替换的注入卡被当玩家卡塞回手牌（id 撞车时被拒、不撞就是白嫖），而玩家的
	#    新卡落位后 `_from_hand` 已被复位成 false → 关窗被当注入卡吞掉（涂鸦·露易丝槽实测）。
	if _current != null and _current != c:
		_detach_current_to_hand()
	if origin is CardArea and origin.has_method("remove_card"):
		# 从手牌取卡：离开手牌区
		origin.remove_card(c)
		_origin = origin
		_from_hand = true
	elif origin is CardSlot and origin != self and origin.has_method("clear_card"):
		# 在卡槽间移动：来源清空但不回手牌（卡已在另一槽）。
		# 🔴 静默清（不发 card_changed）：那次同步信号会让弹窗立刻重建卡槽，目标槽变僵尸
		#    （2026-10-24 修，详见 clear_card 注释）。`_placed` 残留由弹窗按同实例清扫。
		# 🔴 溯源必须**先取再清**：`clear_card()` 内部会把来源槽的 `_from_hand` 复位成 false，
		#    先调后读永远拿到 false —— 结果「手牌 → A 槽 → 挪到 B 槽」之后这张卡就不再算玩家的，
		#    关窗时被当成注入卡吞掉（2026-10-23 修，与下方 D-HAND2 注释同一件事）。
		var inherited_from_hand: bool = origin._from_hand
		var inherited_origin: Variant = origin._origin
		origin.clear_card(false, true)
		_origin = inherited_origin
		_from_hand = inherited_from_hand   # D-HAND2：溯源跟着卡走，别在换槽时断掉
	# ⚠️ set_card 必须在 if/elif **之外**（与姊妹方法 accept_and_place 一致）。
	# 原先它被缩进在 elif 分支内 ⇒ 「从手牌区拖入」只走 remove_card、never set_card
	# → 卡从手牌消失且卡槽仍空（2026-10-08 修，回归探针 debug/_trig_drag_probe.tscn）。
	if set_card(c):
		# 落位音（设计圣经 §3.6 `ui_card_place_ok`：木桌面「哒」+ 轻微金属尾）。
		# ⚠️ 只挂在**玩家交互路径**（拖放 / 双击）上，不放进 `set_card()` 本身 ——
		#    那个是读档、e2e、初始化也在调的静默 API，放进去会「读档时噼里啪啦」。
		AudioManager.play_sfx("ui_card_place_ok")
		card_changed.emit(slot_name, _current)
		EventSignal.card_placed.emit(slot_name, _current.id, _current.card_type)


## 提示态双击入首卡：若该卡可接受，则放入本槽并从手牌区移除（与拖放路径一致）。
## origin 通常为 CardArea（双击提示态首卡）。内部会把手牌里的卡移除，并广播 card_changed。
## 与 `_drop_data` 同一口径（2026-10-24 修）：先按本槽**自己的** `_from_hand` 清位送回原占卡，
## 再继承来源槽的溯源 —— 顺序反了会让 `_detach_current_to_hand` 读到新卡的标记。
func accept_and_place(card: CardData, origin: Variant) -> bool:
	if _locked:
		return false   # D-ATTRACT-LOCK：吸附槽不接受提示态入卡
	if not accepts(card):
		return false
	if _current != null and _current != card:
		_detach_current_to_hand()   # 替换前先把原来的卡送回手牌，别静默覆盖（2026-10-23 修）
	if origin is CardArea and origin.has_method("remove_card"):
		origin.remove_card(card)
		_origin = origin
		_from_hand = true
	elif origin is CardSlot and origin != self and origin.has_method("clear_card"):
		# 同 `_drop_data`：溯源先取再清（clear_card 会把它复位成 false）；
		# 静默清，理由同 `_drop_data`（2026-10-24 修）。
		var inherited_from_hand: bool = origin._from_hand
		var inherited_origin: Variant = origin._origin
		origin.clear_card(false, true)
		_origin = inherited_origin
		_from_hand = inherited_from_hand   # D-HAND2：溯源跟着卡走
	if set_card(card):
		AudioManager.play_sfx("ui_card_place_ok")
		card_changed.emit(slot_name, _current)
		EventSignal.card_placed.emit(slot_name, _current.id, _current.card_type)
		return true
	return false


func _on_slot_gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	# 左键落在槽位内（空槽或非空槽）一律吞掉事件，阻止冒泡到弹窗背景
	# （否则空槽单击触发提示态后，事件又冒到 Panel → 立刻触发「取消提示态」，互相抵消）。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		if _current == null and not _locked:   # D-ATTRACT-LOCK：锁死槽（含售罄空货槽）不进提示态
			_empty_click_time = Time.get_ticks_msec()
			# 与上一次间隔短 → 视为双击
			if _empty_click_time - _last_empty_click_time <= DOUBLE_CLICK_MS:
				empty_slot_double_clicked.emit(self)
				# 🔴 清零后**不能**再落到下面那句赋值上 —— 原实现把清零写在赋值前一行，
				#    立刻被覆盖成「本次时间」⇒ 防三连击形同虚设，连点三下会触发两次双击
				#    （每次双击都会把首卡塞进槽里）。2026-10-23 修。
				_last_empty_click_time = 0
			else:
				empty_slot_clicked.emit(self)
				_last_empty_click_time = _empty_click_time
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		accept_event()
		if _current != null and not _locked:
			clear_card()   # D-ATTRACT-LOCK：吸附卡不允许右键取走


## 双击判定窗口（毫秒）。
const DOUBLE_CLICK_MS := 320
var _last_empty_click_time := 0
var _empty_click_time := 0


# ============================================================
#  公共 API（静默，兼容 e2e）
# ============================================================

## 静默设置卡（不发信号）。返回 true=成功（类型匹配或空）。
func set_card(card: CardData) -> bool:
	if card == null:
		_current = null
		_from_hand = false
		_refresh_view()
		return true
	if is_forbidden(card):  # D-F1：程序化设卡也拒绝禁止 tag
		return false
	if is_name_rejected(card):  # D-DOC6：程序化设卡也检查 accept_name
		return false
	if is_class_rejected(card):  # D-DOC18：程序化设卡也检查 accept_class
		return false
	if accept != "" and accept != "*" and card.card_type != accept:
		return false
	_current = card
	_refresh_view()
	return true


## 静默摘下当前占用的卡（不发 card_changed）。若它最初是玩家从手牌拖进来的，送回手牌；
## 引擎注入的卡（auto_fill / auto_attract / turn 实例货）直接丢弃 —— 它们本就属于触发器，
## 不该进玩家手牌。
##
## 🔴 为什么需要它（2026-10-23 修的真 bug）：`set_card()` 只是把 `_current` 覆盖掉。
##    往一个**已有卡**的槽再拖一张卡（`accepts()` 不判占用，`_can_drop_data` 也因此放行）时，
##    原来那张卡已经被 `origin.remove_card()` 从手牌摘掉了，覆盖之后就既不在槽里、也不在手牌里
##    —— 玩家的卡凭空蒸发，且没有任何日志。
func _detach_current_to_hand() -> void:
	var prev: CardData = _current
	if prev == null:
		return
	var was_hand := _from_hand
	_current = null
	_from_hand = false
	if not was_hand:
		return
	var target := _hand_target()
	if target != null:
		target.add_card(prev)
	else:
		Player.add_hand_card(prev)   # D-HAND1：没视图也要进账本


## 清空并广播 card_changed(null)。return_to_hand=true 且来源为卡牌区时，把卡归还手牌。
## silent=true：不发 card_changed —— 供「槽 → 槽」移动的来源槽使用：那次同步信号会触发
## TriggerPopup._rebuild_slots 把目标槽**当帧重建**，set_card 落在僵尸节点上、溯源回读读
## 到新实例的 false → 玩家的卡关窗被当注入卡吞掉（2026-10-24 修，涂鸦·露易丝槽实测）。
## 静默清掉的 `_placed` 残留由弹窗 `_on_slot_changed` 的「同实例去重」清扫兜住。
func clear_card(return_to_hand: bool = true, silent: bool = false) -> void:
	var card: CardData = _current
	var was_hand := _from_hand
	_current = null
	_from_hand = false
	_refresh_view()
	if return_to_hand and card != null and was_hand:
		var target := _hand_target()
		if target != null:
			target.add_card(card)
		else:
			Player.add_hand_card(card)   # D-HAND1：没视图也要进账本，否则一次性丢失
	if not silent:
		card_changed.emit(slot_name, null)


func get_card() -> CardData:
	return _current


## D-HAND2（2026-10-14）：这张卡**最初是不是玩家从手牌拖进来的**。
##
## 为什么不直接拿 `_origin is CardArea` 去判：`_origin` 是个对象引用，一旦那张卡牌区视图
## 被切场景销毁，它就成了个已释放引用 —— `is` 判定会直接抛「previously freed instance」，
## 「这张卡归属手牌」这条信息反而随视图一起没了。溯源要的是个**事实**，不是个引用，所以
## 这里存布尔：拖进来 = true、卡槽间移动 = 继承来源槽的值、引擎注入（auto_fill 等）= false。
func did_come_from_hand() -> bool:
	return _from_hand


## 回填溯源标记。display 切换（放卡会触发 `TriggerPopup._rebuild_slots`）会**重建 CardSlot
## 实例**，新实例没人塞过卡，标记是 false —— 不回填的话「这张卡是不是玩家的」这条信息
## 会在第一次刷新时就丢掉，关弹窗时玩家自己的卡会被当成注入卡一样蒸发。
func set_from_hand(v: bool) -> void:
	_from_hand = v


## 取回/下落目标：优先这张卡来时的那张卡牌区；它若已被销毁（切过场景）→ 交给当前登记的
## 那张；连 UI 都不在场 → 直落账本 `Player.hand`（与 `ActionQueue._land` 兜底同口径）。
func _hand_target() -> CardArea:
	# ⚠️ 必须先 `is_instance_valid` 再 `is`：对一个已释放对象做 `is` 判定会直接抛错，
	#    而这恰恰是「玩家在别处换了场景」之后最常见的状态。
	if is_instance_valid(_origin) and _origin is CardArea:
		return _origin as CardArea
	return TriggerManager.get_card_area()


## 冻结/解冻卡槽交互（触发器执行后等待结算期间调用）。
## enabled=false：禁止拖入/拖出/右键取回，并把槽内 CardChip 设为不可拖。
func set_interactive(enabled: bool) -> void:
	_interactive = enabled
	# 冻结时若高亮还亮着，立刻灭掉 —— 锁上之后这个槽不该再摆出「可以放」的样子。
	if not enabled and _highlight != null:
		_highlight.visible = false
	for ch in chip_holder.get_children():
		var chip := ch as CardChip
		if chip != null and chip.has_method("set_draggable"):
			chip.set_draggable(enabled)


## D-ATTRACT-LOCK：锁/解吸附锁。锁上后 chip 禁拖（lock_move）、_can_drop_data /
## _drop_data / 右键取走 / accept_and_place 全被拦；引擎 set_card / clear_card 不受限。
## set_card 新建的 chip 由 _refresh_view 统一回填 lock_move，这里只需刷现存 chip。
func set_locked(v: bool) -> void:
	_locked = v
	for ch in chip_holder.get_children():
		var chip := ch as CardChip
		if chip != null:
			chip.set_lock_move(v)


## 本槽是否处于吸附锁（探针/调试用）。
func is_locked() -> bool:
	return _locked
