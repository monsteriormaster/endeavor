## 触发器弹窗组件 —— 标题 + 左卡槽（从外部卡牌区拖卡进入）+ 右文本 + 执行 / 关闭。
## 浮动小窗（约 560x460，居中，无全屏遮罩以免遮挡卡牌区），长按标题栏(>350ms)或拖动移动整个弹窗。
## setup(trigger_id) 加载触发器、进首 turn 的 require:null phase。
## 从卡牌区拖卡进槽 → 重选 display → 重建槽位（保留同名已放卡）→ 更新文本（{槽位}替换 + x/needs/verdict）。
## 执行：内联 compare → 应用 effect（TriggerManager.apply_effect）→ 路由下一 turn/phase。
## 路由逻辑：phase.ending → harvest/fail_harvest → 提交流程字典并关闭；
##           否则 find_next_turn → 下一 phase（保留流程字典）或流程结束（提交并关闭）。
## tag 隔离：流程中获得的 tag 只进 TriggerManager 流程字典，不直接写 Player.player_tags；
##          全流程结束（_finish_flow）才提交并清空。中途关闭（close）则丢弃（cancel_flow）。
## 卡牌归属：卡从卡牌区拖入卡槽时即从手牌移除；只有「关闭弹窗」时才通过 cards_returned 归还手牌
##           （执行结果出现后卡仍留在槽位，待用户关闭触发器后才回卡牌区）。
class_name TriggerPopup
extends Control

## 全流程结束时广播：trigger_id + 是否可重复（供 TriggerSpot 决定是否禁用自身）+ 是否成功（非 fail_harvest 结局）。
signal flow_completed(trigger_id: String, repeatable: bool, success: bool)
## 已放卡牌归还手牌时广播（参数：本次归还的卡数据，**观察者信号**）。
## D-HAND2：归还动作本身由本弹窗完成（`_return_to_hand`），只派这一个入口，避免双份。
signal cards_returned(cards: Array[CardData])
signal book_acquired(card: CardData)
## 注：结算结束需播放剧情（D-C2）的信号统一在 TriggerManager.plot_requested 上广播，
## 由 TriggerManager 内部路由到 PlotImporter.play_by_key（键名 → 文件见 dialogue_registry.json）。
## 本组件在 _finish_flow 中直接 emit TriggerManager.plot_requested，不单独持有该信号。

const SLOT_SCENE := preload("res://components/card_slot.tscn")
const TextVars := preload("res://script/text_vars.gd")
const LONG_PRESS_MS := 350
const DRAG_THRESHOLD := 6.0
const BOOKS_PATH := "res://resoures/items/books.json"
## ---- 犹格索托斯之所（2026-10-16）----
## 书架读尽标记：由 ReadBookTriggerPopup 在读完 books.json 最后一本时授予（player_tags）。
## 本文件只读不写：书店购书「闭店」display 的门控、`_compute_bookshop_result` 的闭店早退都认它。
const ALL_BOOKS_TAG := "书肆读尽"
## 闭店状态 tag：玩家在闭店后去书店、看到老板收摊那一刻落。是「调查书店」的 show_when 门控。
const BOOKSHOP_CLOSED_TAG := "书店关闭"
## 白桦书肆剧情文件（闭店剧情「书店关闭」与调查剧情「银之匙」都在这里）。
const BOOKSHOP_PLOT := "res://resoures/plot/rite/书店.json"
const GRID_COLS := 4                        # 九宫格列数（上四 / 下四）
const SLOT_W := 90.0                        # 卡槽宽（与 DropZone 一致）
const SLOT_H := 159.0                       # 卡槽高（与 DropZone 一致，与 card.png 367:648 比例贴合）
const LABEL_H := 18.0                       # 槽名标签估算高
const LABEL_SEP := 4.0                       # 标签与黑方块间距
const DEFAULT_ORDER := [1, 2, 3, 4, 5, 6, 7, 8, 9]  # 默认填充顺序：上四→下四→第9中央

# ============================================================
#  判定读数开关（2026-10-14 用户口径：把「不合理的结算语言」关掉）
# ============================================================
## false = 正式表现。`PhaseLabel` 那一行只写玩家看得懂的中文阶段名，
## 不出现 phase: / 🎲 / 📐 / x= / v= / needs= / 判定= 这些开发期读数；
## 右栏「执行结果」表头也不再拼内部结果键（suc0 / suc1）。
## 要在编辑器里定位判定链路时改成 true，六处读数一起回来。
const SHOW_DEBUG_READOUT := false

# ============================================================
#  外观（A 套：纸 + 铜 + 墨。2026-10-01 从 B 套深墨紫收口过来）
# ============================================================
## 底部按钮的字色（纸片样式自 2026-10-06 起由 Autoload `ButtonSkin` 统一提供，见 `_style_buttons`）。
const BTN_INK := Color(0.180, 0.141, 0.094)             # #2E2418，与全局墨色同族
const BTN_DISABLED_INK := Color(0.420, 0.380, 0.330)
## 纸面板素材（`trig_panel.png`）四周留的透明边，与 `make_trig_assets.py` 的 PAD 一致。
## 底部按钮栏必须自己让开它 —— 旧值 12px 比这个还小，按钮会压出纸面（实测超出 6px）。
const EDGE_MARGIN: float = 30.0
## 2026-09-25：槽位 hint **已彻底移除**——不再有 SLOT_HINTS_VISIBLE 开关，
## JSON 里的 slots.*.hint 字段与 CardSlot 的 hint 参数均已删除，槽位标签恒显示槽位名。

# ============================================================
#  布局（在 Inspector 改这些即可调整各区块的相对位置，无需动场景树）
#  - 左"卡槽区"固定在 Content 左侧，宽为 slot_section_width
#  - 右"文本区"固定在 Content 右侧，宽为 text_section_width
#  - 中间留白 = Content 总宽 - 两者宽 - 两侧 padding
#  Content 改为绝对定位 Control，SlotsSection/TextSection 用锚点+偏移定位，
#  故可自由拖拽或在下方直接调数值。
# ============================================================
@export_group("布局 / 相对位置")
@export var layout_padding: float = 16.0        # 左右两区到 Content 边缘的内边距
@export var content_top_pad: float = 8.0        # 两区到 Content 顶部的间距
@export var content_bottom_pad: float = 8.0     # 两区到 Content 底部的间距
@export var slot_section_width: float = 392.0   # 左侧卡槽区宽度（需 ≥ 4 列卡槽宽 ≈ 392）
@export var text_section_width: float = 380.0   # 右侧文本区宽度
@export var slot_block_gap: float = 6.0         # 卡槽标题与卡槽列表的间距
@export var text_block_gap: float = 6.0         # 详情标题与正文的间距
@export var slot_inner_gap: float = 8.0         # 卡槽之间的间距


@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/TitleBar/Title
@onready var title_bar: Control = $Panel/TitleBar
@onready var phase_label: Label = $Panel/PhaseLabel
@onready var slots_grid: Control = $Panel/Content/SlotsSection/SlotsGrid
@onready var text_label: Label = $Panel/Content/TextSection/TextLabel
@onready var text_title: Label = get_node_or_null("Panel/Content/TextSection/TextTitle")
@onready var execute_btn: Button = $Panel/BottomBar/ExecuteButton
@onready var close_btn: Button = $Panel/BottomBar/CloseButton
@onready var cancel_btn: Button = $Panel/BottomBar/CancelButton
@onready var content: Control = $Panel/Content
@onready var slots_section: Control = $Panel/Content/SlotsSection
@onready var text_section: Control = $Panel/Content/TextSection
@onready var bottom_bar: HBoxContainer = $Panel/BottomBar
# 编辑器内放置的三个「位置标记」Control（触发器名 / 卡槽存放的位置 / 文字位置）。
# 运行时仅作定位参照（本身无样式、不可见）；popup 内容对齐到这些标记。
@onready var marker_title: Control = $Panel/触发器名
@onready var marker_slots: Control = $Panel/卡槽存放的位置
@onready var marker_text: Control = $Panel/文字位置

var _expanded: Dictionary = {}
var _trigger_id: String = ""
var _turn_id: String = ""
var _phase: Dictionary = {}
var _phase_name: String = ""
var _slots: Array[CardSlot] = []
var _placed: Dictionary = {}  # slot_name -> CardData
## D-HAND2（2026-10-14）：每个槽位的**溯源标记**（slot_name -> bool：这张卡最初是不是
## 玩家从手牌拖进来的）。
## `_placed` 里的卡不都是玩家的 —— 上排「理性/感性/知觉」这类是配置里 auto_fill /
## auto_attract 注入的指示牌，玩家手上从来没有它们。旧实现 `_return_cards` 无差别归还
## `_placed` 全体，于是「取消一次送学就白得三张指示牌」。标记必须是**布尔**而不是
## 「来源对象」：卡牌区是场景内节点，视图一销毁对象引用就废了，而这条事实还在。
var _slot_from_hand: Dictionary = {}
var _returned := false  # 防止 cards_returned 重复广播
var _flow_failed := false  # 全流程是否以 fail_harvest 结局（供 success 判定）
## 同步流程是否已真正执行过（按过「执行」且结算成立、进入快照消耗那一刻置位）。
## 消耗品的「不归还」只在执行后成立 —— 没执行就关窗（执行被锁 / 缺必填槽 / 直接点关），
## 放进槽里的消耗品必须原样回手牌，否则等于凭空没收（2026-10-24 修：放在上面的卡关窗后消失）。
var _executed := false

## D-ATTRACT-HOLD（2026-10-24）：吸附（auto_attract / 回合实例上槽）的卡，若玩家手牌里
## 恰好有**同 id** 的卡，暂时从卡牌区摘下 —— 槽里一张、手牌再亮一张 = 视觉上凭空两份，
## 且玩家还能把手牌这张拖去别的槽凑出第二份。摘下的卡在关窗/销毁时**无条件**归还：
## 槽里那张是池卡（关闭即蒸发、被消耗也是消耗池卡），手牌这张是玩家自己的财产，两不相干。
var _attract_held: Array[CardData] = []
var _attract_held_returned := false
## D-ATTRACT-LOCK（2026-10-24）：被吸附占用的槽名集合。卡槽实例每次 _refresh 都会重建，
## 锁状态必须记在弹窗这层、按槽名回填（否则刷新一次锁就丢了）。槽空出（被买走/消耗）时擦除。
var _locked_slots: Dictionary = {}

# 拖拽移动状态
var _dragging := false
var _drag_long_pressed := false
var _drag_offset := Vector2.ZERO
var _press_pos := Vector2.ZERO
var _press_time := 0

# 书籍注册表缓存（resoures/items/books.json），首次读取后复用。
var _books_cache: Dictionary = {}
var _books_cache_ready := false

# 异步等待流程状态：_frozen=执行后冻结（仅取消/关闭可点）；_pending_result=已算出但未落地的统一结算字典。
var _frozen := false
var _pending_result: Dictionary = {}


func _ready() -> void:
	execute_btn.pressed.connect(_on_execute)
	close_btn.pressed.connect(close)
	cancel_btn.pressed.connect(_on_cancel)
	title_bar.gui_input.connect(_on_title_gui_input)
	panel.gui_input.connect(_on_popup_background_gui_input)
	execute_btn.disabled = true
	cancel_btn.visible = false
	_style_buttons()
	_center_panel()
	_apply_layout()
	# 文字大小：跟随全局设置（与对话框正文一致），并监听滑块联动。
	_apply_text_font_size()
	if Settings.text_font_size_changed.connect(_on_text_font_size_changed) != OK:
		push_warning("TriggerPopup: 连接 Settings 文字大小信号失败")


## 底部三个按钮（执行 / 关闭 / 取消）的**字色 + 纹理过滤**。
##
## ▍纸片样式自 2026-10-06 起**不再在这里设** —— 全工程按钮统一由 Autoload `ButtonSkin`
##   按尺寸套 `art/ui/btn_paper_{l,s}.png` 九宫格（88x44 落在大档）。
##   ⚠️ 再在这里 `add_theme_stylebox_override` 会把全局皮顶掉（本函数在 `_ready` 里跑，
##      晚于 ButtonSkin 的 node_added）—— 那就是「又长出第二套皮」的入口。
func _style_buttons() -> void:
	for b: Button in [execute_btn, close_btn, cancel_btn]:
		if b == null:
			continue
		# 全局 default_texture_filter = NEAREST，九宫格的细描边必须单独开 LINEAR。
		b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		b.add_theme_color_override("font_color", BTN_INK)
		b.add_theme_color_override("font_hover_color", BTN_INK)
		b.add_theme_color_override("font_pressed_color", BTN_INK)
		b.add_theme_color_override("font_disabled_color", BTN_DISABLED_INK)


func _center_panel() -> void:
	var vp := get_viewport_rect().size
	panel.position = (vp - panel.size) / 2.0


## 把右侧正文文字大小设为全局设置的字号（与对话框正文保持一致）。
func _apply_text_font_size() -> void:
	if text_label != null:
		text_label.add_theme_font_size_override("font_size", Settings.text_font_size)


func _on_text_font_size_changed(_size: int) -> void:
	_apply_text_font_size()


## 按编辑器里放置的三个「位置标记」Control，把 标题 / 卡槽区 / 文本区 绝对定位到对应标记处。
## 标记现已改为 Panel 的子节点，因此标记的 position 就是 Panel 本地坐标；运行时将内容节点的
## global_position 直接对齐到标记的 global_position，即可保证无论 Panel 如何居中/拖动，内容都
## 稳稳落在背景图的对应区域。
## 改标记的位置即可调整相对位置（在编辑器里拖那三个 Control），无需动布局代码。
func _apply_layout() -> void:
	if marker_title == null or marker_slots == null or marker_text == null:
		_apply_layout_legacy()
		return

	# 标题栏组（标记的 position 即 Panel 本地坐标）
	_place_in_panel(title_bar, marker_title.position, Vector2(420, 34))
	# phase 行：紧随标题下方
	_place_in_panel(phase_label, marker_title.position + Vector2(0, 36), Vector2(420, 18))

	# 卡槽区：宽度/高度限制在面板内
	var slots_w := minf(slot_section_width, panel.size.x - marker_slots.position.x - 8.0)
	var slots_h := minf(panel.size.y - marker_slots.position.y - 60.0, maxf(320.0, panel.size.y - marker_slots.position.y - 70.0))
	_place_in_panel(slots_section, marker_slots.position, Vector2(slots_w, slots_h))

	# 文本区：同样限制在面板内（默认落在右栏 marker_text 处）
	_layout_text_region(marker_text.position)

	# 底部按钮栏：固定在面板底部右侧（边距避开纸沿的透明边）
	var bb_size := bottom_bar.size if bottom_bar.size.x > 0 else Vector2(180, 36)
	_place_in_panel(bottom_bar,
			Vector2(panel.size.x - bb_size.x - EDGE_MARGIN, panel.size.y - bb_size.y - EDGE_MARGIN),
			bb_size)

	# 标记仅作编辑器参照（本身无样式已不可见），显式隐藏避免误显示
	marker_title.visible = false
	marker_slots.visible = false
	marker_text.visible = false

	# 卡槽九宫格内部尺寸仍由变量驱动
	_slots_grid_size()


## 把节点定位在 Panel 本地坐标 pos（左上角）处，并指定尺寸。
func _place_in_panel(node: Control, pos: Vector2, size: Vector2) -> void:
	if node == null:
		return
	# 重置锚点，避免父级或自动布局干扰
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 0.0
	node.anchor_bottom = 0.0
	node.global_position = panel.global_position + pos
	node.size = size


## 把「文本区」放到 Panel 本地坐标 pos 处，宽度铺到面板右缘（限制在面板内），
## 并处理区内部布局（有标题则标题置顶、正文填剩余；无标题则正文填满）。
## 供双栏默认布局（marker_text）与无卡槽全宽布局（marker_slots 起）共用。
func _layout_text_region(pos: Vector2) -> void:
	if text_section == null:
		return
	var text_w := maxf(120.0, panel.size.x - pos.x - 16.0)
	var text_h := maxf(200.0, panel.size.y - pos.y - 70.0)
	_place_in_panel(text_section, pos, Vector2(text_w, text_h))
	if text_title != null:
		text_title.position = Vector2.ZERO
		text_title.size = Vector2(text_w, 22)
	if text_label != null:
		if text_title != null:
			text_label.position = Vector2(0, 26)
			text_label.size = Vector2(text_w, maxf(60.0, text_h - 30))
		else:
			text_label.position = Vector2.ZERO
			text_label.size = Vector2(text_w, maxf(60.0, text_h))


## 无卡槽「亲历」display（slots 为空，如剧院看剧）→ 隐藏左侧卡槽区、正文从原卡槽区左缘铺到右缘；
## 有卡槽 display → 显示卡槽区、正文回右栏。每次选中 display 后调用，保证无卡槽触发器看起来**没有任何卡槽**。
func _sync_slot_region(display: Dictionary) -> void:
	if slots_section == null or marker_slots == null or marker_text == null:
		return
	var has_slots: bool = not ((display.get("slots", {}) as Dictionary).is_empty())
	slots_section.visible = has_slots
	if has_slots:
		_layout_text_region(marker_text.position)
	else:
		# 左缘略下移避开 phase 行，从原卡槽区起点起铺满至面板右缘
		_layout_text_region(marker_slots.position + Vector2(0, 14))


## 九宫格内部尺寸：依 SLOT_W/H 与间距变量算出 SlotsGrid 的本地包围盒。
func _slots_grid_size() -> void:
	if slots_grid == null:
		return
	slots_grid.offset_left = 0.0
	slots_grid.offset_top = 26.0
	var cell_w: float = SLOT_W + slot_inner_gap
	var cell_h: float = SLOT_H + LABEL_H + LABEL_SEP
	var grid_w: float = GRID_COLS * SLOT_W + (GRID_COLS - 1) * slot_inner_gap
	var grid_h: float = 2.0 * cell_h + slot_inner_gap
	slots_grid.offset_right = grid_w
	slots_grid.offset_bottom = 26.0 + grid_h


## 旧版：靠 export 变量把左卡槽区 / 右文本区定位（标记缺失时回退用）。
func _apply_layout_legacy() -> void:
	if slots_section == null or text_section == null or content == null:
		return
	var slots_h := maxf(320.0, panel.size.y - content_top_pad - 70.0)
	var text_h := maxf(200.0, panel.size.y - content_top_pad - 70.0)
	_place_in_panel(slots_section, Vector2(layout_padding, content_top_pad), Vector2(slot_section_width, slots_h))
	_place_in_panel(text_section, Vector2(panel.size.x - layout_padding - text_section_width, content_top_pad), Vector2(text_section_width, text_h))
	if text_title != null:
		text_title.position = Vector2.ZERO
		text_title.size = Vector2(text_section_width, 22)
	if text_label != null:
		if text_title != null:
			text_label.position = Vector2(0, 26)
			text_label.size = Vector2(text_section_width, maxf(60.0, text_h - 30))
		else:
			text_label.position = Vector2.ZERO
			text_label.size = Vector2(text_section_width, maxf(60.0, text_h))


## 九宫格中第 pos(1-9) 个槽位的本地坐标（相对 SlotsGrid 左上角）。
## 1-4=上排左→右，5-8=下排左→右，9=右列、上下两排正中。
func _slot_grid_pos(pos: int) -> Vector2:
	var cell_w: float = SLOT_W + slot_inner_gap
	var cell_h: float = SLOT_H + LABEL_H + LABEL_SEP
	if pos == 9:
		var grid_h: float = 2.0 * cell_h + slot_inner_gap
		return Vector2(3.0 * cell_w, (grid_h - cell_h) / 2.0)
	var idx: int = pos - 1
	var col: int = idx % GRID_COLS
	var row: int = idx / GRID_COLS
	return Vector2(col * cell_w, row * cell_h)


func close() -> void:
	# 关闭弹窗前：取消可能激活的提示态（还原手牌顺序/视觉），并清空活动弹窗引用。
	TriggerManager.set_active_trigger_popup(null)
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null and ca.is_hint_active():
		ca.cancel_hint()
	# 冻结态（已执行未结算）：关闭 = 提交为"进行中"行动，占用卡不归还。
	if _frozen:
		_commit_action()
		return
	_return_cards()
	TriggerManager.cancel_flow()
	# 统一从覆盖层管理器出栈（内部会 queue_free）；未被托管时自行销毁
	if not OverlayRoot.close_overlay(self):
		queue_free()


## 初始化触发器。返回 false=未找到/校验失败。
func setup(trigger_id: String) -> bool:
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	if raw.is_empty():
		# 开发信息走 stderr，弹窗里只说玩家能看懂的一句（2026-10-14）。
		push_warning("[TriggerPopup] 未找到触发器：%s" % trigger_id)
		text_label.text = "这一项暂时打不开。"
		return false
	_trigger_id = trigger_id
	TriggerManager.begin_flow()
	# D-DOC24：回合级触发器（init_scope="turn"）确保本回合实例已生成（幂等兜底，正常已由
	# 回合边界 TriggerManager.advance_turn 生成）。静态触发器本方法直接返回。
	TriggerManager.initialize_for(trigger_id)
	_expanded = TriggerLoader.expand(raw)
	var errs: Array = TriggerLoader.validate(_expanded)
	if not errs.is_empty():
		# 校验详情只给开发（stderr），不铺到弹窗正文里。
		push_error("[TriggerPopup] 配置校验错误（%s）：%s" % [trigger_id, str(errs)])
		text_label.text = "这一项暂时打不开。"
		return false
	title_label.text = String(_expanded.get("title", trigger_id))
	# 方案 B（2026-10-16 用户拍板）：打开弹窗前，把手牌里的**角色卡**按 id 从 `Player.npc`
	# 重建一遍 —— 这让后续 `forbid_tags` 等判定只认 `Player.npc` 一份真值：上次触发器结算
	# 写入角色条目的「受伤」等 tag，会在这里反映到玩家手上那张卡上（否则卡实例还是进手牌
	# 那一刻的快照，槽位会放进一个「数据里已受伤、卡面却干净」的人）。
	# 卡牌区不在场（纯逻辑探针 / 无主 UI 的流程）时 `get_card_area()` 返回 null，静默跳过。
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null:
		ca.refresh_from_source()
	_enter_first_phase()
	return true


func _enter_first_phase() -> void:
	var turns: Dictionary = _expanded.get("turns", {})
	if turns.is_empty():
		return
	_turn_id = String(turns.keys()[0])
	var turn: Dictionary = turns[_turn_id]
	for ph in turn.get("phases", []):
		var phase: Dictionary = ph
		if phase.get("require", "___") == null:
			_phase = phase
			_phase_name = String(phase.get("phase", ""))
			break
	_refresh()


func _refresh() -> void:
	var display: Dictionary = TriggerLoader.select_display(_phase, _placed, TriggerManager.get_routing_tags())
	if display.is_empty():
		push_warning("[TriggerPopup] 无匹配 display：turn=%s phase=%s" % [_turn_id, _phase_name])
		text_label.text = "现在还不能做这件事。"
		execute_btn.disabled = true
		return
	_sync_slot_region(display)
	_rebuild_slots(display)
	_update_text(display)


func _rebuild_slots(display: Dictionary) -> void:
	for s in _slots:
		s.queue_free()
	_slots.clear()
	var slots: Dictionary = display.get("slots", {})
	var positions: Array = display.get("slot_positions", [])
	var slot_names: Array = slots.keys()
	var attracted_ids: Array = []  # D-DOC23：本次重建已吸附的卡 id（跨槽去重）
	for i in slot_names.size():
		var slot_name = slot_names[i]
		var cfg: Dictionary = slots[slot_name]
		var pos: int = int(DEFAULT_ORDER[i]) if i >= positions.size() else int(positions[i])
		if pos < 1 or pos > 9:
			pos = int(DEFAULT_ORDER[i])
		var inst: CardSlot = SLOT_SCENE.instantiate() as CardSlot
		inst.custom_minimum_size = Vector2(SLOT_W, SLOT_H + LABEL_H + LABEL_SEP)
		inst.position = _slot_grid_pos(pos)
		slots_grid.add_child(inst)
		inst.setup(
			String(slot_name),
			String(cfg.get("accept", "")),
			bool(cfg.get("required", false)),
			cfg.get("forbid_tags", []),
			cfg.get("accept_name", []),
			cfg.get("accept_class", [])
		)
		inst.card_changed.connect(_on_slot_changed)
		# 提示态：空槽单击进入、双击入首卡（仅在空槽发出，非空槽由卡面 chip 处理）。
		inst.empty_slot_clicked.connect(_on_empty_slot_clicked)
		inst.empty_slot_double_clicked.connect(_on_empty_slot_double_clicked)
		# D-DOC24：回合级触发器里由**实例管理**的槽（带 auto_attract 声明，如杂货店货一~三）
		# 内容只由回合实例决定——不从 _placed 恢复、不做现场吸附。实例无货（池不足）或该卡本
		# 回合已消耗（被买走）→ 空位，并清掉可能残留的已放记录，保持 _placed 与 UI 一致
		# （否则会出现「槽位空着却仍能按价成交」的幻影货）。
		var instance_managed: bool = TriggerLoader.is_turn_scoped(_trigger_id) \
			and not TriggerLoader.attract_spec(cfg).is_empty()
		if instance_managed:
			var inst_id := String(TriggerManager.get_turn_instance(_trigger_id).get(String(slot_name), ""))
			if inst_id != "" and not TriggerManager.is_consumed(_trigger_id, inst_id):
				var inst_card: CardData = CardRegistry.get_card(inst_id)
				if inst_card != null and inst.set_card(inst_card):
					_placed[String(slot_name)] = inst_card
					_hold_hand_copy_of(inst_card)
					_locked_slots[String(slot_name)] = true   # D-ATTRACT-LOCK
					inst.set_locked(true)
				else:
					_placed.erase(String(slot_name))
					_locked_slots.erase(String(slot_name))
			else:
				_placed.erase(String(slot_name))
				_locked_slots.erase(String(slot_name))
		elif _placed.has(String(slot_name)):
			inst.set_card(_placed[String(slot_name)])
			# D-HAND2：连同溯源标记一起回填 —— 否则这条信息在第一次刷新时就丢了，
			# 关窗时玩家自己的卡会被当成注入卡一样蒸发。
			inst.set_from_hand(bool(_slot_from_hand.get(String(slot_name), false)))
			inst.set_locked(bool(_locked_slots.get(String(slot_name), false)))   # D-ATTRACT-LOCK 回填
		# D-DOC7（2026-08-24）：auto_fill —— 固定 NPC 自动入槽。
		# 程序化 set_card（绕过拖放，但仍过 accept/forbid 校验）。
		# 🔴 2026-10-16（方案 B 同批）：改走 `hand_card_for_id`（按 id 取**实时源**：主角 /
		#    `Player.npc` 条目现场造卡），查不到才回落注册表静态卡。原实现直接吃
		#    `CardRegistry.get_card` 的**共享静态实例** ⇒ auto_fill "Hero" 拿到的是预设卡：
		#    名字是模板名（不是玩家取的名字）、属性是预设值，与 `Player.npc` 真值两套。
		var auto_fill_v: Variant = cfg.get("auto_fill", null)
		if auto_fill_v is String and auto_fill_v != "" and not _placed.has(String(slot_name)):
			var auto_card: CardData = EffectProcessor.hand_card_for_id(String(auto_fill_v))
			if auto_card != null:
				if inst.set_card(auto_card):
					_placed[String(slot_name)] = auto_card
					_hold_hand_copy_of(auto_card)   # D-ATTRACT-HOLD：auto_fill 同口径——手牌同 id 暂时摘走（全场只能有一张）
					_locked_slots[String(slot_name)] = true   # D-ATTRACT-LOCK：auto_fill 固定 NPC 同口径锁死
					inst.set_locked(true)
			else:
				push_warning("TriggerPopup: auto_fill NPC '%s' 未在实时源/注册表中找到" % String(auto_fill_v))
		# —— 槽位自动上卡（D-DOC24，非实例管理的槽）——
		# auto_attract 现场吸附——字符串 = 按 tag（D-DOC13 越狱支援）/ 对象 {class, exclude_sold}
		# = 按物品 class（D-DOC23 商品池）。抽取走 Player.make_rng **确定性**（同局同天恒定、
		# 读档重来同结果，反 SL）；跨槽去重 + 排除本回合已消耗。
		if not instance_managed and not _placed.has(String(slot_name)):
			var spec: Dictionary = TriggerLoader.attract_spec(cfg)
			if not spec.is_empty() and not _slot_attract_locked(String(slot_name)):
				var exclude: Array = attracted_ids.duplicate()
				# D-UNIQ（2026-10-24）：已放在其他槽的卡不参与抽取——「同一张卡只出现一份」
				# 的跨槽去重，从吸附卡之间扩展到吸附 vs 玩家已放卡。
				for p_sn in _placed:
					var p_card: CardData = _placed[p_sn]
					if p_card != null and not (p_card.id in exclude):
						exclude.append(p_card.id)
				if bool(spec.get("exclude_sold", false)):
					exclude.append_array(TriggerManager.consumed_ids(_trigger_id))
				var attracted: CardData = _attract_card(
					String(spec.get("tag", "")),
					String(cfg.get("accept", "")),
					spec.get("classes", []),
					exclude,
					"attract:%s:%s" % [_trigger_id, String(slot_name)]
				)
				if attracted != null:
					if inst.set_card(attracted):
						_placed[String(slot_name)] = attracted
						attracted_ids.append(attracted.id)
						_hold_hand_copy_of(attracted)
						_locked_slots[String(slot_name)] = true   # D-ATTRACT-LOCK
						inst.set_locked(true)
		_slots.append(inst)
	# 设计约定：第9卡槽（右列、上下两排正中）与「上4 / 下4」（pos 4 / 8，同处右列）互斥。
	# 注意只与 4/8 冲突，而非与 1-8 全体冲突——杂货店的 [1,2,3,5,6,7,9] 是合法布局
	# （4/8 空出，第9槽独占右列），旧写法对 1-8 全扫导致误报刷屏（2026-09-13 修正）。
	var used_positions: Dictionary = {}
	for i in slot_names.size():
		var p: int = int(DEFAULT_ORDER[i]) if i >= positions.size() else int(positions[i])
		if p >= 1 and p <= 9:
			used_positions[p] = true
	if used_positions.has(9) and (used_positions.has(4) or used_positions.has(8)):
		push_warning("TriggerPopup: 第9卡槽与 上4/下4 同时出现（设计约定互斥），请检查该 display 的 slot_positions")
	# 清掉新 display 没有的槽位的已放卡
	var to_remove: Array = []
	for sn in _placed.keys():
		if not slots.has(sn):
			to_remove.append(sn)
	for sn in to_remove:
		_placed.erase(sn)
		_locked_slots.erase(sn)


## 子类钩子（D-DOC23 神秘杂货店）：该槽位本次会话禁止再吸附。
## 仅对**非回合级**触发器的 auto_attract 生效（回合级走实例读取，已由「已消耗」过滤空位）。
func _slot_attract_locked(_slot_name: String) -> bool:
	return false


## 吸附一张卡（薄封装 → TriggerLoader.attract_card，池构建与抽取的**单一来源**在 TriggerLoader）。
## D-DOC24：抽取走 Player.make_rng 确定性——同局 + 同天 + 同 seed_key → 同结果
## （消除「同一回合内重开/放卡就重抽」，读档重来也刷不动）。
## seed_key 省略 → "attract:<触发id>"（调用方一般显式传 "attract:<触发id>:<槽名>"）。
func _attract_card(tag: String, accept: String, classes: Array = [], exclude_ids: Array = [],
		seed_key: String = "") -> CardData:
	var key := seed_key if seed_key != "" else "attract:%s" % _trigger_id
	return TriggerLoader.attract_card(tag, accept, classes, exclude_ids, key)


## 把 Player.npc 条目映射回一张角色卡（薄封装 → TriggerLoader.npc_entry_to_card）。
func _card_of_npc_entry(key: String, entry: Dictionary) -> CardData:
	return TriggerLoader.npc_entry_to_card(key, entry)


func _on_slot_changed(slot_name: String, card: CardData) -> void:
	if card == null:
		_placed.erase(slot_name)
		_slot_from_hand.erase(slot_name)
	else:
		_placed[slot_name] = card
		# D-HAND2：溯源必须在**这条信号里**抓 —— 卡槽此刻刚记下它是怎么来的
		# （拖入=来自手牌、卡槽间移动=继承来源槽、程序注入=false）。
		_slot_from_hand[slot_name] = _slot_came_from_hand(slot_name)
		# 同一卡实例只允许占一个槽：来源槽静默清空（不发 card_changed，见 CardSlot.clear_card
		# 2026-10-24 注）后，这里按实例把旧槽的 `_placed` / 溯源残留清掉。
		for sn in _placed.keys():
			if sn != slot_name and _placed[sn] == card:
				_placed.erase(sn)
				_slot_from_hand.erase(sn)
		# D-UNIQ（2026-10-24）：同 id 只允许一份——不同实例的同 id 卡（吸附池卡 vs 玩家手牌卡）
		# 落槽时，把**后放的这张**退回手牌并清槽（先放的通常是引擎注入的固定 NPC，不动）。
		# 不做这层，露易丝线涂鸦会出现「槽里吸附一个露易丝 + 手牌再拖进来一个露易丝」。
		for sn in _placed.keys():
			if sn != slot_name and _placed[sn] is CardData and _placed[sn] != card \
					and _placed[sn].id == card.id:
				_placed.erase(slot_name)
				_slot_from_hand.erase(slot_name)
				for s in _slots:
					if s.slot_name == slot_name:
						s.set_card(null)   # 静默（set_card 不发信号），不会再触发本回调
						break
				_return_to_hand([card])
				AudioManager.play_sfx("ui_card_reject")
				break
	_refresh()


## 取某槽位当前记录的溯源标记（找不到该槽 → false）。
func _slot_came_from_hand(slot_name: String) -> bool:
	for s in _slots:
		if s.slot_name == slot_name:
			return s.did_come_from_hand()
	return false


## 空槽左键单击 → 进入提示态（把可选卡按排序聚到最左、首卡高亮）。冻结态不触发。
func _on_empty_slot_clicked(slot: CardSlot) -> void:
	if _frozen:
		return
	var ca: CardArea = TriggerManager.get_card_area()
	if ca == null:
		return
	ca.begin_hint(slot, get_current_priority_attrs())


## 空槽左键双击 → 把首卡入槽、其余还原（提示态结束）。冻结态不触发。
func _on_empty_slot_double_clicked(slot: CardSlot) -> void:
	if _frozen:
		return
	var ca: CardArea = TriggerManager.get_card_area()
	if ca == null:
		return
	ca.end_hint(true)


## 点击弹窗背景（面板）/ 标题 / 文本区等「卡槽、卡牌区、卡以外」的位置 → 取消提示态（还原）。
## 槽位内点击已在 CardSlot._on_slot_gui_input 里 accept_event() 吞掉，不会冒泡到这里。
func _on_popup_background_gui_input(_event: InputEvent) -> void:
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null and ca.is_hint_active():
		ca.cancel_hint()


## 取当前 phase 的「数值排序属性上下文」：按声明顺序收集 check.attrs / dice_attrs / conditions.attrs
## 的属性名，去重。供卡牌区「整理」按钮与提示态对人物卡按数值区间档排序（声明序=主次，先声明为主）。
func get_current_priority_attrs() -> Array:
	var out: Array = []
	var display: Dictionary = TriggerLoader.select_display(_phase, _placed, TriggerManager.get_routing_tags())
	var check_v: Variant = display.get("check", null)
	if not (check_v is Dictionary):
		return out
	var check: Dictionary = check_v
	# 1) check.attrs（{attr: weight}）
	var attrs_d: Dictionary = check.get("attrs", {})
	for an in attrs_d.keys():
		var s := String(an)
		if s != "" and not out.has(s):
			out.append(s)
	# 2) check.dice_attrs（[attr,...]）
	var dice_attrs: Array = check.get("dice_attrs", [])
	for an in dice_attrs:
		var s := String(an)
		if s != "" and not out.has(s):
			out.append(s)
	# 3) check.conditions.attrs（{attr: ...}）
	var cond_v: Variant = check.get("conditions", null)
	if cond_v is Dictionary:
		var cond_d: Dictionary = (cond_v as Dictionary).get("attrs", {})
		for an in cond_d.keys():
			var s := String(an)
			if s != "" and not out.has(s):
				out.append(s)
	return out


## 把指定 id 的卡从槽位里**就地抹掉**（不归还手牌、不发 card_changed）。
##
## 给 `remove_child`（孤儿院·归还孩子）用：孩子的 npc 条目已被删除，槽里那张卡若在关窗时
## 按「来自手牌」归还，`resolve_hand_entry` 会回落 `CardRegistry` 的静态预设，把一份
## 「查不到主人」的孩子卡复活回手牌（还能再拖进学校学习槽，怎么判都判不过）。
## 归还 = 孩子卡彻底消失，所以这里先把它从槽里摘掉，`_returnable_cards()` 就看不见它了。
##
## ⚠️ 刻意**不调 `_refresh()`**：那会按当前 `_placed` 重选 display 并重写正文，把刚打出来的
##    执行结果换成「请把要送回的孩子放进孩子栏。」（槽已空）。槽位视觉由 `set_card(null)`
##    自己刷新，`_placed` / 溯源已就地清干净，别无他事。
func purge_cards(cids: Array) -> void:
	if cids.is_empty():
		return
	for s in _slots:
		if s == null or not is_instance_valid(s):
			continue
		var c: CardData = s.get_card()
		if c == null or not (String(c.id) in cids):
			continue
		s.set_card(null)          # 静默：清 _current 与溯源，不触发 card_changed
		_placed.erase(s.slot_name)
		_slot_from_hand.erase(s.slot_name)


## 本次该归还手牌的卡：**来源 = 卡牌区**的那些（且非消耗品）。
##
## D-HAND2（2026-10-14）归还判据，两条同时成立才有资格回手牌：
##   ① 该卡来自卡牌区（该槽的溯源标记为 true）——排除 auto_fill / auto_attract /
##      回合实例这些「玩家手上从来没有」的引擎注入卡（送学的理性/感性/知觉正是这类）；
##   ② 未被本次流程「占用」——异步流程执行后由 `_commit_action` 接管，本函数不会被调用到。
func _returnable_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for s in _slots:
		# 槽位刚被重建（queue_free 尚未落地）时这里会抓到已释放对象，`is` 判定会直接报错。
		if s == null or not is_instance_valid(s):
			continue
		var c: CardData = s.get_card()
		if c == null or out.has(c):
			continue
		if not s.did_come_from_hand():
			continue  # auto_fill / auto_attract / 回合实例：不还，玩家本来就没有
		# 消耗品不回流（卡牌系统 §10.4）——但只在**执行后**成立：同步流程在快照时刻
		# `_consume_placed_consumables` 已把它从槽里摘掉，这条过滤只是双保险；异步流程
		# 走 `_commit_action` 占用模型（`_returned` 已置位，本函数不会被调到）。
		# 没执行就关窗（执行被锁 / 缺必填槽 / 玩家直接点关）→ 照常归还，绝不静默没收。
		if c.is_consumable() and _executed:
			continue
		out.append(c)
	return out


## 把该归还的卡归还手牌（幂等）。
## 执行结果出现后卡仍留在槽位，不在此归还；待用户关闭触发器才回卡牌区（见 close）。
## 消耗品不归还（卡牌系统 §10.4：分配时消耗；含 tag「消耗」，2026-09-08）；执行时已
## _consume_placed_consumables 移出 _placed，此处再过滤作为双保险。
func _return_cards() -> void:
	if _returned:
		return
	_returned = true
	var arr: Array[CardData] = _returnable_cards()
	_slot_from_hand.clear()
	# 卡已归还手牌 → 清掉槽位里的显示（静默 set_card，不触发 card_changed 信号），
	# 避免弹窗仍显示已回手的卡造成视觉重复。**注入卡也一并清掉**（它们随弹窗消失）。
	for s in _slots:
		if s != null and is_instance_valid(s) and s.get_card() != null:
			s.set_card(null)
	# 归还落点由弹窗自己现找（见 `_return_to_hand`）：**不能**指望开弹窗那一刻连好的
	# 那个 CardArea —— 它可能已经被切场景销毁了，对着僵尸发信号 = 玩家的卡静默消失。
	_return_to_hand(arr)
	# D-ATTRACT-HOLD：吸附时暂时摘走的手牌卡一并归还（与槽卡归还互不干扰）。
	_return_attract_held()
	cards_returned.emit(arr)


## D-HAND2：归还落点 —— 优先当前登记的卡牌区，**没 UI 时落账本**。
##
## 为什么不直接往 signal 上丢：弹窗销毁（含切场景被 OverlayRoot 清理）时卡牌区可能已经
## 换了人，旧代码又是在**开弹窗那一刻**把信号接到某个具体 CardArea 上的 —— 那张旧视图
## 一销毁，这就是个对着僵尸发信号的引用，玩家那张卡**连声响都没有地消失**。这里每次都向
## TriggerManager 现问，问不到就直落账本（与 `ActionQueue._land` 的兜底同口径）。
func _return_to_hand(arr: Array[CardData]) -> void:
	if arr.is_empty():
		return
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null:
		ca.add_cards(arr)
		return
	for c in arr:
		if c is CardData:
			Player.add_hand_card(c)


## D-ATTRACT-HOLD：某卡被吸附上槽后，把玩家手牌里的**同 id** 卡暂时摘下（幂等）。
## 手牌区不在场（纯逻辑探针）→ 静默跳过；摘不到（手牌本来就没有）→ 什么都不做。
func _hold_hand_copy_of(attracted: CardData) -> void:
	if attracted == null:
		return
	for held in _attract_held:
		if held.id == attracted.id:
			return  # 这个 id 已经摘过一份了
	var ca: CardArea = TriggerManager.get_card_area()
	if ca == null:
		return
	for c in ca.get_cards():
		if c != null and c.id == attracted.id:
			if ca.remove_card(c):
				_attract_held.append(c)
			return


## 当前「仍在玩家名下、但暂时寄放在本弹窗」的卡（2026-10-24，存档补全用）。
##
## 两类：
##   ① 槽里那些来自手牌的卡 —— 拖进槽时就已从账本摘掉，关窗才会归还；
##   ② 吸附时被 D-ATTRACT-HOLD 摘走的手牌卡 —— 关窗/销毁才会归还。
## 只读，不改任何状态；判据复用 `_returnable_cards()`，所以消耗品 / 引擎注入卡天然被排除
## （`_attract_held` 里存的全是玩家自己的手牌卡，直接并进来）。
##
## 给 `SaveLoader.data_get()` 用：不并的话，玩家在这些卡「寄放」期间存档，读档后它们就没了
## —— 弹窗状态不持久化，而账本里已经没有它们。
func hand_cards_on_hold() -> Array[CardData]:
	var out: Array[CardData] = _returnable_cards()
	for c in _attract_held:
		if c is CardData and not out.has(c):
			out.append(c)
	return out


## D-ATTRACT-HOLD：归还所有因吸附被暂时摘走的手牌卡（幂等）。## 无条件归还 —— 即使流程已执行：槽里那张是池卡，手牌这张是玩家自己的。
## 撞车兜底（2026-10-24）：流程中玩家可能**买到了与自己被摘手牌同 id 的卡**（杂货店货恰
## 好是玩家持有的物品）——买到的已在手，这份归还时 `add_card` 会因不可堆叠被拒；两份同 id
## 本就放不下，这份就地吸收（玩家仍持有一份，不亏数据），绝不静默丢失。
func _return_attract_held() -> void:
	if _attract_held_returned:
		return
	_attract_held_returned = true
	if _attract_held.is_empty():
		return
	var arr: Array[CardData] = []
	for c in _attract_held:
		if c is CardData:
			arr.append(c)
	_attract_held.clear()
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null:
		for c in arr:
			if not ca.add_card(c):
				print("[TriggerPopup] D-ATTRACT-HOLD 归还撞车（手牌已有同 id 且不可堆叠），吸收：%s" % c.id)
		return
	for c in arr:
		if c is CardData:
			Player.add_hand_card(c)


## D-HAND2：弹窗未经 `close()` 就被销毁（典型 = 切场景时被 OverlayRoot 清理）——
## 这时也不能让玩家自己拖进来的卡凭空蒸发。规则与 `close()` 完全一致：
## 未占用（没走过 `_commit_action`，那时 `_returned` 已被置位，此处会跳过）
## + 来自卡牌区 → 归还。`_frozen` 未提交也算未占用，一并归还。
func _exit_tree() -> void:
	if not _returned:
		_return_to_hand(_returnable_cards())
	# D-ATTRACT-HOLD：销毁兜底 —— 异步提交（_commit_action，_returned 已置位、上面的
	# 归还被跳过）也必须把吸附时摘走的手牌卡还回去。
	_return_attract_held()
	_returned = true
	_slot_from_hand.clear()


## 快照时刻（点击执行）消耗「分配时消耗」的道具卡（卡牌系统 §10.4；tag「消耗」同语义，2026-09-08）。
## 从 _placed 移除 + 清掉对应槽位 UI（静默），使其不参与后续路由、也不在结算后归还。
## 无论触发器结果成功与否都消耗（成功与否 = 条件/分支是否命中，消耗不受影响）。
## 仅作用于同步执行分支（异步流程为「占用」模型，结算时归还，不在此消耗）。
func _consume_placed_consumables() -> void:
	var consumed: Array[String] = []
	for sn in _placed.keys():
		var c: CardData = _placed[sn]
		if c != null and c.is_consumable():
			consumed.append(sn)
	for sn in consumed:
		var c: CardData = _placed[sn]
		_placed.erase(sn)
		_locked_slots.erase(sn)
		for s in _slots:
			if s.slot_name == sn:
				s.set_locked(false)
				s.set_card(null)
		print("[TriggerPopup] 消耗道具卡 %s（槽 %s）" % [c.display_name if c != null else "?", sn])


## 计算本次结算的 v 值。
## - compare：x = 加权均值（确定性，不掷骰）。
## - dice：x = 反 SL 确定性掷骰 d(sides)（D-C4 / D-F4），再 + 道具 bonus + 卡牌加骰 tag（D-F3）。
## 返回字典含 x / bonus / tag_bonus / v / is_dice / performer / performer_name。
## 关键：dice 模式下 x 由 seed 决定，_update_text 与 _on_execute 用相同 seed → 显示与结算一致。
func _compute_v(check: Dictionary) -> Dictionary:
	var attrs: Dictionary = check.get("attrs", {})
	var performer_name: String = String(check.get("performer", "执行者"))
	var performer: CardData = _placed.get(performer_name, null)
	var is_dice: bool = String(check.get("type", "compare")) == "dice"
	var x := 1
	if is_dice:
		# D-DOC13（越狱）：dice_attrs 多骰求和 + num_tag_penalty 惩罚；否则单骰 d(sides)。
		var dice_attrs: Array = check.get("dice_attrs", [])
		if not dice_attrs.is_empty():
			x = _roll_dice_attrs(check, performer)
		else:
			x = _dice_roll(check, performer)
	elif performer != null:
		# 触发器 compare 判定吃 tag/装备 bonus：生效值（与独立鉴定 _calc_x 同一口径，走 Player 统一入口）。
		var eff_attrs := Player.effective_attrs_of(performer)
		x = CardData.weighted_x(eff_attrs, attrs)

	var bonus := 0
	var tag_bonus := 0
	for sn in _placed:
		var c: CardData = _placed[sn]
		if c == null:
			continue
		# 道具卡的加骰加成（执行者不是道具，跳过其自身）
		if c.card_type == "item" and sn != performer_name:
			for a in attrs:
				bonus += c.get_bonus(String(a))
		# D-F3：骰子模式下，执行者 / 支援人物卡携带的「加骰 tag」均计入 tag_bonus
		if is_dice and c.card_type == "character":
			var dice_tags: Dictionary = check.get("dice_tags", {})
			if dice_tags is Dictionary:
				for t in dice_tags.keys():
					if c.has_tags([t], 1):
						tag_bonus += int(dice_tags[t])
	# M2（2026-08-23）：词条数值加骰 —— bonus += Player.player_num_tags[名] × 系数
	# （「str骰 + 酒馆后厨工作经验」用：经验值随打工累积，加骰量随之增长）
	if is_dice:
		var dice_num_tags: Dictionary = check.get("dice_num_tags", {})
		if dice_num_tags is Dictionary:
			for t in dice_num_tags.keys():
				tag_bonus += int(Player.player_num_tags.get(String(t), 0)) * int(dice_num_tags[t])
	# D-DOC17（2026-08-26）：玩家装备/持有物的 check_bonus（任意鉴定结果+1）。
	# ⚠️ 装备是三槽字典，取**值**（equipment_names），别把槽位名当装备名。
	bonus += CardRegistry.total_check_bonus(Player.equipment_names())
	return {
		"x": x, "bonus": bonus, "tag_bonus": tag_bonus,
		"v": x + bonus + tag_bonus, "is_dice": is_dice,
		"performer": performer, "performer_name": performer_name,
	}


## 反 SL 确定性掷骰（D-F4 / 鉴定 GDD §6）。
## seed_key 含业务名 + 触发器 + 检查属性；extra 含当前天 + 各已放卡 id，
## 保证「同局同天同卡 → 同结果」，且不同卡 / 不同天结果不同（读档重来无意义）。
func _dice_roll(check: Dictionary, performer: CardData) -> int:
	# D-DOC15（2026-08-26）：weighted_sides —— 骰面 = 执行者加权均值（如 {"app":2,"int":8} = 魅力×0.2+智力×0.8）。
	# 招聘/质疑/敲诈等「派遣者属性加权掷骰」用；否则沿用固定 sides。
	var weighted_sides: Dictionary = check.get("weighted_sides", {})
	if not weighted_sides.is_empty() and performer != null:
		var eff_attrs := Player.effective_attrs_of(performer)
		var ws: int = CardData.weighted_x(eff_attrs, weighted_sides)
		return Player.roll_dice("dice:weighted:%s:%s" % [_trigger_id, _phase_name], ws, _placed_salt())
	var sides: int = int(check.get("sides", 10))
	var seed_key: String = "dice:%s:%s:%d" % [_trigger_id, _phase_name, int(check.get("attrs", {}).hash())]
	return Player.roll_dice(seed_key, sides, _placed_salt())


## D-DOC13（越狱）：多骰求和 —— dice_attrs 每项掷 1d(执行者该属性生效值)，求和；
## num_tag_penalty {名: 系数} → 再减去 系数 × 执行者该 num_tag 值（越狱「-2×越狱次数」）。
func _roll_dice_attrs(check: Dictionary, performer: CardData) -> int:
	var dice_attrs: Array = check.get("dice_attrs", [])
	var salt := _placed_salt()
	var total := 0
	for an in dice_attrs:
		total += _roll_attr_die(performer, String(an), salt)
	var penalty_cfg: Dictionary = check.get("num_tag_penalty", {})
	for tag in penalty_cfg:
		total += int(penalty_cfg[tag]) * _performer_num_tag(performer, String(tag))
	return total


## 掷 1d(执行者某属性生效值)，至少 1 面。
func _roll_attr_die(performer: CardData, attr: String, salt: String) -> int:
	var eff: Dictionary = Player.effective_attrs_of(performer) if performer != null else {}
	var sides: int = max(1, int(eff.get(attr, 0)))
	return Player.roll_dice("diceattr:%s:%s:%s" % [_trigger_id, _phase_name, attr], sides, salt)


## 执行者某 num_tag 值（从其 npc 条目读；主角卡读 player_num_tags）。
func _performer_num_tag(performer: CardData, tag: String) -> int:
	if performer == null:
		return 0
	if performer.id == "Hero":
		return int(Player.player_num_tags.get(tag, 0))
	var npc_key := EffectProcessor._npc_key_of(performer)
	var entry: Dictionary = Player.npc.get(npc_key, {})
	return int(entry.get("num_tags", {}).get(tag, 0))


## 反 SL 盐：当前天 + 各已放卡 id（多骰/单骰/越狱结算共用）。
func _placed_salt() -> String:
	var extra := str(Player.time)
	for sn in _placed:
		var c: CardData = _placed[sn]
		if c != null:
			extra += "|" + c.id
	return extra


## 写 PhaseLabel。正式表现走 human 文案，开发读数只在 SHOW_DEBUG_READOUT 时用。
## 这一行是布局的一部分（`_apply_layout` 按 marker 定位），所以不移除节点、只换 text。
func _set_phase_label(human: String, debug_text: String) -> void:
	phase_label.text = debug_text if SHOW_DEBUG_READOUT else human


## 结算结果表头。2026-10-24 起**正式表现直接关掉表头**（流程性语言）；开发读数才拼 mode、内部结果键与 v。
## `bkey` 是 `suc0` / `suc1` 这种内部分支键，不该出现在玩家眼前。
func _result_header(mode: String, bkey: String, v: int) -> String:
	if SHOW_DEBUG_READOUT:
		return "— 执行结果（%s，%s，v=%d）—" % [mode, bkey, v]
	return ""


func _update_text(display: Dictionary) -> void:
	var check_v: Variant = display.get("check", null)
	if not (check_v is Dictionary):
		_set_phase_label("", "phase: %s" % _phase_name)
		_render_right_text(display)
		execute_btn.disabled = _is_execute_disabled(display)
		return
	var check: Dictionary = check_v
	# D-DOC3：多骰模式显示预览
	var mode_type := String(check.get("mode", ""))
	if mode_type == "multi" or mode_type == "multi_all" or mode_type == "multi_any":
		var multi_needs: Dictionary = check.get("multi_needs", {})
		_set_phase_label("",
				"phase: %s  |  🎲多骰 mode=%s  multi_needs=%s" % [_phase_name, mode_type, str(multi_needs)])
		_render_right_text(display)
		execute_btn.disabled = _is_execute_disabled(display)
		return
	var needs: Array = check.get("needs", [])
	var c := _compute_v(check)
	# 判定预览串（模式符号、x=、needs=、判定=）只在调试读数开关打开时上屏。
	# 2026-10-14 起默认关闭：它既暴露内部公式，也把「判定=成功/失败」提前剧透给玩家。
	var mode_prefix: String = "🎲骰子 " if c.is_dice else "📐比大小 "
	var detail: String
	if c.is_dice:
		detail = "掷骰 x=%d  道具+%d  标签+%d  → v=%d" % [int(c.x), int(c.bonus), int(c.tag_bonus), int(c.v)]
	else:
		detail = "执行者 x=%d  道具 +%d  → v=%d" % [int(c.x), int(c.bonus), int(c.v)]
	_set_phase_label("",
			"phase: %s  |  %s |  %s  needs=%s  判定=%s" % [
				_phase_name, mode_prefix, detail, str(needs), _verdict(int(c.v), needs)])
	_render_right_text(display)
	execute_btn.disabled = (c.performer == null) or _has_lock_tags(display)


## 右栏文本：每次都**整体重赋值**（即"先清空再按当前已放卡重建"）。
## 取出卡片 → _on_slot_changed 触发 _refresh → 此处按 _placed 现状重建 → 文本自然回退。
func _render_right_text(display: Dictionary) -> void:
	var text: String = String(display.get("显示内容", ""))
	for sn in _placed:
		text = text.replace("{%s}" % sn, _placed[sn].display_name)
	var extra := _derive_dynamic_text(display)
	if extra != "":
		text = extra  # 放入卡后动态说明整体替换基础文案，而非追加
	# 2026-10-24：显示内容与「结算文本 / 分支 text」同口径过 TextVars——
	# 此前只做 {槽位名} 替换，{child_name}/{player_name} 等全局占位符会原样上屏
	#（实测：学校「引导」display 在无 resolver 的纯文本路径下露出 {child_name}）。
	text = TextVars.resolve(text, _build_slot_context(display))
	text_label.text = text


## 按已放卡派生动态说明（先删后加模型的核心：每次都从 _placed 重新计算）。
func _derive_dynamic_text(_display: Dictionary) -> String:
	var resolver: String = String(_expanded.get("resolver", ""))
	if resolver == "bookshop":
		var buyer: CardData = _placed.get("人物", null)
		if buyer == null:
			return ""
		var iv: int = int(buyer.attrs.get("int", 0))
		if iv <= 2:
			return "没看到什么合适的书。"
		var cost: int = 3 if iv <= 5 else 1
		var tier: String = "低品质" if iv <= 5 else "高品质"
		var lines := "放入角色后，将花掉 %d，购入%s的书籍。" % [cost, tier]
		# 「书店剧情xxx」这条占位 hook 照样检测，只是不再写进玩家看得见的正文
		# （2026-10-14：原「对应剧情尚未实装，待接入」是开发痕迹，不上屏）。
		var item: CardData = _placed.get("物品", null)
		if item != null:
			for t in item.tags:
				var ts: String = String(t)
				if ts.begins_with("书店剧情"):
					push_warning("[TriggerPopup] 书店剧情物品尚未接入：%s" % ts)
		return lines
	# 2026-09-09：移除通用「已放卡清单」分支（原逻辑会把 display 的显示内容整体替换成
	# 「· 执行者：xxx」槽位清单，导致按执行者属性分层的文本——如在剧院打工的
	# Str<6 / Str>=6 文案——放卡后无法显示）。无 resolver 的触发器一律保留显示内容，
	# 占位符（{执行者} 等）仍由上方正常替换。已核对：无 resolver 的 display 无一依赖该清单。
	return ""


## resolver 触发器（无 check）在装配态是否允许执行：必填槽未填则禁用。
## M0（2026-08-23）：无 resolver 且 check 为 null 的纯文本 display（如酒馆打工 零/一/拒绝），
##   必填槽已填即可执行（原逻辑一律禁用，导致纯文本路径无法推进）。
## D-DOC5（2026-08-24）：display.lock_execute = [tag,...]，任意已放卡命中其一则禁用确定按钮。
## 2026-10-25：删掉「resolver 为空就恒禁用」那条分支。它只可能被 `check.mode=multi*` 的档走到
##   （无 check 的档在上面那条就 return 了），结果是 6 条多骰档填满必填槽也永远按不动 ——
##   群死凶器 t2「推进」/ t3「收网」、群死常规 t2「试探」、调查丹尼斯 t2「潜入」、
##   夜间调查剧院「万事俱备」（该线其余四档全 lock_execute）、涂鸦大作战「放露易丝」。
##   多骰的成败本来就由 `_compute_v` 的 multi 分支算，拦在按钮上只会卡死主线。
func _is_execute_disabled(display: Dictionary) -> bool:
	# D-DOC5：lock_execute 标签门控（优先级最高）
	if _has_lock_tags(display):
		return true
	return _required_slots_missing(display)


## D-DOC5：检查 display 是否「禁止确定」。
## lock_execute 支持两种形式：
##   - true（布尔）：该 display 一旦被选中即禁止确定（如「app>=13,str<12 危险境地」）
##   - [tag,...]（数组）：任一已放卡命中其一 tag 即禁止确定（如「child 不能按确定」）
func _has_lock_tags(display: Dictionary) -> bool:
	var lt_v: Variant = display.get("lock_execute", null)
	if lt_v is bool and bool(lt_v):
		return true
	if not (lt_v is Array) or lt_v.is_empty():
		return false
	for sn in _placed:
		var c: CardData = _placed[sn]
		if c == null:
			continue
		for t in lt_v:
			if c.has_tags([String(t)], 1):
				return true
	return false


func _required_slots_missing(display: Dictionary) -> bool:
	var slots: Dictionary = display.get("slots", {})
	for sn in slots:
		if bool(slots[sn].get("required", false)) and not _placed.has(String(sn)):
			return true
	return false


func _verdict(v: int, needs: Array) -> String:
	if needs.is_empty():
		return "—"
	if v < int(needs[0]):
		return "suc0（失败档）"
	for i in needs.size():
		if v < int(needs[i]):
			return "suc%d" % i
	return "suc%d（最高档）" % needs.size()


func _suc_idx(v: int, needs: Array) -> int:
	if needs.is_empty():
		return 0
	if v < int(needs[0]):
		return 0
	for i in needs.size():
		if v < int(needs[i]):
			return i
	return needs.size()


# ============================================================
#  M3 + M4（2026-08-23）：统一结算 outcome（副骰 extra_dice + plot 键）
#  _resolve_outcome 被 _on_execute（同步）与 _compute_normal_result（异步）共用，
#  保证两条路径文本/effect/plot 一致。plot 格式 {"path": "...", "name": "..."}，
#  散落各剧情文件，落地时 PlotImporter.add_plot(path, name)。
# ============================================================

## 解析当前 display 的结算 outcome：{effect, text, plot, mode, bkey, v, extra_note}。
## - check 为 null（M0）：effect/plot 取自 display 级，文本=显示内容。
## - check 为 dict：掷主骰选分支；若配 extra_dice，掷副骰，<below 则前缀文本+并入 effect。
## - check.mode=="multi"（D-DOC3，2026-08-24）：多骰模式，每个 attr 各掷一骰，
##   各按 multi_needs[attr] 阈值定档，总档 = min(all)（mode 缺省/"all"）或 max(any)。
func _resolve_outcome(display: Dictionary) -> Dictionary:
	var check_v: Variant = display.get("check", null)
	if not (check_v is Dictionary):
		# D-订报（2026-09-08）：无 check 的 display 可选「结算文本」作为执行结果文案；
		# 缺省回退「显示内容」（历史行为，兼容既有触发器）。
		var result_key := "结算文本" if display.has("结算文本") else "显示内容"
		var d_text := TextVars.resolve(String(display.get(result_key, "")), _build_slot_context(display))
		return {
			"effect": display.get("effect", {}),
			"text": d_text,
			"plot": display.get("plot", null),
			"mode": "无骰", "bkey": "—", "v": 0, "extra_note": "",
		}
	var check: Dictionary = check_v
	var mode_type := String(check.get("mode", ""))

	# D-DOC3：多骰模式（multi / multi_all / multi_any）
	if mode_type == "multi" or mode_type == "multi_all" or mode_type == "multi_any":
		return _resolve_multi_outcome(display, check)

	var c := _compute_v(check)
	if c.performer == null:
		return {}
	var idx := _suc_idx(int(c.v), check.get("needs", []))
	var bkey := "suc%d" % idx
	var branch: Dictionary = check.get("branches", {}).get(bkey, {})
	var branch_text: String = TextVars.resolve(String(branch.get("text", "(无文案)")), _build_slot_context(display))
	var effect: Dictionary = branch.get("effect", {})
	var mode := "🎲骰子" if c.is_dice else "📐比大小"

	# M3：副骰 extra_dice —— 1d 执行者属性（如 bod），<below 触发前缀+并入 effect
	var extra_note := ""
	var exv: Variant = check.get("extra_dice", null)
	if exv is Dictionary:
		var ed: Dictionary = exv
		var sides := _extra_sides(ed, c.performer)
		var roll := Player.roll_dice("extra:%s:%s" % [_trigger_id, _phase_name], sides, _voyage_extra(c.performer, null))
		var below := int(ed.get("below", 0))
		if below > 0 and roll < below:
			var prefix := String(ed.get("text_prefix", ""))
			if prefix != "":
				branch_text = prefix + branch_text
			var ex_eff: Variant = ed.get("effect", null)
			if ex_eff is Dictionary and not (ex_eff as Dictionary).is_empty():
				effect = _merge_effect(effect, ex_eff)
			extra_note = ""
		else:
			extra_note = ""

	# D-DOC16（2026-09-09）：分支 bonus —— 满足条件才并入的次级 effect / plot（一次性守卫等）。
	# 条件键：if_player_tags（结算前 Player 已持有其中全部）、unless_player_tags（均未持有）。
	# 语义：查的是 Player.player_tags（持久 tags，流程 _flow_tags 尚未提交）→
	# 天然表达「此前已达成过 X」（如第二次及以后打工成功），同一次结算里刚加的 tag 不会自触发。
	var bonus_v: Variant = branch.get("bonus", null)
	var plot_out: Variant = branch.get("plot", null)
	if bonus_v is Dictionary:
		var bn: Dictionary = bonus_v
		if _bonus_satisfied(bn):
			var be: Variant = bn.get("effect", null)
			if be is Dictionary and not (be as Dictionary).is_empty():
				effect = _merge_effect(effect, be)
			if plot_out == null and bn.has("plot"):
				plot_out = bn["plot"]

	return {
		"effect": effect, "text": branch_text, "plot": plot_out,
		"mode": mode, "bkey": bkey, "v": int(c.v), "extra_note": extra_note,
		"empty_goto": branch.get("empty_goto", null),
	}


## 副骰骰面：优先 sides_attr（1d 执行者该属性），否则 sides（默认 10）。至少 1。
## sides_attr 取「生效值」（裸值 + tag/装备 bonus），与 compare 判定同一口径（走 Player 统一入口）。
func _extra_sides(ed: Dictionary, performer: CardData) -> int:
	var sa: String = String(ed.get("sides_attr", ""))
	if sa != "" and performer != null:
		return max(1, int(Player.effective_attrs_of(performer).get(sa, 0)))
	return max(1, int(ed.get("sides", 10)))


## 合并两个 effect 字典（副骰 effect 并入分支 effect）。
func _merge_effect(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate(true)
	for k in b:
		match k:
			"tags", "remove_tags", "stuff", "equipment":
				var arr: Array = out.get(k, [])
				for v in b[k]:
					arr.append(v)
				out[k] = arr
			"num_tags":
				var nt: Dictionary = out.get("num_tags", {})
				for t in b[k]:
					nt[t] = b[k][t]
				out["num_tags"] = nt
			_:
				out[k] = b[k]
	return out


## D-DOC16：分支 bonus 条件评估（基于 Player.player_tags —— 结算当下流程 tags 未提交）。
func _bonus_satisfied(bn: Dictionary) -> bool:
	var has_v: Variant = bn.get("if_player_tags", null)
	if has_v is Array:
		for t in has_v:
			if not Player.player_tags.has(String(t)):
				return false
	var lacks_v: Variant = bn.get("unless_player_tags", null)
	if lacks_v is Array:
		for t in lacks_v:
			if Player.player_tags.has(String(t)):
				return false
	return true


# ============================================================
#  D-DOC3（2026-08-24）：多骰模式（check.mode = "multi"）
#  每个 attr 各掷一骰 d(sides)，各按 multi_needs[attr] 阈值数组定档。
#  总档聚合方式由 combine 决定：
#    - 缺省 / "all"：总档 = min(各骰档)（全骰须过线才算该档成功）
#    - "any"：总档 = max(各骰档)（任一骰过线即该档成功）
#    - "dual"（2026-08-25）：双骰双阈值精确 5 档判定（调查丹尼斯专用）。
#        设两骰档位 a_tier/b_tier（0=低于第1阈值，1=过第1阈值，2=过第2阈值）：
#          双<1 → 档0(全失败)；仅A过线 → 档1；仅B过线 → 档2；
#          双≥1且非双≥2 → 档3(过线成功)；双≥2 → 档4(大成功)。
#        用于「0失败/1仅int受伤/2仅bod一无所获/3过线/4大成功」这类双骰各有成败的分支。
#  branches 按总档 sucN 选取，与单骰模式一致。
#  multi_needs: {attr: [t0, t1, ...]} —— attr 骰值 < t0 = 档0(失败)，>= t0 且 < t1 = 档1...
#  attrs: {attr: weight} —— weight 在多骰模式下忽略（各骰独立），仅用于决定掷哪些属性。
#  performer: 取 attrs 中首个属性的执行者（共用单骰的 performer 槽名）。
# ============================================================

## D-DOC3：多骰模式结算。
## sides_mode:"sum"（2026-08-25 调查丹尼斯专用）：每个骰的骰面 = 所有已放角色卡的该属性之和
##   （如两卡 bod 各 9 → 1d(18)），而非固定 sides。缺省/其他 → 固定 sides。
## dual 模式神偷替代（check.thief_tag，2026-08-25）：队伍任一已放角色带该 tag 时，
##   bod 判定被神偷替代——int≥8 → 大成功、int≥5 → 过线（无需看 bod 骰）。
func _resolve_multi_outcome(display: Dictionary, check: Dictionary) -> Dictionary:
	var attrs: Dictionary = check.get("attrs", {})
	var multi_needs: Dictionary = check.get("multi_needs", {})
	var sides: int = int(check.get("sides", 10))
	var sides_mode := String(check.get("sides_mode", ""))
	var mode_type := String(check.get("mode", "multi"))
	var combine := String(check.get("combine", ""))
	var is_any := (mode_type == "multi_any")
	var is_dual := (combine == "dual")
	var performer_name: String = String(check.get("performer", "执行者"))
	var performer: CardData = _placed.get(performer_name, null)
	if performer == null:
		return {}

	# D-夜探（2026-09-08）：队伍带 thief_tag 时，跳过 thief_skip_attrs 列出的属性骰（doc：神偷免 bod 档）。
	var has_thief: bool = _has_placed_tag(String(check.get("thief_tag", "")))
	var thief_skip: Array = check.get("thief_skip_attrs", [])

	# 逐属性掷骰 + 定档
	var roll_details: Array = []  # [{attr, roll, tier, sides}]
	var overall_tier := 999 if not is_any else -1
	for an in attrs:
		var attr_name := String(an)
		if has_thief and attr_name in thief_skip:
			continue
		var seed_key := "multi:%s:%s:%s" % [_trigger_id, _phase_name, attr_name]
		var extra := str(Player.time)
		for sn in _placed:
			var c: CardData = _placed[sn]
			if c != null:
				extra += "|" + c.id
		# D-DOC3（2026-08-25）：sides_mode:"sum" → 骰面 = 所有已放角色卡该属性【生效值】之和
		var dice_sides := sides
		if sides_mode == "sum":
			var total := 0
			for sn in _placed:
				var pc: CardData = _placed[sn]
				if pc != null and pc.card_type == "character":
					total += int(Player.effective_attrs_of(pc).get(attr_name, 0))
			dice_sides = max(1, total)
		var roll := Player.roll_dice(seed_key, dice_sides, extra)
		var thresholds: Array = multi_needs.get(attr_name, [])
		var tier := 0
		for t in thresholds:
			if roll >= int(t):
				tier += 1
			else:
				break
		roll_details.append({"attr": attr_name, "roll": roll, "tier": tier, "sides": dice_sides})
		if is_any:
			overall_tier = max(overall_tier, tier)
		else:
			overall_tier = min(overall_tier, tier)

	# D-DOC3（2026-08-25）：dual 组合 —— 双骰双阈值精确 5 档（含神偷替代）
	if is_dual and roll_details.size() >= 2:
		var a_tier: int = int(roll_details[0]["tier"])
		var b_tier: int = int(roll_details[1]["tier"])
		overall_tier = _dual_idx(a_tier, b_tier, has_thief)

	# 所有骰都被跳过（如 thief_skip 覆盖全部 attrs）→ 无从判定，安全兜底为失败。
	if roll_details.is_empty():
		return {}

	var idx := overall_tier
	var bkey := "suc%d" % idx
	var branch: Dictionary = check.get("branches", {}).get(bkey, {})
	var branch_text := TextVars.resolve(String(branch.get("text", "(无文案)")), _build_slot_context(display))
	var effect: Dictionary = branch.get("effect", {})

	# 构造明细文本
	var detail_parts: Array = []
	for rd in roll_details:
		detail_parts.append("%s:%d/d%d(档%d)" % [rd["attr"], rd["roll"], rd["sides"], rd["tier"]])
	var detail_text := "🎲多骰 %s → 总档%d(%s)" % ["|".join(detail_parts), overall_tier, bkey]

	return {
		"effect": effect, "text": branch_text, "plot": branch.get("plot", null),
		"mode": detail_text, "bkey": bkey, "v": overall_tier, "extra_note": "",
		"empty_goto": branch.get("empty_goto", null),
	}


## D-DOC3（2026-08-25）：双骰双阈值精确 5 档映射（含神偷替代）。
## has_thief 为真时：bod 判定被神偷替代——int 档≥2 → 4(大成功)、int 档≥1 → 3(过线)，
##   无需看 bod 骰；int 档<1 仍走正常（神偷只替代 bod，不替代 int）。
## 无神偷：双<1→0；仅A过线→1；仅B过线→2；双≥1非双≥2→3；双≥2→4。
func _dual_idx(a_tier: int, b_tier: int, has_thief: bool = false) -> int:
	if has_thief:
		if a_tier >= 2:
			return 4
		if a_tier >= 1:
			return 3
	if a_tier >= 2 and b_tier >= 2:
		return 4
	if a_tier >= 1 and b_tier >= 1:
		return 3
	if a_tier >= 1:
		return 1
	if b_tier >= 1:
		return 2
	return 0


## D-DOC3（2026-08-25）：队伍（已放角色卡）中是否有任一人携带指定 tag。
func _has_placed_tag(tag: String) -> bool:
	if tag == "":
		return false
	for sn in _placed:
		var c: CardData = _placed[sn]
		if c != null and c.card_type == "character" and c.has_tags([tag], 1):
			return true
	return false


## M4：落地 plot 键 {"path","name"} —— 散落各剧情文件，直接 PlotImporter.add_plot。
## D-DOC11（2026-08-24）：附带传入 slot context（含 executor_name1/2/... 映射），
## 使剧情对话中的 {executor_name1} 等占位符可解析。
func _land_plot(plot: Variant) -> void:
	if not (plot is Dictionary):
		return
	var p: Dictionary = plot
	var pp: String = String(p.get("path", ""))
	var pn: String = String(p.get("name", ""))
	if pp != "" and pn != "":
		PlotImporter.add_plot(pp, pn, _build_plot_context())


## D-DOC11：构建传给剧情的上下文：executor_name1/2/... 按角色槽放入顺序编号。
## 首个执行者同时注入 executor_name + executor.* 各字段（{executor_name}/{executor.x} 语义 = 执行者）。
## 2026-10-10（周游线）：首个执行者**优先取「执行者」槽**，不再按 _placed 插入序取首张角色卡。
##   —— 多角色槽弹窗（周游：执行者/同伴/行囊）里，玩家先拖「同伴」再拖「执行者」时，
##   旧口径会让剧情里的 {executor_name} 指到同伴头上。与 _build_slot_context 的既有口径对齐：
##   「执行者」槽存在且已放卡 → 就是它；否则（无该槽 / 该槽空）才回落到首个角色卡。
## 2026-10-16（家业主线）：补注 ctx["_investigators"]（text_vars 的调查者名单）——
##   不注入时剧情里的 {int}/{bod}/{app}/{str}/{tags:xxx} 会走 text_vars 的默认名单
##   （主角 + 带「追随」tag 的 npc），指不到本次触发器槽位里的角色。家业主线的
##   《调查丹尼斯之夜》正靠 {int}/{bod}/{tags：神偷} 指代「智谋/行动」两槽的人
##   （{int}=槽位角色中 int 最高者、{bod}=bod 最高者、{tags:神偷}=带神偷的槽位角色）。
func _build_plot_context() -> Dictionary:
	var ctx: Dictionary = {}
	var ordered: Array = []
	if _placed.get("执行者", null) is CardData:
		ordered.append("执行者")
	for sn in _placed:
		if String(sn) != "执行者":
			ordered.append(sn)
	var idx := 1
	var investigators: Array = []
	for sn in ordered:
		var c: CardData = _placed.get(sn, null)
		if c == null or c.card_type != "character":
			continue
		if idx == 1:
			ctx["executor_name"] = c.display_name
			ctx["executor.name"] = c.display_name
			ctx["executor.tags"] = ", ".join(c.tags)
			ctx["executor.desc"] = c.description
			for a in ["int", "app", "str", "bod"]:
				ctx["executor." + a] = c.attrs.get(a, 0)
		ctx["executor_name%d" % idx] = c.display_name
		idx += 1
		investigators.append({
			"name": c.display_name,
			"int": int(c.attrs.get("int", 0)),
			"app": int(c.attrs.get("app", 0)),
			"str": int(c.attrs.get("str", 0)),
			"bod": int(c.attrs.get("bod", 0)),
			"tags": c.tags.duplicate(),
		})
	if not investigators.is_empty():
		ctx["_investigators"] = investigators
	# 槽名占位符（与 _build_slot_context 同口径，家业管理 §5.2：{主管}/{护卫} 换成本槽卡名）。
	# 剧情里指代「某个槽位的人」一律用槽名，不用 {int}/{bod} 这类属性占位符——
	# 后者走 text_vars 的属性排序（且 {tags:xxx} 持有者被排除出排序池），
	# 《调查丹尼斯之夜》就踩过：神偷恰好是 bod 最高者时 {bod} 被解析成空串。
	for sn2 in _placed:
		var c2: CardData = _placed.get(sn2, null)
		if c2 == null or c2.card_type != "character":
			continue
		ctx[String(sn2)] = c2.display_name
	return ctx


func _on_execute() -> void:
	# 模块专属结算（家业经营：出航双检查 / 书店购书 / 越狱）—— 数据驱动由 trigger 顶层 resolver 字段指定。
	var resolver: String = String(_expanded.get("resolver", ""))
	var duration: int = int(_expanded.get("duration", 0))
	if resolver != "":
		if duration > 0:
			var res: Dictionary = _compute_async_result(resolver)
			if res.is_empty():
				_resolve_special(resolver)  # 该 resolver 暂不支持异步 → 退回即时
			else:
				_compute_and_freeze(res)
			return
		_resolve_special(resolver)
		return

	if duration > 0:
		var res: Dictionary = _compute_normal_result()
		if res.is_empty():
			return
		_compute_and_freeze(res)
		return

	var display: Dictionary = TriggerLoader.select_display(_phase, _placed, TriggerManager.get_routing_tags())
	var outcome := _resolve_outcome(display)
	if outcome.is_empty():
		return  # performer 缺失（_resolve_outcome 返回空）

	var mode: String = String(outcome.get("mode", ""))
	var bkey: String = String(outcome.get("bkey", "—"))
	var v: int = int(outcome.get("v", 0))
	var branch_text: String = String(outcome.get("text", ""))
	if String(outcome.get("extra_note", "")) != "":
		branch_text += "\n" + String(outcome["extra_note"])
	# 显示执行结果
	var header := _result_header(mode, bkey, v)
	if header != "":
		text_label.text = "%s\n\n%s\n%s" % [text_label.text, header, branch_text]
	else:
		text_label.text = "%s\n\n%s" % [text_label.text, branch_text]
	# 结算后这一行留空：结果已经在下面的「执行结果」块里，再挂一遍阶段名是重复。
	# 若这一支还要路由到下一 phase，`_update_text` 会立刻把新阶段名写回来。
	_set_phase_label("", "%s → %s  v=%d" % [_phase_name, bkey, v])
	print("[TriggerPopup] %s/%s → %s  v=%d  effect=%s  plot=%s" % [
		_turn_id, _phase_name, bkey, v, str(outcome.get("effect", {})), str(outcome.get("plot", null))])

	# 快照时刻消耗 consumable 道具卡（卡牌系统 §10.4：分配时消耗，不归还）
	# 从这一刻起本次流程算「已执行」：之后关窗，槽里的消耗品不再回流（见 _returnable_cards）。
	_executed = true
	_consume_placed_consumables()

	# 应用效果 + plot + 路由
	_finalize_phase(outcome, display)


## 异步等待流程：算出统一结算字典后冻结界面（锁槽/禁执行/显取消/留关闭）。
## D-DOC18（读书）：result 带 "before" 时，冻结前先在正文显示「阅读前文本」。
func _compute_and_freeze(result: Dictionary) -> void:
	_pending_result = result
	_freeze()
	var before_v: Variant = result.get("before", "")
	if before_v is String and String(before_v) != "":
		text_label.text = String(before_v)


func _freeze() -> void:
	_frozen = true
	for s in _slots:
		s.set_interactive(false)
	execute_btn.visible = false
	cancel_btn.visible = true
	close_btn.text = "提交"
	_set_phase_label("", "phase: %s  |  已执行，等待结算" % _phase_name)


func _on_cancel() -> void:
	_pending_result = {}
	_frozen = false
	for s in _slots:
		s.set_interactive(true)
	execute_btn.visible = true
	cancel_btn.visible = false
	close_btn.text = "关闭"
	_refresh()


## 冻结态关闭 = 提交为"进行中"行动：登记 ActionQueue，占用卡不归还，关弹窗。
func _commit_action() -> void:
	var duration: int = int(_expanded.get("duration", 1))
	var slots_snap: Dictionary = {}
	for sn in _placed:
		slots_snap[sn] = _placed[sn]
	# D-HAND2：占用卡里哪些是玩家从手牌拿来的 —— 结算（`ActionQueue._land`）只还这部分。
	# 槽位快照本身仍要带齐 `_placed` 全体：slot_attrs / plot 执行者 这些效果靠它定位。
	var from_hand: Array[CardData] = _returnable_cards()
	ActionQueue.enqueue(_trigger_id, slots_snap, _pending_result, duration, from_hand)
	# immediate_effect：提交即落地（不等过天结算）。直落 Player（不走 flow_tags），
	# 否则「回家」的「想回家了」会卡在流程字典、下一天仍被拦截。放在提交而非冻结，
	# 保证「取消」不会留下已落地的副作用。
	var imm: Variant = _pending_result.get("immediate_effect", null)
	if imm is Dictionary and not (imm as Dictionary).is_empty():
		EffectProcessor.apply(imm, {"placed": _placed})
	_returned = true  # 占用卡已离开卡牌区，标记避免后续重复归还
	# 异步流程：执行即「流程结束」（后续是 ActionQueue 结算），发 flow_completed 让 TriggerSpot
	# 据此 consume（repeatable=false 的触发器执行后即禁用，不再被 exclusive 锁定成「点了没反应」）。
	flow_completed.emit(_trigger_id, TriggerLoader.is_repeatable(_trigger_id), not _flow_failed)
	if not OverlayRoot.close_overlay(self):
		queue_free()


## 计算各 resolver 的异步结算结果（只算不落地）；不支持的返回空字典。
func _compute_async_result(resolver: String) -> Dictionary:
	var display: Dictionary = TriggerLoader.select_display(_phase, _placed, TriggerManager.get_routing_tags())
	match resolver:
		"bookshop":
			return _compute_bookshop_result(display)
		"prison_break":
			return _compute_prison_break_result(display)
		"go_home":
			return _compute_go_home_result(display)
		"voyage":
			return _compute_voyage_result(display)
		_:
			# D-DOC14（打听）：子类可 override 的自定义 resolver 异步结算钩子。
			return _compute_custom_async_result(resolver, display)


## 回家（新手教程 GDD）：duration 1 异步结算。执行即落地「想回家了」（解封下一天），
## 冻结时显示「希望一切安好」；过天结算 ResultPopup 显示「我迫不及待回家看看了」，确认后切家业。
##
## 「出现管家」放在 **effect（结算结果）** 而非 immediate_effect：ActionQueue._land 先 apply effect
## 再 goto_scene（action_queue.gd:136 → 164），因此进家业那一刻 tag 已在 player_tags 里，
## home.gd 的 _ready 能读到 → 管家出现在地图上。放在 immediate_effect（提交时）也能work，
## 但「家的内容」语义上属于触发器的**结果**，放 effect 便于以后单看 resolver 就知道家业初始状态。
func _compute_go_home_result(_display: Dictionary) -> Dictionary:
	return {
		"effect": {"tags": ["出现管家"]},
		"before": "希望一切安好",
		"text": "我迫不及待回家看看了",
		"goto_scene": "res://scene/home.tscn",
		"immediate_effect": {"tags": ["想回家了"]},
	}


## D-DOC14（2026-08-26）：子类可 override 的自定义 resolver 异步结算钩子。
## 默认返回空字典（= 不支持该 resolver，由 _on_execute 退回即时 _resolve_special）。
## 子类（如 InquiryTriggerPopup）override 本方法处理专属 resolver 的「只算不落地」结算。
func _compute_custom_async_result(_resolver: String, _display: Dictionary) -> Dictionary:
	return {}


## 通用 compare/dice 触发器的异步结算结果（只算不落地）。
## M3/M4：复用 _resolve_outcome，含副骰文本/effect 与 plot。
func _compute_normal_result() -> Dictionary:
	var display: Dictionary = TriggerLoader.select_display(_phase, _placed, TriggerManager.get_routing_tags())
	var outcome := _resolve_outcome(display)
	if outcome.is_empty():
		return {}
	var mode: String = String(outcome.get("mode", ""))
	var bkey: String = String(outcome.get("bkey", "—"))
	var v: int = int(outcome.get("v", 0))
	var text := "%s\n%s" % [_result_header(mode, bkey, v), String(outcome.get("text", ""))]
	if String(outcome.get("extra_note", "")) != "":
		text += "\n" + String(outcome["extra_note"])
	return {"effect": outcome.get("effect", {}), "text": text, "plot": outcome.get("plot", null)}


## 阶段结算：应用效果 → plot → 检测 ending / 路由下一个 turn
## outcome = {effect, plot, ...}（M4：plot 在 effect 之后、ending 之前落地）
func _finalize_phase(outcome: Dictionary, _display: Dictionary) -> void:
	# 孤儿院首次判定（2026-09-26）：任何「点击并确定触发器」都算玩家已经历过事件 →
	# 摘除「与小七相遇」（首次到访标记）。授予点唯一 = TutorialManager.complete_tutorial；
	# 另一处摘除点 = PlotImporter.add_plot（进入任何剧情）。幂等：无该 tag 时 no-op。
	Player.remove_tag(TutorialManager.FIRST_VISIT_TAG)
	var effect: Dictionary = outcome.get("effect", {})
	# 1. 效果落地（tags 进流程字典，不直接写 player_tags）
	if not effect.is_empty():
		TriggerManager.apply_effect(effect, _placed)

	# 2. M4：plot 键落地（display 级 / 分支级，{"path","name"}）
	_land_plot(outcome.get("plot", null))

	# D-DOC4（2026-08-24）：empty_goto —— 可选支援槽全空时跳转至指定 turn（如失败阶段）。
	# 优先取 branch 级 empty_goto（失败分支专属），否则取 phase 级。
	# 用于「卡槽为空→失败阶段」的队伍人手检测：结算后若所有可选角色槽都空（仅剩必填执行者），
	# 路由到 empty_goto 指定的 turn。
	var empty_goto_v: Variant = outcome.get("empty_goto", null)
	if empty_goto_v == null:
		empty_goto_v = _phase.get("empty_goto", null)
	if empty_goto_v is String and String(empty_goto_v) != "":
		if _optional_character_slots_empty(_display):
			_goto_turn(String(empty_goto_v))
			return

	# 3. 检测 phase.ending（harvest / fail_harvest）→ 全流程结束
	var ending_v: Variant = _phase.get("ending", null)
	if ending_v != null:
		var ending_key: String = String(ending_v)
		_apply_harvest(ending_key)
		_finish_flow()
		return

	# 3. 路由下一个 turn（路由上下文 = 持久 player_tags + 本流程字典）
	var next := TriggerLoader.find_next_turn(_expanded, _turn_id, TriggerManager.get_routing_tags())
	if next.is_empty():
		text_label.text += "\n\n（无后续阶段，流程结束）"
		execute_btn.disabled = true
		close_btn.text = "关闭"
		print("[TriggerPopup] 无后续 turn，流程结束")
		_finish_flow()
		return

	# 4. 进入下一个 turn/phase（流程继续，字典保留累加；已放卡保留以复用执行者/工具）
	_enter_turn(String(next["turn_id"]), next["phase"])
	print("[TriggerPopup] 路由 → %s / %s" % [_turn_id, _phase_name])


## D-DOC4：直接跳转到指定 turn 的首个 phase（不经过 find_next_turn）。
func _goto_turn(turn_id: String) -> void:
	var turns: Dictionary = _expanded.get("turns", {})
	if not turns.has(turn_id):
		push_warning("TriggerPopup: empty_goto 目标 turn '%s' 不存在" % turn_id)
		_finish_flow()
		return
	var turn: Dictionary = turns[turn_id]
	var phases: Array = turn.get("phases", [])
	if phases.is_empty():
		_finish_flow()
		return
	_enter_turn(turn_id, phases[0])
	print("[TriggerPopup] empty_goto → %s" % turn_id)


## 进入指定 turn/phase（共用入口，刷新 UI）。
func _enter_turn(turn_id: String, phase: Dictionary) -> void:
	_turn_id = turn_id
	_phase = phase
	_phase_name = String(phase.get("phase", ""))
	_refresh()


## D-DOC4：检查当前 display 的所有「可选角色槽」（accept=character 且非 required）是否全空。
## 全空 → 触发 empty_goto 失败路由（无人手支援）。若存在可选角色槽但未放卡 → true。
func _optional_character_slots_empty(display: Dictionary) -> bool:
	var slots: Dictionary = display.get("slots", {})
	var has_optional := false
	for sn in slots:
		var cfg: Dictionary = slots[sn]
		if String(cfg.get("accept", "")) != "character":
			continue
		if bool(cfg.get("required", false)):
			continue
		has_optional = true
		# 该可选角色槽已放卡 → 有人手，不空
		if _placed.has(String(sn)) and _placed[String(sn)] != null:
			return false
	return has_optional


## 全流程结束：仅提交流程字典 tag 到 Player、清空字典、广播 flow_completed。
## 注意：不在此归还卡牌——执行结果出现后卡仍留在槽位，待用户关闭弹窗（close）才回卡牌区。
func _finish_flow() -> void:
	# D-DOC19：群体羁绊 —— 当触发器执行者（已放入卡槽的角色卡）超过 2 人且包含主角（Hero）时，
	# 只要流程成功完成（非 fail_harvest），为每个非主角的执行者 numtag love +1（集体协作好感累积）。
	_group_love_on_completion()
	var repeatable: bool = TriggerManager.complete_flow(_trigger_id)
	# D-S7：旅行触发器换图——必须在 complete_flow（提交 tag）之后执行，
	# 固定顺序：关弹窗 → 写 Player.path → change_scene → emit scene_entered。
	TriggerManager.execute_pending_goto_scene(self)
	flow_completed.emit(_trigger_id, repeatable, not _flow_failed)
	# D-C2：结算若配置了 dialogue → 广播「入剧情」（键名→文件见 dialogue_registry.json）。
	# D-DOC1（2026-08-24）：失败结局（_flow_failed）播 fail_harvest.dialogue，成功播 harvest.dialogue。
	# 亲历鉴定（protagonist_only）的 check==null 必走 harvest（成功）路径，故播 harvest.dialogue。
	var ending_key := "fail_harvest" if _flow_failed else "harvest"
	var dialogue_key: String = String(_expanded.get(ending_key, {}).get("dialogue", ""))
	if dialogue_key != "":
		TriggerManager.plot_requested.emit(dialogue_key)
	print("[TriggerPopup] 流程结束：%s  repeatable=%s" % [_trigger_id, repeatable])


## D-DOC19：群体羁绊（同伴情谊）—— 当已放入触发器卡槽的角色卡超过 2 人、
## 且其中含主角（Hero）时，只要流程成功完成（未走 fail_harvest），
## 为每个非主角的执行者 numtag love +1（集体协作好感随人数累积）。
## 这是唯一的好感结算规则：原先 Hero+法拉叶 双人专属的 D-DOC16 已并入本规则统一处理。
func _group_love_on_completion() -> void:
	if _flow_failed:
		return
	var hero_count := 0
	var others: Array[CardData] = []
	for sn in _placed:
		var c: CardData = _placed[sn]
		if c == null or c.card_type != "character":
			continue
		if c.id == "Hero":
			hero_count += 1
		else:
			others.append(c)
	if hero_count == 0:
		return
	# 执行者（角色卡总数）= hero_count + others.size()，必须严格 > 2 才触发
	if hero_count + others.size() <= 2:
		return
	var add_spec: Dictionary = {}
	for c in others:
		add_spec[EffectProcessor._npc_key_of(c)] = {"love": 1}
	if not add_spec.is_empty():
		EffectProcessor.apply({"npc_num_tag_add": add_spec})


## 模块专属结算路由（家业经营 GDD）—— 由 trigger 顶层 "resolver" 字段指定。
func _resolve_special(resolver: String) -> void:
	var display: Dictionary = TriggerLoader.select_display(_phase, _placed, TriggerManager.get_routing_tags())
	match resolver:
		"voyage":
			_resolve_voyage(display)
		"bookshop":
			_resolve_bookshop(display)
		"prison_break":
			_resolve_prison_break(display)
		"companion_talk":
			_resolve_companion_talk(display)
		_:
			# D-DOC14（打听）：子类可 override 的自定义 resolver 即时结算钩子。
			if not _resolve_custom(resolver, display):
				push_warning("TriggerPopup: 未知 resolver=%s，按普通流程关闭" % resolver)
				_finish_flow()


## D-DOC14（2026-08-26）：子类可 override 的自定义 resolver 即时结算钩子。
## 返回 true 表示已处理（子类内部自行落地 + 结束流程）；false 表示未处理（走 default 警告 + 关闭）。
## 子类（如 InquiryTriggerPopup）override 本方法处理专属 resolver 的即时结算。
func _resolve_custom(_resolver: String, _display: Dictionary) -> bool:
	return false


## demo 硬约束（2026-10-14 晚拍板）：神秘分支（失败的教训）彻底压掉——
## 不加 tag、不播剧情、不显占位文本。等神秘剧情落成 plot 后，把本 const 翻 false
## 即可恢复双轴判定（见 `design/家业管理触发器_阶段1.md` §3）。
const DEMO_SUPPRESS_MYSTERY := true

## 家业管理双检查结算（`design/家业管理触发器_阶段1.md` §3）—— **只算不落地**，返回统一结算字典。
##
## 2026-10-16 起改为 **duration=1 异步**：`_on_execute` → `_compute_and_freeze` 冻结界面，
## 玩家「提交」（冻结态关闭按钮）→ `_commit_action` 登记 ActionQueue，过一回合后 `ActionQueue._land` 落地
## （设计稿 §0「家业持续 1 回合」本条此前漏配 duration，一直按 0 回合即时结算）。
## 缺主管 / 护卫 → 返回空字典，`_on_execute` 据此退回即时 `_resolve_special` 显示提示、不占回合。
##
## 与旧「远洋贸易·出航」的三处差异（设计稿 §0）保持不变：
##   1. 槽位 4 → 3；2. 护卫必填（废 ×0.6）；3. 1 回合收益 5 / 25 / 50。
##
## 2026-10-14 晚口径变更（user 拍板）：
##   * 结果 headline 严格四选一 ∈ {低收益, 正常收益, 高收益, 受伤} ——
##     受伤不再与收益档 / 主管神秘叠加出现（修复原「受伤 overlay」bug）。
##   * 受伤优先：护卫 2–3 → headline=受伤（不叠收益档叙事），但利润仍按主管结算照常发放
##     （设计稿「受伤不影响本航收益」）。
##   * demo 彻底压掉神秘分支（见 `DEMO_SUPPRESS_MYSTERY`）。
## 判定骨架沿用：主管判 int&app 定收益档，护卫判 bod&str 定受伤，反 SL 种子照旧。
## 物品槽走跨触发器统一口径：只吃 bonus，直接并进 final。
##
## 返回 {effect, text, plot}：
##   effect = {money, tags:["家业已执行"], slot_tags:{槽名:[tag...]}} —— 结算时直落。
##     · `tags`「家业已执行」进 player_tags（教程门控认它）；
##     · `slot_tags` 写**角色数据**（NPC → `Player.npc` 条目；主角 → player_tags），
##       「受伤」走这条。手牌里那张旧卡实例由「打开弹窗时按 `Player.npc` 重建」刷新
##       （CardArea.refresh_from_source，方案 B），所以这里只认条目、不再写卡面。
## ⚠️ `slot_tags` 的落地依赖调用方传 `placed`（`_land` 传 ActionQueue 槽位快照 /
##    `_resolve_voyage` 传 `_placed`），否则会因 `EffectProcessor` 的空字典守卫静默不落。
func _compute_voyage_result(display: Dictionary) -> Dictionary:
	var manager: CardData = _placed.get("主管", null)
	var guard: CardData = _placed.get("护卫", null)
	if manager == null or guard == null:
		return {}

	# 货物槽物品 bonus：int/app 给主管，bod/str 给护卫（设计稿 §3 的 bonus_m / bonus_g）。
	var cargo: CardData = _placed.get("货物", null)
	var bonus_m := 0
	var bonus_g := 0
	if cargo != null and cargo.card_type == "item":
		bonus_m = cargo.get_bonus("int") + cargo.get_bonus("app")
		bonus_g = cargo.get_bonus("bod") + cargo.get_bonus("str")

	var mod_m: int = _attr_mod(manager.attrs, {"int": 5, "app": 5})
	var roll_m: int = Player.roll_dice("voyage:manager:%s" % _trigger_id, 10, _voyage_extra(manager, guard))
	var final_m: int = roll_m + mod_m + bonus_m

	var mod_g: int = _attr_mod(guard.attrs, {"bod": 5, "str": 5})
	var roll_g: int = Player.roll_dice("voyage:guard:%s" % _trigger_id, 10, _voyage_extra(guard, manager))
	var final_g: int = roll_g + mod_g + bonus_g

	# 结算：先算三个 flag（mystery_guard / mystery_manager / injured）与 profit，
	# 四者互斥地决定结果 headline（mystery 仅在非 demo 时可能出现，见下）。
	var profit: int = 0
	var injured := false
	var mystery_guard := false
	var mystery_manager := false
	var slot_tags: Dictionary = {}

	if not DEMO_SUPPRESS_MYSTERY:
		# —— 神秘分支（非 demo，待神秘剧情落成后启用）——
		# §3.4 组合与优先级：先判护卫。护卫 ≤1 → 护卫神秘，主管即便也 ≤1 也不触发、不加 tag。
		if final_g <= 1 and not _card_has_tag(guard, "失败的教训"):
			slot_tags["护卫"] = ["失败的教训"]
			final_g = max(final_g, 2)  # §3.3 地板 2
			mystery_guard = true
		elif final_m <= 1 and not _card_has_tag(manager, "失败的教训"):
			slot_tags["主管"] = ["失败的教训"]
			final_m = max(final_m, 2)
			mystery_manager = true
		else:
			# §3.3 主管档位（1 回合平衡：5 / 25 / 50）
			if final_m <= 1:
				profit = 0
			elif final_m <= 3:
				profit = 5
			elif final_m <= 6:
				profit = 25
			else:
				profit = 50
		# 护卫 2–3 → 加「受伤」（不影响本航收益，仅禁未来出航）
		if final_g >= 2 and final_g <= 3:
			slot_tags["护卫"] = (slot_tags.get("护卫", []) as Array) + ["受伤"]
			injured = true
	else:
		# —— demo 四选一（现役）——
		# 受伤优先：护卫 2–3 → headline=受伤（不叠收益档叙事），利润仍按主管结算照常发放。
		if final_g >= 2 and final_g <= 3:
			slot_tags["护卫"] = ["受伤"]
			injured = true
		# 收益档（连续化：final_m ≤3→5 / 4-6→25 / 7+→50；原 ≤1→0 的神秘档随神秘一并压掉）
		if final_m <= 3:
			profit = 5
		elif final_m <= 6:
			profit = 25
		else:
			profit = 50

	# §3.5 奖励在结算时落账（D-F5）。
	# 「家业已执行」：本航次真的跑了（主管/护卫齐、判定走过）才落地 —— 教程门控认它
	# （2026-10-14 用户拍板：执行过家业才放行「过回合 / 返回主城」）。
	return {
		"effect": {"money": profit, "tags": ["家业已执行"], "slot_tags": slot_tags},
		"text": _voyage_report(display, profit, injured, mystery_guard, mystery_manager),
		"plot": "",
	}


## 家业管理**即时**结算（duration=0 兜底：异常存档缺 duration，或验收探针直调）。
## 判定与异步完全共用 `_compute_voyage_result`，这里只多做「立刻落地」这一步。
func _resolve_voyage(display: Dictionary) -> void:
	var manager: CardData = _placed.get("主管", null)
	if manager == null:
		_append_result("家业需要一名主管。")
		_finish_flow()
		return
	var guard: CardData = _placed.get("护卫", null)
	if guard == null:
		_append_result("家业需要一名护卫。")
		_finish_flow()
		return

	var res: Dictionary = _compute_voyage_result(display)
	# money / tags 走 flow_tags，随 _finish_flow → complete_flow 提交，与异步落地同一结果。
	# 🔴 slot_tags（护卫「受伤」）靠 `placed` 定位施加对象 —— 必须把 `_placed` 传进去；
	#    不传时 `EffectProcessor` 那条 `not placed.is_empty()` 守卫会让它静默不落地。
	var effect: Dictionary = res.get("effect", {})
	if not effect.is_empty():
		TriggerManager.apply_effect(effect, _placed)
	_append_result(String(res.get("text", "")))
	_finish_flow()


## 家业结算的叙述文本（设计稿 §5）。占位符 `{主管}` / `{护卫}` 经 TextVars 换成放进槽那张卡的名字；
## 该槽放的是主角（Hero）时这三段改第二人称（§5.1），否则「他把账算得很清楚」成了主角对着自己讲。
## 结果 headline 严格四选一（优先级：护卫神秘 > 主管神秘 > 受伤 > 收益档），末尾永远单独一行「收益 +N」。
func _voyage_report(display: Dictionary, profit: int, injured: bool, mystery_guard: bool, mystery_manager: bool) -> String:
	var manager: CardData = _placed.get("主管", null)
	var guard: CardData = _placed.get("护卫", null)
	var ctx: Dictionary = _build_slot_context(display)
	var lines: Array[String] = []
	# headline 四选一（优先级：护卫神秘 > 主管神秘 > 受伤 > 收益档）
	if mystery_guard:
		if guard != null and guard.id == "Hero":
			lines.append("货是好货，船是好船，价钱也谈拢了。黄就黄在你自己身上，你非说守夜那晚货舱里有人在清点，而且数得比谁都准。买主不肯跟一个对着空货舱打招呼的人做买卖。")
		else:
			lines.append(TextVars.resolve("货是好货，船是好船，价钱也谈拢了。黄就黄在{护卫}身上，他非说守夜那晚货舱里有人在清点，而且数得比他还准。买主不肯跟一个对着空货舱打招呼的人做买卖。", ctx))
	elif mystery_manager:
		if manager != null and manager.id == "Hero":
			lines.append("这一切都要从一只燃烧的犀牛角说起。")
		else:
			lines.append(TextVars.resolve("{主管}把账算得很清楚，就是不肯说海上的事。见他讳莫如深，你忽然想起一个有关犀牛的传闻。", ctx))
	elif injured:
		# 受伤 headline：不叠收益档叙事（利润数字仍在末尾「收益 +N」行单独给）。
		if guard != null and guard.id == "Hero":
			lines.append("明天和意外哪一个会先来临，半死不活的你终于想清楚，如果再不救救自己，你就可以先一步去见见意外了。")
		else:
			lines.append(TextVars.resolve("明天和意外哪一个会先来临，半死不活的{护卫}告诉你，如果再不救救他，他就可以先一步去见见意外了。", ctx))
	elif profit <= 5:
		lines.append("人才是最宝贵的财富，大家平安无事便是最大的收获。")
	elif profit <= 25:
		lines.append("月有圆缺，人有离合。波动的中规中矩的收获，不过这仍然证明了你的能力，挑选人的能力。")
	else:
		lines.append("抱歉，刚才没有认出您大人。多亏了你的聪明才智，贸易大丰收，虽然你的聪明才智没有一点用在了具体的生意上。")

	lines.append("收益 +%d。" % profit)
	return "\n".join(lines)


## 越狱结算（D-DOC13，法拉叶招揽线第二章）。
## 阶段1：1d str + 1d bod − 2×越狱次数；<1 失败、≥1 成功。
## 失败阶段二次判定：1d bod ≥ 4 或 执行者带「神偷」→ 软失败（躲藏，无损失）；否则硬失败（money −5）。
## 越狱次数：每次尝试开始前 +1（首次也计入惩罚，Q3）→ 递增作为 slot_num_tags 效果随结算落地。
## 成功：移除执行者「监狱内」tag（slot_remove_tags）。
## 只算不落地，返回统一结算字典 {effect, text, plot}（异步等待流程用）。
func _compute_prison_break_result(_display: Dictionary) -> Dictionary:
	var executor: CardData = _placed.get("执行者", null)
	if executor == null:
		return {"effect": {}, "text": "越狱需要一名执行者。", "plot": ""}
	# 越狱次数 +1（每次尝试开始前）
	var n := _performer_num_tag(executor, "越狱次数") + 1
	var incr_effect: Dictionary = {"slot_num_tags": {"执行者": {"越狱次数": {"add": 1}}}}
	var name := executor.display_name
	var salt := _placed_salt()
	# 阶段1：1d str + 1d bod − 2×越狱次数
	var total := _roll_attr_die(executor, "str", salt) + _roll_attr_die(executor, "bod", salt) - 2 * n
	if total >= 1:
		var text := "人们常说离家出走的孩子终会迷途知返，也许某一天%s还会回来进修，不过现在他可以尽情享受自由的空气。" % name
		# 越狱成功：法拉叶好感 love 置为基线 2（招揽成功；两种越狱方式暂不分）。
		# D-FOLLOW1（2026-10-16）：越狱成功 = 法拉叶正式入队 → 授「追随」tag（入队 tag），
		# EffectProcessor 见到它会把法拉叶卡自动补进手牌；但**手牌上限**仍由主 UI 决定。
		# 2026-10-22：同时把「法拉叶闲聊_love2」（坦白舞春神 → 给藏身处钥匙）排进他的待聊队列，
		# 玩家回家走「与同伴交流」即可聊到——这是坦白剧情目前唯一的入口。
		var effect := _merge_effect(incr_effect, {
			"slot_remove_tags": {"执行者": ["监狱内"]},
			# 2026-10-23：玩家侧同时落「法拉叶入队」—— 家里「表白」点位的 show_when 只认这条 tag
			# （npc 条目上的「追随」读不到 show_when 的 tags，npc_tags 又会在条目还没建出来时刷 warning）。
			"tags": ["法拉叶入队"],
			"npc": {"法拉叶": {"num_tags": {"love": 2}, "tags": ["追随"]}},
			"enqueue_talk": {"法拉叶": [
				# 2026-10-22：坦白舞春神 → 给藏身处钥匙（回家走「与同伴交流」聊，唯一的坦白入口）。
				{"path": "res://resoures/characters/falayee.json", "name": "法拉叶闲聊_love2"},
				# 2026-10-24：公园邀约也走待聊队列（「有话说」不占地图点击入口），排坦白之后 FIFO；
				# 末句落 tag「法拉叶的邀约」→ 主城「公园」触发点显形。
				{"path": "res://resoures/plot/falayee/公园的邀约.json", "name": "公园的邀约"},
			]},
		})
		return {"effect": effect, "text": text, "plot": ""}
	# 失败阶段二次判定：1d bod ≥ 4 或 神偷
	var bod_roll := _roll_attr_die(executor, "bod", salt + "|fail")
	var has_thief := executor.has_tags(["神偷"], 1)
	if has_thief or bod_roll >= 4:
		var text := "晦暗之月，呼啸之风。这本应是自由的时机，可惜只能仓促躲藏另觅良机了。"
		return {"effect": incr_effect, "text": text, "plot": ""}
	var text := "壁虎断尾求生，想把一切当无事发生总需要一些东西转移狱卒的注意。"
	var effect := _merge_effect(incr_effect, {"money": -5})
	return {"effect": effect, "text": text, "plot": ""}


## 越狱即时落地版（无 duration 的兜底），复用 _compute_prison_break_result。
func _resolve_prison_break(_display: Dictionary) -> void:
	var r: Dictionary = _compute_prison_break_result(_display)
	if not r.get("effect", {}).is_empty():
		TriggerManager.apply_effect(r.effect, _placed)
	_append_result(r.get("text", ""))
	_finish_flow()


## 与同伴交流结算（家·与同伴交流 GDD）。
## 读槽位角色（第一个 character 槽）→ 找对应 NPC 条目 → pop 待聊队列 talk_queue 队首
## → 动态 PlotImporter.add_plot 按序播剧情 → 该 NPC「有话可说」num_tag −1（归零则清键）。
## 队列空 → 提示「无话可说」，直接结束流程（不消耗）。
func _resolve_companion_talk(display: Dictionary) -> void:
	var slot_name := _first_character_slot(display)
	var card: CardData = _placed.get(slot_name, null)
	if card == null:
		_append_result("需要选择一名同伴。")
		_finish_flow()
		return
	var npc_key := EffectProcessor._npc_key_of(card)
	if not Player.npc.has(npc_key):
		_append_result("%s现在没什么想跟你说的。" % card.display_name)
		_finish_flow()
		return
	var entry: Dictionary = Player.npc[npc_key]
	if not entry.has("num_tags"):
		entry["num_tags"] = {}
	var queue: Array = entry.get("talk_queue", [])
	if queue.is_empty():
		_append_result("%s现在没什么想跟你说的。" % card.display_name)
		_finish_flow()
		return
	var plot: Variant = queue.pop_front()
	# 有话可说 −1（归零即清键，下次该 NPC 不再命中门控）。Hero 走 player_num_tags（与门控一致）。
	if npc_key == "Hero":
		var hcur := int(Player.player_num_tags.get("有话可说", 0))
		Player.player_num_tags["有话可说"] = max(0, hcur - 1)
		if int(Player.player_num_tags["有话可说"]) <= 0:
			Player.player_num_tags.erase("有话可说")
	else:
		var cur := int(entry["num_tags"].get("有话可说", 0))
		entry["num_tags"]["有话可说"] = max(0, cur - 1)
		if int(entry["num_tags"]["有话可说"]) <= 0:
			entry["num_tags"].erase("有话可说")
	# 播剧情（对话 id 沿用 plot 键格式 {path,name}）
	if plot is Dictionary:
		var p: Dictionary = plot
		var pp := String(p.get("path", ""))
		var pn := String(p.get("name", ""))
		# 2026-10-10（周游线）：talk 条目可自带 effect —— 谈完即按**当前槽位**落地
		# （slot_tags / slot_remove_tags / tags 等，placed 就是本次放进「执行者」槽的那张卡）。
		# 用途：《雨国游记》读者谈完 → 执行者得「周游队长」、摘掉「雨国游记」，玩家得「事件周游」
		#   → 家里随之长出「周游」触发点（show_when 检测 tags）。
		# 顺序要求：必须在 _finish_flow 之前 apply —— tags 先进 _flow_tags，随 complete_flow 一并提交；
		#   放到 _finish_flow 之后就会漏提交（流程字典已清空）。
		var talk_eff: Variant = p.get("effect", null)
		if talk_eff is Dictionary and not (talk_eff as Dictionary).is_empty():
			TriggerManager.apply_effect(talk_eff, _placed)
		if pp != "" and pn != "":
			PlotImporter.add_plot(pp, pn, _build_plot_context())
	_finish_flow()


## 取当前 display 的第一个「人物」槽名（与同伴交流单槽用）。
func _first_character_slot(display: Dictionary) -> String:
	var slots: Dictionary = display.get("slots", {})
	for sn in slots:
		var cfg: Dictionary = slots[sn]
		if String(cfg.get("accept", "")) == "character":
			return String(sn)
	return ""


## 书店购书结算（参考密教模拟器/苏丹的游戏「书肆买书」）。
## 分档依据：顾客(人物槽)的智力 int。
##   int<=2  → 「没看到什么合适的书」（不购书、不花钱）
##   int<=5  → 花 3、大概率低品质（S 加权高）
##   int>=6  → 花 1、大概率高品质（SSR 加权高）
## 按档位加权从 books.json 随机抽一本入背包（排除已拥有的书，绝不重复）。
## 物品槽若带「书店剧情xxx」标签则触发对应剧情（尚未实装，仅检测+占位）。
##
## _compute_bookshop_result：只算不落地，返回统一结算字典
##   {effect, text, plot, book_card?, book_id?}（异步等待流程用）。
## _resolve_bookshop：即时落地版（无 duration 的兜底），复用上面的计算。

func _compute_bookshop_result(_display: Dictionary) -> Dictionary:
	# 书架读尽 → 白桦书肆闭店。返回**空字典** = 「本次没有可结算的购书结果」：
	# `_on_execute` 见空会退回即时 `_resolve_special`（不冻结、不占回合），
	# 由 `_resolve_bookshop` 走闭店支线。这是「闭店只是看一眼，不该花掉一天」的落点。
	if Player.player_has_tags([ALL_BOOKS_TAG], 1):
		return {}
	var buyer: CardData = _placed.get("人物", null)
	if buyer == null:
		return {"effect": {}, "text": "书店需要一位顾客。", "plot": ""}

	var int_val: int = int(buyer.attrs.get("int", 0))

	# 物品槽：检测「书店剧情xxx」标签（尚未实装，占位）。
	# 2026-10-14：检测保留，但不再写进结算正文（原「对应剧情尚未实装，待接入」是开发痕迹）。
	var item: CardData = _placed.get("物品", null)
	if item != null:
		for t in item.tags:
			var ts: String = String(t)
			if ts.begins_with("书店剧情"):
				push_warning("[TriggerPopup] 书店剧情物品尚未接入：%s" % ts)

	# 智力分档（用户修订：≤2 没书 / ≤5 花3低品质 / ≥6 花1高品质）
	if int_val <= 2:
		return {"effect": {}, "text": "没看到什么合适的书。", "plot": ""}

	var cost: int = 3 if int_val <= 5 else 1
	var tier: String = "low" if int_val <= 5 else "high"

	if Player.player_money < cost:
		return {"effect": {}, "text": "你相中了一本书，手头的钱却还差 %d。" % [cost - Player.player_money], "plot": ""}

	var books: Dictionary = _load_books()
	if books.is_empty():
		push_error("[TriggerPopup] 书店取不到书目：books.json 为空或读取失败")
		return {"effect": {}, "text": "店里今天没有新书可进。", "plot": ""}

	var book_id: String = _roll_book(books, tier)
	if book_id == "":
		return {"effect": {}, "text": "店里的书你都已读过，再无新货可购。", "plot": ""}

	var book: Dictionary = books.get(book_id, {})
	var gain: int = int(book.get("after_read", {}).get("attrs", {}).get("int", 0))
	var card: CardData = CardData.from_book(book_id, book)
	var name: String = String(book.get("name", book_id))
	var lead: String
	if int_val <= 5:
		lead = "买到书了"
	else:
		lead = "我与老板意气相投，老板几乎是把书送我的"
	var text: String = "%s——你花掉 %d，购入《%s》，研读后智力 +%d。" % [
		lead, cost, name, gain]
	var effect: Dictionary = {"money": -cost, "stuff": ["book:%s" % book_id]}
	return {"effect": effect, "text": text, "plot": "", "book_card": card, "book_id": book_id}


func _resolve_bookshop(_display: Dictionary) -> void:
	var r: Dictionary = _compute_bookshop_result(_display)
	if r.is_empty():
		_resolve_bookshop_closed()
		return
	if r.has("effect") and not r.effect.is_empty():
		TriggerManager.apply_effect(r.effect, _placed)
	if r.has("book_card") and r.book_card != null:
		book_acquired.emit(r.book_card)
	_append_result(r.get("text", ""))
	_finish_flow()


## 白桦书肆闭店结算（书架读尽，2026-10-16 犹格索托斯之所）：**不占回合**。
## 落「书店关闭」tag（= 「调查书店」的 show_when 门控），播关店剧情。
## 剧情走 `plot`（结果文案留在弹窗里、剧情叠在上层）——与「调查丹尼斯」分支级 plot 同一套。
## 走 `TriggerManager.apply_effect` 而不是直接写 Player：tags 进流程字典，由 `_finish_flow()`
## 统一提交，与触发器其它 effect 的落地口径一致。
func _resolve_bookshop_closed() -> void:
	TriggerManager.apply_effect({"tags": [BOOKSHOP_CLOSED_TAG]}, _placed)
	_land_plot({"path": BOOKSHOP_PLOT, "name": "书店关闭"})
	_append_result("白桦书肆关了门。")
	_finish_flow()


## 书架是否读尽（2026-10-16）：books.json 里每本书的 `after_read.player_tags`（已读标记）
## 都在玩家身上。`reading_book` = 本次正在读的书 id —— 它的标记还没落地，按「已读」算
## （读最后一本时靠这个参数把当次排除掉）。
##
## 数据驱动：加新书只要 books.json 里配了 player_tags，本函数不用改；
## 任一本书没配标记 → 恒 false（宁可闭店判定不生效，也不误判成读尽）。
func _books_all_read(reading_book: String = "") -> bool:
	var books: Dictionary = _load_books()
	if books.is_empty():
		return false
	for id in books:
		if String(id) == reading_book:
			continue
		var ar_v: Variant = books[id].get("after_read", null)
		if not (ar_v is Dictionary):
			return false
		var marks: Variant = (ar_v as Dictionary).get("player_tags", null)
		if not (marks is Array) or (marks as Array).is_empty():
			return false
		if not Player.player_has_tags(marks, 1):
			return false
	return true

func _roll_book(books: Dictionary, tier: String) -> String:
	# 已拥有的书（不重复获得）
	var owned: Dictionary = {}
	for s in Player.player_stuff:
		if typeof(s) == TYPE_STRING and String(s).begins_with("book:"):
			owned[String(s).substr(5)] = true
	var weights := {
		"S": 70 if tier == "low" else 10,
		"SR": 25 if tier == "low" else 30,
		"SSR": 5 if tier == "low" else 60,
	}
	var pool: Array = []
	var total := 0
	for id in books:
		if owned.has(String(id)):
			continue
		var lvl: String = String(books[id].get("level", ""))
		var w: int = int(weights.get(lvl, 0))
		if w <= 0:
			continue
		pool.append({"id": String(id), "w": w})
		total += w
	if total <= 0 or pool.is_empty():
		return ""
	var buyer: CardData = _placed.get("人物", null)
	var salt: String = str(Player.time) + "|" + (buyer.id if buyer != null else "")
	var r: int = Player.roll_dice("bookshop:%s" % _trigger_id, total, salt) - 1
	for entry in pool:
		r -= entry["w"]
		if r < 0:
			return String(entry["id"])
	return String(pool[pool.size() - 1]["id"])

func _load_books() -> Dictionary:
	if _books_cache_ready:
		return _books_cache
	var file := FileAccess.open(BOOKS_PATH, FileAccess.READ)
	if file == null:
		push_error("TriggerPopup: 无法打开 %s" % BOOKS_PATH)
		_books_cache_ready = true
		return {}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		_books_cache_ready = true
		return {}
	_books_cache = data
	_books_cache_ready = true
	return _books_cache


# ============================================================
#  卡牌标签辅助
# ============================================================
#
# ⚠️ 只保留**只读**判定（`_card_has_tag`）。原先还有一对 `_card_add_tag` / `_card_remove_tag`
#    直接写 `CardData.tags`，随家业 `card_tags` 补丁一并删除（2026-10-16 方案 B）。
#    原因：写卡实例是「会话内有效」的假持久 —— 卡实例是进手牌那一刻的快照，下次打开触发器
#    弹窗就会被 `CardArea.refresh_from_source` 按 `Player.npc` 重建，写进去的 tag 无声蒸发。
#    要持久地给角色加 tag，一律走 `effect.slot_tags`（写 `Player.npc` 条目 / player_tags）。

func _card_has_tag(card: CardData, tag: String) -> bool:
	if card == null:
		return false
	return card.has_tags([tag], 1)


## 属性加权均值 → 修正值 mod = clamp(均值-5, -4, +4)（家业经营 GDD §3.1）。
func _attr_mod(attrs: Dictionary, weights: Dictionary) -> int:
	var mean: int = CardData.weighted_x(attrs, weights)
	return clampi(mean - 5, -4, 4)


## 反 SL 额外盐：当前天 + 主/副卡 id，确保同卡同天恒定、不同卡/天不同（D-F4）。
func _voyage_extra(primary: CardData, other: Variant) -> String:
	var extra := str(Player.time) + "|" + (primary.id if primary != null else "")
	if other is CardData:
		extra += "|" + other.id
	return extra


func _append_result(text: String) -> void:
	text_label.text += "\n" + text


## 构建文本变量上下文：把已放卡映射为 {槽位名}→卡名 与 card.<槽>.* 命名空间。
## 未放置的槽位也预置空串，避免无谓的未解析告警。
func _build_slot_context(display: Dictionary) -> Dictionary:
	var ctx: Dictionary = {}
	var slots: Dictionary = display.get("slots", {})
	for sn in slots:
		ctx[String(sn)] = ""
		ctx["card.%s.name" % sn] = ""
	for s in _placed:
		var c: CardData = _placed[s]
		if c == null:
			continue
		ctx[String(s)] = c.display_name
		ctx["card.%s.name" % s] = c.display_name
		ctx["card.%s.tags" % s] = ", ".join(c.tags)
		ctx["card.%s.desc" % s] = c.description
		for a in ["int", "app", "str", "bod"]:
			ctx["card.%s.%s" % [s, a]] = c.attrs.get(a, 0)
	# 执行者命名空间（{executor_name}/{executor.name}/{executor.int}/... = 执行者而非主角）：
	# 默认取「执行者」槽卡，否则首个角色卡；同时注入 executor.* 各字段供 {executor.x} 解析。
	if not ctx.has("executor_name"):
		var exec_card: CardData = null
		if _placed.has("执行者") and _placed["执行者"] != null:
			exec_card = _placed["执行者"]
		else:
			for s2 in _placed:
				var cc: CardData = _placed[s2]
				if cc != null and cc.card_type == "character":
					exec_card = cc
					break
		if exec_card != null:
			ctx["executor_name"] = exec_card.display_name
			ctx["executor.name"] = exec_card.display_name
			ctx["executor.tags"] = ", ".join(exec_card.tags)
			ctx["executor.desc"] = exec_card.description
			for a in ["int", "app", "str", "bod"]:
				ctx["executor." + a] = exec_card.attrs.get(a, 0)
	return ctx


## 应用 harvest / fail_harvest 效果并关闭
func _apply_harvest(ending_key: String) -> void:
	if ending_key == "fail_harvest":
		_flow_failed = true
	var harvest_effect: Dictionary = _expanded.get(ending_key, {}).get("effect", {})
	if not harvest_effect.is_empty():
		TriggerManager.apply_effect(harvest_effect, _placed)
	text_label.text += "\n\n— 阶段结束（%s）—" % ending_key
	if not harvest_effect.is_empty():
		text_label.text += "\n获得：%s" % str(harvest_effect)
	execute_btn.disabled = true
	close_btn.text = "关闭"
	print("[TriggerPopup] %s 已应用 %s effect=%s" % [ending_key, ending_key, str(harvest_effect)])


# ============================================================
#  长按 / 拖动移动整个弹窗
# ============================================================

func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_long_pressed = false
			_press_pos = get_global_mouse_position()
			_drag_offset = _press_pos - panel.global_position
			_press_time = Time.get_ticks_msec()
			set_process(true)
		else:
			_dragging = false
			set_process(false)
	elif event is InputEventMouseMotion and _dragging:
		_try_move()


func _process(_delta: float) -> void:
	if _dragging:
		_try_move()


func _try_move() -> void:
	var held := float(Time.get_ticks_msec() - _press_time)
	var moved := get_global_mouse_position() - _press_pos
	if moved.length() > DRAG_THRESHOLD or held > LONG_PRESS_MS:
		_drag_long_pressed = true
	if _drag_long_pressed:
		panel.global_position = get_global_mouse_position() - _drag_offset
