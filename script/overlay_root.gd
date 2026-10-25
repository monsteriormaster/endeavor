extends Node

## 统一覆盖层管理器（autoload `OverlayRoot`）—— 落地《主UI交互策划案》§6.4，关闭缺陷 D-UI6。
##
## 解决的问题：此前各弹窗分散 `add_child` 到不同父节点（tree.root / 当前场景 / main_ui），
## 叠放顺序靠"谁后加谁在上"隐式决定，Esc 语义各组件自行 `_input` 抢，没有输入门控。
##
## 结构（自下而上）：
##   Layer 0            主场景地图 + 常驻 HUD
##   BusinessLayer(50)  业务覆盖层（TriggerPopup / DialogueUI / Newspaper / CheckUI /
##                      CharacterPanel / ConfirmDialog / SettingsMenu）+ 模态输入拦截层
##   TutorialLayer(100) 教学覆盖层（始终压在业务层之上）
##   DragLayer(200)     拖拽预览层 —— 拖拽中的卡牌永远压在最上（见 DRAG_PREVIEW_LAYER）
##
## 用法：
##   OverlayRoot.push_overlay(popup, {"modal": true, "esc_closes": true, "close_method": "close"})
##   OverlayRoot.close_overlay(popup)      # 组件自己的关闭流程末尾调用；返回 false 表示未托管
##   OverlayRoot.close_top()               # Esc 语义：只关最上层
##   OverlayRoot.add_tutorial_overlay(n)   # 教学层，不进模态栈
##
## options 字段：
##   modal        bool   默认 true。true 时在其下方插入全屏输入拦截层，地图/HUD 不可戳。
##   esc_closes   bool   默认 true。Esc 是否可以关掉它（只作用于栈顶）。
##   close_method String 默认 ""。非空时 Esc 走组件自身的关闭方法（保证其 closed 信号/收尾逻辑跑到）。
##   persist      bool   默认 false。true 则场景切换时不自动关闭。
##   exclusive    bool   默认 true。只对 Window 派生的覆盖层有效（PopupPanel / AcceptDialog…）。
##                       Window 是嵌入子窗口，**exclusive=true 会把落在窗口外的点击整个吞掉**：
##                       拦截层收不到、手牌也收不到，于是「点面板外收起」根本无从触发。
##                       这类面板要设 false —— 挡输入交给 ModalBlocker，不必靠独占。
##   outside_click_closes bool 默认 false。true 时**点 ModalBlocker（= 面板外）就关掉它**。
##                       若那一下正好落在手牌卡上，顺手把点击转给那张卡 ——
##                       于是一次点击同时完成「关掉旧面板 + 打开新面板」（见 close_with_click_through）。
##
## 生命周期：
##   - 覆盖层被 `queue_free()` 自行销毁时，通过 `tree_exited` 自动出栈，不会留下悬空条目。
##   - 场景切换（SceneTree.scene_changed）时，自动关闭"属于旧场景"的覆盖层；
##     在新场景 `_ready` 里呼出的覆盖层（此时 current_scene 已是新场景）不会被误杀。

## 业务覆盖层的 CanvasLayer 层号（高于地图/HUD 的默认 layer 0）
const BUSINESS_LAYER := 50
## 教学覆盖层层号（GDD §2.1 Layer 2：始终最上，不被业务层遮挡）
const TUTORIAL_LAYER := 100
## 拖拽预览层号。**必须高于业务层与教学层** —— 引擎会把 `force_drag` 的预览挂到
## 「发起点所在的最外层 Control」下（与发起控件**同层**），于是从卡牌区拖卡时预览落在
## Layer 0，拖到触发器弹窗（BusinessLayer 50）上就被盖住了。`Control.top_level` 只让它
## 脱离父级**变换**，不改变它所属的 **canvas 层**，所以必须靠独立 CanvasLayer 抬层。
const DRAG_PREVIEW_LAYER := 200

## 模态拦截层颜色。默认全透明——只做输入门控，不改变现有观感。
## 若将来要做"模态压暗"，把 alpha 调到 0.25 左右即可。
const BLOCKER_COLOR := Color(0, 0, 0, 0)

## 覆盖层入栈 / 出栈广播（供调试或未来的焦点栈使用）
signal overlay_pushed(node: Node)
signal overlay_closed(node: Node)

var _business: CanvasLayer = null
var _tutorial: CanvasLayer = null
var _drag: CanvasLayer = null
var _blocker: ColorRect = null
## 拦截层当前「为哪个覆盖层站岗」。只有它标了 `outside_click_closes` 时，点拦截层才会关人。
var _blocker_owner: Node = null
## 业务覆盖层模态栈，元素为 Dictionary：
## {node, modal, esc_closes, close_method, persist, exclusive, outside_click_closes, scene}
var _stack: Array[Dictionary] = []


func _ready() -> void:
	# 覆盖层要在暂停时也能响应（未来若加暂停菜单）
	process_mode = Node.PROCESS_MODE_ALWAYS

	_business = CanvasLayer.new()
	_business.name = "BusinessLayer"
	_business.layer = BUSINESS_LAYER
	add_child(_business)

	_tutorial = CanvasLayer.new()
	_tutorial.name = "TutorialLayer"
	_tutorial.layer = TUTORIAL_LAYER
	add_child(_tutorial)

	_drag = CanvasLayer.new()
	_drag.name = "DragPreviewLayer"
	_drag.layer = DRAG_PREVIEW_LAYER
	add_child(_drag)

	_blocker = ColorRect.new()
	_blocker.name = "ModalBlocker"
	_blocker.color = BLOCKER_COLOR
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.visible = false
	_blocker.gui_input.connect(_on_blocker_gui_input)
	_business.add_child(_blocker)

	get_tree().scene_changed.connect(_on_scene_changed)


# ============================================================
#  公共 API
# ============================================================

## 呼出一个业务覆盖层。node 未入树时挂到业务层，已入树则原地接管。
## 返回传入的 node，便于链式调用。
func push_overlay(node: Node, options: Dictionary = {}) -> Node:
	if node == null:
		push_error("OverlayRoot: push_overlay 收到 null")
		return null
	if _index_of(node) != -1:
		return node

	var entry: Dictionary = {
		"node": node,
		"modal": bool(options.get("modal", true)),
		"esc_closes": bool(options.get("esc_closes", true)),
		"close_method": String(options.get("close_method", "")),
		# persist 必须是独立字段，不能用 "scene == null" 表示。
		# Godot 的坑：已被释放的对象与 null 比较会返回 true，
		# 旧场景销毁后 scene 字段就"变成 null"，常驻判断会误命中 → 覆盖层永远清不掉。
		"persist": bool(options.get("persist", false)),
		"exclusive": bool(options.get("exclusive", true)),
		"outside_click_closes": bool(options.get("outside_click_closes", false)),
		"scene": get_tree().current_scene,
	}
	_stack.append(entry)

	_attach(node, _business, bool(entry["exclusive"]))
	# 组件自行 queue_free 时自动出栈，避免悬空条目
	node.tree_exited.connect(_on_overlay_tree_exited.bind(node), CONNECT_ONE_SHOT)

	_refresh_blocker()
	overlay_pushed.emit(node)
	return node


## 教学覆盖层：挂到最高层，不进模态栈、不拦输入、不随场景切换销毁。
func add_tutorial_overlay(node: Node) -> Node:
	if node == null:
		return null
	_attach(node, _tutorial, true)
	return node


## 关闭并销毁一个受管覆盖层。返回 false 表示它不在栈里（调用方应自行兜底 queue_free）。
## 组件自身的 close() 末尾调用本函数即可，不会与 close_top() 造成重复释放。
func close_overlay(node: Node) -> bool:
	var idx: int = _index_of(node)
	if idx == -1:
		return false
	_stack.remove_at(idx)
	_refresh_blocker()
	overlay_closed.emit(node)
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		if node is Window:
			# 延迟 hide：避免在 _input / GUI input 回调栈内同步 hide Window 导致
			# Viewport 输入状态损坏（表现为"点击弹窗外 → 弹窗消失 → 全局卡死"）。
			# queue_free 本身延迟，free 时也会释放 grab，故这里只把 hide 挪到下一帧。
			node.hide.call_deferred()
		node.queue_free()
	return true


## 点「面板外」时用：按组件自己的关闭方法收掉它，并把这一下点击**转交**给落点处的那张手牌。
##
## 为什么要有它（2026-10-23 用户拍板的行为）：
##   面板在场时，面板外的一切点击都被 ModalBlocker / 全屏遮罩吃掉 —— 于是「点另一张卡」
##   第一次只是把面板关掉，玩家必须再点第二次才能打开另一张卡的详情，一步交互拆成两步。
##   这里在关掉的同时把点击转给那张卡，一次点击就完成「换面板」。
##
## ⚠️ 只能转**手牌**卡（`CardArea` 的 chip）—— 地图人物卡 / 卡槽里的卡都不接受点击，
##   转过去也不会有人响应。落点不在卡上时只关面板，什么都不做（那一击被吞掉是对的）。
## ⚠️ 先算出落点上的 chip，再关面板：关闭过程可能触发 `_refresh_blocker()` 与布局回调，
##   把顺序反过来会拿到一个已经不在树上的 chip。
##
## 开这类面板的组件请给自己挂一条 meta `card_panel_key`（= 这张卡 id 或显示名）：
##   · 落点是**同一张卡** → 只收起、不重开（否则玩家点自己刚打开的那张卡，面板会「闪一下又回来」，
##     看起来像点不动）；· 落点是别的卡 → 收起后把点击转过去，一次点击换面板。
func close_with_click_through(node: Node, at: Vector2) -> void:
	var chip := _hand_chip_at(at)
	var same_card := false
	if chip != null and is_instance_valid(chip) and chip.card != null and is_instance_valid(node):
		same_card = String(node.get_meta("card_panel_key", "")) == _card_key_of(chip.card)
	_close_by_entry(node)
	if same_card or chip == null or not is_instance_valid(chip) or chip.card == null:
		return
	# 同步 emit：`clicked` 的上游是 `main_ui._on_card_clicked`，它自己用 deferred 开面板，
	# 所以不会在本回调栈里再 add_child（那会踩 "Parent node is busy setting up children"）。
	chip.clicked.emit(chip.card)


## 卡的标识口径与 `CardArea._card_id_of()` 一致：有 id 用 id，没有用显示名。
func _card_key_of(card: CardData) -> String:
	return card.id if card.id != "" else card.display_name


## 按 entry 的 close_method 关掉一个覆盖层（Esc 与「点外收起」共用这一条收尾路径）。
func _close_by_entry(node: Node) -> void:
	var entry: Dictionary = _entry_of(node)
	var method := String(entry.get("close_method", ""))
	if method != "" and is_instance_valid(node) and node.has_method(method):
		node.call(method)
		# 兜底：组件的关闭方法若没回调 close_overlay，这里补出栈
		if _index_of(node) != -1:
			close_overlay(node)
		return
	close_overlay(node)


## 落点处的手牌卡（不在手牌上 → null）。查找口径交给 `CardArea`（chip 的归属人），
## 这里只负责「谁登记在册」——`TriggerManager.get_card_area()`，切场景后旧实例不会冒充。
func _hand_chip_at(at: Vector2) -> CardChip:
	var area: CardArea = TriggerManager.get_card_area()
	if area == null or not is_instance_valid(area):
		return null
	return area.chip_at(at)


## Esc 语义：只关最上层。栈顶不允许 Esc 关闭时返回 false（不再往下穿透）。
func close_top() -> bool:
	var entry: Dictionary = _top_entry()
	if entry.is_empty():
		return false
	if not bool(entry["esc_closes"]):
		return false
	var node: Node = entry["node"]
	if not is_instance_valid(node):
		close_overlay(node)
		return true
	_close_by_entry(node)
	return true


## 关闭全部业务覆盖层（切场景、返回标题等场合）。
func clear_all() -> void:
	for entry in _stack.duplicate():
		close_overlay(entry["node"])
	_stack.clear()
	_refresh_blocker()


func has_overlay(node: Node) -> bool:
	return _index_of(node) != -1


## node 是否是当前最上层业务覆盖层（组件用它决定要不要吃输入）。
func is_top(node: Node) -> bool:
	var entry: Dictionary = _top_entry()
	if entry.is_empty():
		return false
	return entry["node"] == node


func top() -> Node:
	var entry: Dictionary = _top_entry()
	if entry.is_empty():
		return null
	return entry["node"]


func overlay_count() -> int:
	return _stack.size()


## 当前受管的业务覆盖层列表（自下而上）。
func get_overlays() -> Array[Node]:
	var result: Array[Node] = []
	for entry in _stack:
		var n: Node = entry["node"]
		if is_instance_valid(n):
			result.append(n)
	return result


## 业务覆盖层根（教学高亮框等需要在覆盖层里找节点时用）。
func get_business_layer() -> CanvasLayer:
	return _business


func get_tutorial_layer() -> CanvasLayer:
	return _tutorial


## 拖拽预览层根：把引擎托管的拖拽预览挂到这里，它就会压在所有弹窗之上。
## 用法见 `card_chip.gd::_rehome_preview()`（`force_drag` 之后把预览搬进来）。
func get_drag_preview_layer() -> CanvasLayer:
	return _drag


# ============================================================
#  输入：Esc 只关最上层
# ============================================================

func _unhandled_key_input(event: InputEvent) -> void:
	if _stack.is_empty():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode != KEY_ESCAPE:
		return
	if close_top():
		get_viewport().set_input_as_handled()


## 嵌入子窗口里的 Esc（见 `_attach` 里的 `window_input` 连接）。只按最上层语义走，
## 免得同一个 Esc 既关子窗口又穿透关掉下一层。
func _on_overlay_window_input(event: InputEvent, win: Window) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if not is_instance_valid(win) or top() != win:
		return
	if close_top():
		win.set_input_as_handled()


# ============================================================
#  输入：点面板外收起
# ============================================================

## 拦截层收到左键按下 = 玩家点了「面板外」。只有当前站岗的那个覆盖层标了
## `outside_click_closes` 才关它；否则保持老行为（拦截层只吃点击，什么都不做）。
##
## ⚠️ 这里能收到点窗口外的点击，**前提是该 Window 覆盖层以 `exclusive: false` 入栈**
##    （见 push_overlay 的 options 说明）。headless 量不出来，用
##    `debug/_card_panel_click_probe.tscn` 在 `--windowed` 下验。
func _on_blocker_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var node := _blocker_owner
	if node == null or not is_instance_valid(node):
		return
	var entry: Dictionary = _entry_of(node)
	if entry.is_empty() or not bool(entry.get("outside_click_closes", false)):
		return
	get_viewport().set_input_as_handled()
	# 🔴 落点必须由**事件本身**算：`get_global_mouse_position()` 读的是系统光标的实时位置，
	# 与这条事件的位置不是一回事（鼠标被外部注入 / 事件排队时会对不上，探针实测差到 1000px 开外）。
	close_with_click_through(node, _blocker.global_position + mb.position)


# ============================================================
#  内部
# ============================================================

func _attach(node: Node, parent: CanvasLayer, exclusive: bool = true) -> void:
	if parent == null:
		push_error("OverlayRoot: 覆盖层容器尚未初始化")
		return

	# Window 派生的弹窗（PopupPanel / AcceptDialog…）不能挂在 CanvasLayer 下——
	# 实测挂上去后 is_inside_tree() 恒为 false，_ready 不跑。它需要 Viewport 作父级。
	# 这类窗口本来就渲染在所有 CanvasLayer 之上，交给 root 托管即可；
	# 模态栈 / Esc / 场景切换清理仍由本管理器统一负责。
	var target: Node = parent
	if node is Window:
		var win := node as Window
		# PopupPanel(Popup) 默认 popup_window=true(FLAG_POPUP)。其源码 `Popup::_parent_focused`
		# 监听父窗口 focus_entered：点击弹窗外 → 焦点回父窗口 → `_close_pressed()` 自动 hide，
		# 绕过本管理器栈管理 → 栈残留 + ModalBlocker 残留 → 点击被透明拦截层吃掉，卡死。
		# 关键：这条焦点关闭路径只检查 FLAG_POPUP，**不检查 exclusive**（上一轮只设 exclusive 无效）。
		# 必须清 popup_window 标志阻断它；关闭完全交给 close_top / 组件 close 方法。
		win.popup_window = false
		# exclusive 默认 true：窗口独占输入（外部不可点），挡输入主要靠 ModalBlocker。
		# 「点面板外收起」类面板必须传 false —— 独占会把窗口外的点击整个吞掉，
		# 拦截层收不到、手牌也收不到（2026-10-23 实测：探针点手牌连点都不响应）。
		win.exclusive = exclusive
		if not win.transient:
			win.transient = true
		# 嵌入子窗口一旦拿到焦点，键盘事件就只在这个子窗口里走，主视口的
		# `_unhandled_key_input` 收不到 —— Esc 对人物面板一直无效（探针实证：exclusive
		# true / false 都一样，是既有缺陷不是本轮引入）。这里接住子窗口自己的输入，
		# 把 Esc 汇进同一条 close_top()，语义才和「Esc 只关最上层」对齐。
		if not win.window_input.is_connected(_on_overlay_window_input):
			win.window_input.connect(_on_overlay_window_input.bind(win))
		target = get_tree().root

	var current: Node = node.get_parent()
	if current == target:
		return
	if current == null:
		# 目标是我们自己的 CanvasLayer 时永远不处于 "busy setting up children"，可同步 add_child，
		# 调用方 push_overlay 之后可以立刻用 @onready 节点。
		# 目标是 root（Window 弹窗）时，请勿在别的节点 _ready 里同步调用 push_overlay，
		# 否则会命中 "Parent node is busy setting up children"；这种场合请 push_overlay.call_deferred。
		target.add_child(node)
	else:
		node.reparent(target)


func _index_of(node: Node) -> int:
	for i in _stack.size():
		if _stack[i]["node"] == node:
			return i
	return -1


## 取某个覆盖层的栈条目（不在栈里 → 空字典）。
func _entry_of(node: Node) -> Dictionary:
	var idx: int = _index_of(node)
	if idx == -1:
		return {}
	return _stack[idx]


func _top_entry() -> Dictionary:
	for i in range(_stack.size() - 1, -1, -1):
		if is_instance_valid(_stack[i]["node"]):
			return _stack[i]
	return {}


## 模态拦截层跟随"最上层的模态覆盖层"，插在它正下方；无模态覆盖层时隐藏。
func _refresh_blocker() -> void:
	if _blocker == null or not is_instance_valid(_blocker):
		return
	var top_modal: Node = null
	for i in range(_stack.size() - 1, -1, -1):
		var entry: Dictionary = _stack[i]
		if bool(entry["modal"]) and is_instance_valid(entry["node"]):
			top_modal = entry["node"]
			break

	if top_modal == null:
		_blocker.visible = false
		_blocker_owner = null
		return

	_blocker_owner = top_modal
	_blocker.visible = true
	# 先把拦截层挪到最后，再把模态窗挪到最后 —— 拦截层恰好落在模态窗正下方，
	# 同时保证模态窗压在其它非模态覆盖层之上。
	if _blocker.get_parent() == _business:
		_business.move_child(_blocker, -1)
	if top_modal.get_parent() == _business:
		_business.move_child(top_modal, -1)


func _on_overlay_tree_exited(node: Node) -> void:
	var idx: int = _index_of(node)
	if idx == -1:
		return
	_stack.remove_at(idx)
	_refresh_blocker()
	overlay_closed.emit(node)


## 场景切换：关闭"属于旧场景"的覆盖层，标了 persist 的保留。
##
## 注意判定顺序：先看 persist 字段，再用 is_instance_valid 判断旧场景是否已销毁。
## 千万不要写成 `if owner_scene == null: continue` —— 在 Godot 里被释放的对象
## 与 null 比较会返回 true，切场景后旧场景引用恰好满足这个条件，
## 于是每个覆盖层都被当成"常驻"跳过，清理彻底失效（本次实测踩到过）。
func _on_scene_changed() -> void:
	var current: Node = get_tree().current_scene
	for entry in _stack.duplicate():
		if bool(entry.get("persist", false)):
			continue
		var owner_scene: Variant = entry.get("scene", null)
		if not is_instance_valid(owner_scene) or owner_scene != current:
			close_overlay(entry["node"])
