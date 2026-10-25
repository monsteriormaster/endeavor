## 卡牌组件 —— 可拖拽的卡牌（参考密教模拟器：手牌拖入动词槽）。
## 统一卡面：以 res://art/card.png 为外框，内部布局「名字区（display_name）+ 图像区（icon_path）」。
## 所有卡牌（手牌 CardArea / 卡槽 CardSlot）均通过 card_chip.tscn 实例化本组件，卡面保持一致。
## 地图人物卡（`character.gd`）也实例化本组件，只是把卡面放大 `face_scale` 倍（2026-10-16）。
##
## ── 卡面 B2（2026-09-27 定稿）──
## 卡牌尺寸 90×159（与 card.png 360×636 同比例 0.5660，不拉伸外框）。
## 版面改造：**名字在上、立绘在下**（原来是立绘在上、名字贴底），并给名字区**预留两行**。
## 卡面最里一道线在 1x 的 ins 5.0 处，内容必须落在它里面 → 边距 左/右/上 6、下 7。
## 名字区固定高 33px（运行时按主题字体真实度量算，YouYuan font14 → 15×2+3；见 _name_reserved_height），
## 这样 1 行名与 2 行名的卡，下方立绘区高度一致、同排卡片立绘大小不会跳。
## ⇒ 图像区实际 = 78 × 109（不是老文档写的 70×99 / 70×100）。
##
## set_card(card) 设置内容；_get_drag_data 返回 {card, origin} 作为拖拽载荷并设置拖拽预览。
## origin：拖拽来源（CardArea / CardSlot），放置成功后由放置目标据此从来源移除或清理。
## drop_target：本芯片作为已放置卡时，把"被拖放到它身上"的事件转发给的目标节点
##             （卡槽/卡牌区整体成为放置目标，支持替换与取回）。
class_name CardChip
extends Panel

## 开始拖拽时发出（参数：被拖的卡）。
signal card_drag_started(card: CardData)
## 单击（按下并原地释放，非拖拽）时发出（参数：被点过的卡）。新手教程「点卡牌管家」等用。
signal clicked(card: CardData)

var card: CardData = null
var draggable: bool = true
## D-ATTRACT-LOCK（2026-10-24）：移动锁 —— 只禁拖拽发起，**保留单击**（点卡看面板）。
## 与 set_draggable(false) 的区别：那个连 mouse_filter 都关掉（点击一起没）；
## 这个只掐断 force_drag，卡还能点开看（吸附卡的「锁死」用这个）。
var lock_move: bool = false
## 拖拽来源：CardArea（手牌）或 CardSlot（已放置的卡），放置成功后由目标据此清理。
var origin: Variant = null
## 放置事件转发目标（卡槽/卡牌区），使本芯片所在容器整体成为放置目标。
var drop_target: Node = null
## 左键按下位置（用于区分「点击」与「拖拽」）。
var _press_pos := Vector2.ZERO

## 统一卡牌外框（卡面底图）。用户后续自行替换/调整此图以适配卡面样式。
## B2 卡面 = 骨色纸面 + 细铜双线外框 + 内缘第二道细线 + 顶中铜徽记。
const CARD_FRAME := preload("res://art/card.png")
## 卡牌尺寸：与 card.png 比例一致（360:636 = 90:159 = 0.5660），不拉伸外框。
## 同时与 card_slot DropZone 90×159 对齐，满铺卡槽。
const CARD_SIZE := Vector2(90, 159)
## 卡面缩放倍率。默认 1.0 = 手牌 / 卡槽的 90×159；
## 地图人物卡（`character.gd`）要把**同一张卡面**放大成 200×353 → 设 `200.0 / 90.0`。
##
## 🔴 为什么不用 `Control.scale`：那只是把已经栅格化的画面（14px 的字形图集）整体拉大 ⇒ 糊。
##    这里让**边距 / 名字字号 / 行距 / 间距**各自乘上倍率，字是按倍率**重新栅格化**的。
##    除了一处例外：`card.png` 外框本身不重烤，靠 LINEAR 采样（4x 素材放到 200px 仍是降采样）。
@export var face_scale: float = 1.0
## 内边距。卡面最里那道线在 1x 的 ins 5.0（粗 0.45）→ 内容必须落在它里面：
## 左右/上取 6；下方那道线的内缘在 y≈152.55，故下边距取 7（比上边距多 1）。
const FRAME_MARGIN_TOP := 6
const FRAME_MARGIN_BOTTOM := 7
const FRAME_MARGIN_SIDE := 6
## 名字字号。
const NAME_FONT_SIZE := 14
## 名字区与图像区之间的间距。原先是写在 `_build_face()` 里的字面量 4，
## 2026-10-16 提为常量 —— 它也要随 `face_scale` 一起放大，藏在函数里会漏。
const FACE_SEPARATION := 4.0
## 名字区**预留行数**。卡面是「名字在上、立绘在下」，最长名字（7 字「章鱼尾人身塑像」）
## 在 78px 宽下会折成 2 行，所以必须预留 2 行；否则 1 行名与 2 行名会让下方立绘区
## 高度差一行、同一排卡片立绘大小不一致。
const NAME_RESERVED_LINES := 2
## 行高兜底系数（实测默认字体 Open Sans SemiBold：font_size 14 → height 20，比值 1.4286）。
## 正常情况下走主题字体的真实 get_height()，取不到字体才用这个兜底。
const NAME_LINE_H_FALLBACK := 1.4286


func _ready() -> void:
	custom_minimum_size = CARD_SIZE * face_scale
	_apply_style(self)
	_redraw()


## 设置卡面缩放倍率（默认 1.0）。入树前设也可以 —— `_ready()` 会照它算最小尺寸；
## 入树后设则立即按新倍率重排。
func set_face_scale(s: float) -> void:
	face_scale = maxf(s, 0.01)
	custom_minimum_size = CARD_SIZE * face_scale
	if is_node_ready():
		_redraw()


## 版式度量 × 倍率，取整到像素。🔴 卡面里所有常量（边距 / 间距 / 字号）都要过这里，
## 别在 `_build_*` 里直接写原值 —— 漏一个，放大后的卡面就会「一处对齐、处处错位」。
func _si(v: float) -> int:
	return int(round(v * face_scale))


## 设置要展示的卡（null 时清空）。
func set_card(c: CardData) -> void:
	card = c
	_redraw()


## 是否可拖拽。false 时鼠标穿透，供卡槽作为放置目标。
func set_draggable(v: bool) -> void:
	draggable = v
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not draggable else Control.MOUSE_FILTER_STOP


## D-ATTRACT-LOCK：锁/解移动锁。锁上后 motion 分支不再发起 force_drag、_start_drag 早退；
## 单击链路（release 位移<阈值 → clicked）不受影响。
func set_lock_move(v: bool) -> void:
	lock_move = v


func _apply_style(target: Control) -> void:
	# 外框：card.png 铺满整卡作为卡面底图（Panel 自身不画底色，边框全部由底图绘制）。
	target.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## 名字区应预留的高度（px）：
##   = 行高 × 行数 + line_spacing × (行数 − 1)
## 全部取自**运行时主题的真实字体度量**，不写死估算值。
## ✅ 2026-10-08 引擎实测（`debug/_book_icon_probe.tscn`，在**真 card_area.tscn** 里量的，主题链与实机一致）：
##   主题字体 = **YouYuan**，height(14) = **15**，Label `line_spacing` = **3**
##   ⇒ 两行预留 = 15×2 + 3 = **33**，图像区 = 78 × (159−6−7−4−33) = **78 × 109**。
## 🔴 下方旧注释里的「43」是**用引擎默认字体（height 20）量出来的错值**，还传进了 2026-09-29 的
##   「图像区 78×99」结论与若干文档 —— 那个数**作废**。改卡面几何前先跑上面的探针，别照抄注释。
func _name_reserved_height() -> float:
	var f: Font = get_theme_font("font", "Label")
	var fs := _si(NAME_FONT_SIZE)
	var lh: float = float(f.get_height(fs)) if f != null else fs * NAME_LINE_H_FALLBACK
	var sp := float(get_theme_constant("line_spacing", "Label")) * face_scale
	return lh * NAME_RESERVED_LINES + sp * (NAME_RESERVED_LINES - 1)


## 重建卡面内容：外框背景 + 名字区（上）+ 图像区（下）。
func _redraw() -> void:
	for ch in get_children():
		ch.queue_free()
	if card == null:
		return
	_build_face(self)


## 把「外框 + 名字（上）+ 立绘（下）」搭到 host 上。
## 卡面本体（set_card 后）与拖拽预览**共用这一份构建代码**，保证预览与真卡一致。
func _build_face(host: Control) -> void:
	# —— 外框背景（card.png） ——
	var frame := TextureRect.new()
	frame.texture = CARD_FRAME
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	# ⚠️ 必须单独开 LINEAR：工程全局 default_texture_filter = NEAREST
	# （project.godot → rendering/textures/canvas_textures/default_texture_filter=0）。
	# card.png 是 4x（360×636）而卡位只有 90×159 → 点采样做 4:1 降采样会把
	# 0.45~1.3px 的细描边整条丢掉或闪成锯齿（旧 367×648 卡面正是这样被点采样缩到 90×159，
	# 细纹全糊成噪点，也是「卡面看着脏」的一部分来源）。
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(frame)

	# —— 内容（名字 + 图像），叠在外框之上、避开最里那道描边线 ——
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", _si(FRAME_MARGIN_TOP))
	margin.add_theme_constant_override("margin_bottom", _si(FRAME_MARGIN_BOTTOM))
	margin.add_theme_constant_override("margin_left", _si(FRAME_MARGIN_SIDE))
	margin.add_theme_constant_override("margin_right", _si(FRAME_MARGIN_SIDE))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _si(FACE_SEPARATION))
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vb)

	# —— 名字区（在上，固定预留 2 行高）——
	vb.add_child(_build_name())

	# —— 图像区（在下，吃掉剩余高度）——
	vb.add_child(_build_icon())


## 构建图像区：与 character_panel 一致的路径解析（CharacterImage.resolve_path）。
## 图像区背景完全透明（无图或加载失败时不显示任何色块），有图时保持比例居中。
func _build_icon() -> Control:
	var box := Panel.new()
	box.custom_minimum_size = Vector2(CARD_SIZE.x * face_scale - _si(FRAME_MARGIN_SIDE) * 2, 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var tex: Texture2D = _try_load_icon()
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	return box


## 构建名字区：display_name + 可选的「有话可说」金色标记。
## 固定预留 NAME_RESERVED_LINES 行高（1 行名居中、2 行名铺满），贴名字区顶部。
func _build_name() -> Control:
	# 人物卡「有话可说」标记：该角色 npc 的「有话可说」num_tag >= 1 时，名字旁加金色「…」
	var talkable := false
	if card.card_type == "character":
		var npc_key := EffectProcessor._npc_key_of(card)
		talkable = int(Player.npc.get(npc_key, {}).get("num_tags", {}).get("有话可说", 0)) >= 1

	var name_l := Label.new()
	name_l.text = card.display_name + (" …" if talkable else "")
	name_l.add_theme_font_size_override("font_size", _si(NAME_FONT_SIZE))
	if talkable:
		# 「有话可说」金色标记：卡面是浅色羊皮纸（名字区亮度中位 ≈219），
		# 亮金色（原 0.95,0.78,0.3，亮度 ≈198）在纸面上几乎看不见，
		# 改用**深青铜金**（亮度 ≈114）——保住「金色」语义同时足够清晰。
		name_l.add_theme_color_override("font_color", Color(0.66, 0.42, 0.05))
	else:
		# B2 卡面是**浅色骨白纸面**（实测名字区底色 RGB=(231,222,202)，亮度 ≈223），
		# 名字必须用**深墨色**才看得清。取深褐墨色（亮度 ≈34），与复古卡面气质一致。
		name_l.add_theme_color_override("font_color", Color(0.18, 0.13, 0.09))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 名字在上：贴名字区顶部；固定高度保证 1 行/2 行名时下方立绘区高度一致。
	name_l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	name_l.custom_minimum_size = Vector2(0, _name_reserved_height())
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return name_l


## 加载立绘贴图。
## - 人物卡：统一走 CharacterImage.resolve_path（与 character_panel 一致，含 gender fallback）。
## - 道具卡：仅用真实 icon_path（gender fallback 对物品无意义，无图显示占位）。
func _try_load_icon() -> Texture2D:
	var path := resolve_icon_path(card)
	if path == "":
		return null
	var t: Texture2D = load(path)
	return t if t is Texture2D else null


## 卡面图像区的**唯一**路径解析入口（本组件与 CardDetailPopup 共用，别再各写一份）。
##
## - 人物卡：一律走 `CharacterImage.resolve_path` —— 它的契约就是「image 缺失 / 指向不存在的
##   文件 → 按 gender 回落到 `man.png` / `woman.png`」。所以人物卡**永远不该是空白图像区**。
## - 道具卡：只用真实 `icon_path`（gender 回落对物品无意义），无图返回 ""（图像区留空）。
##
## 🔴 2026-10-10 修「主角有时卡牌里没有图片」的两个缺陷（都在这里）：
##   ① 原实现在最前面写 `if card.icon_path == "": return null`，**把人物的性别回落整个短路了**。
##      而 `Player.get_hero_card()` 当时不设 icon_path ⇒ 主角卡图像区全空。
##      现在人物卡不再看 icon_path 是否为空，交给 CharacterImage 决定。
##   ② 人物卡带空 icon_path 时，再按 npc 键去 `Player.npc` 条目里补一次 image
##      （运行时构造的卡可能只带属性、不带静态字段）。
static func resolve_icon_path(card: CardData) -> String:
	if card == null:
		return ""
	if card.card_type != "character":
		return card.icon_path

	var lookup: Dictionary = {"image": card.icon_path}
	var npc_key := EffectProcessor._npc_key_of(card)
	var entry: Variant = Player.npc.get(npc_key, {})
	if entry is Dictionary:
		var e: Dictionary = entry
		if e.has("gender"):
			lookup["gender"] = e["gender"]
		if card.icon_path == "":
			lookup["image"] = String(e.get("image", ""))
	return CharacterImage.resolve_path(lookup)


## 拖拽死区（像素）：左键按住并移动超过此距离即发起拖拽。
## 取 Godot 默认 gui/drag_threshold（8px），略大于单击阈值（6px），
## 保证「原地点击 = 单击、移动 = 拖拽」不冲突。
const DRAG_THRESHOLD := 8.0

## 单击检测：左键按下记录位置，原地释放（位移 < 阈值）视为点击，发出 clicked。
## 拖拽在本函数内于「左键按住且位移超过 DRAG_THRESHOLD」时显式 force_drag 发起，
## 不再依赖 Godot 自动拖拽（ ScrollContainer 等容器子节点下自动拖拽不稳定、经常不触发），
## 两者不冲突：点击不触发拖拽，拖拽不触发点击。
##
## 设计要点（修复「ScrollContainer 抢拖拽」+「直接进 main 加卡后点/拖全失效」）：
##   ① 左键按下时调用 accept_event()：卡牌 chip 是 CardArea 内
##      ScrollContainer>HBox 的子节点，Godot 4 的 ScrollContainer 在左键按下时会把它当作
##      「拖拽滚动」起点、收走后续 motion，导致 chip _gui_input(motion) 收不到 → drag 发起不了
##      （round-1「卡牌不能拖动」根因）。accept_event() 把 press 标记为已消费，阻止事件冒泡到
##      ScrollContainer，使其不进入滚动态；左键专用于拖卡，点卡片间隙/HBox 空白仍可拖拽滚动。
##   ② _get_drag_data 返回 null：彻底禁用引擎自动拖拽。关键副作用——若返回非空载荷，引擎会在
##      press 时进入「拖拽候选」态，原地释放时 release 被引擎内部消化、不再派发给 _gui_input，
##      于是 clicked 永不触发（这就是「点击不弹面板」的真因，与入口无关）。返回 null 后 release
##      正常派发，单击链路恢复。
##   ③ 拖拽完全由本函数内的 force_drag 单链路发起，不与引擎自动拖拽竞争/双触发。
func _gui_input(event: InputEvent) -> void:
	if not draggable or card == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				# 拦住 ScrollContainer 的拖拽滚动（见①）；不阻断后续 release/motion 派发，
				# 因为 accept_event() 只作用于当前这一个 press 事件。
				accept_event()
			else:
				# 原地释放（位移 < 单击阈值）→ 单击；拖拽中释放不触发 clicked
				if (_press_pos - mb.position).length() < 6.0:
					clicked.emit(card)
	elif event is InputEventMouseMotion:
		# 左键按住且已移动超过死区 → 显式发起拖拽。
		# 用 gui_is_dragging 守卫：拖拽进行中每帧的 motion 不再重复 force_drag。
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and not lock_move and not get_viewport().gui_is_dragging() and (_press_pos - event.position).length() >= DRAG_THRESHOLD:
			_start_drag()


## 统一发起拖拽：emit card_drag_started + force_drag（显式预览）。
## 与 _get_drag_data 返回相同载荷 {"card","origin"}，放置目标据此从 origin 清理卡牌。
## force_drag 会同步置位 Viewport 拖拽状态，从而抑制 Godot 自动拖拽（_get_drag_data）重复触发。
func _start_drag() -> void:
	if lock_move:
		return
	card_drag_started.emit(card)
	var prev := _build_preview()
	force_drag({"card": card, "origin": origin}, prev)
	# 引擎把预览挂到「发起点所在的最外层 Control」下（= 卡牌区所在的 canvas，Layer 0），
	# 拖到触发器弹窗（BusinessLayer 50）上时预览会被弹窗盖住。force_drag 之后 prev 才入树，
	# 所以推迟到本帧末尾再把它搬进 OverlayRoot 的拖拽预览层（DRAG_PREVIEW_LAYER=200）。
	_rehome_preview.call_deferred(prev)


## 把引擎托管的拖拽预览搬到高层，保证「拖拽中的卡永远压在所有弹窗之上」。
## ⚠️ 预览是引擎的托管对象（拖拽结束时由引擎释放）：这里只换父节点，**不持有引用、不释放**。
## 预览带 `top_level=true` ⇒ position 即画布坐标；目标 CanvasLayer 无变换，搬运后位置不变。
func _rehome_preview(prev: Control) -> void:
	if not is_instance_valid(prev):
		return
	var layer: CanvasLayer = OverlayRoot.get_drag_preview_layer()
	if layer == null or prev.get_parent() == layer:
		return
	var old_parent: Node = prev.get_parent()
	if old_parent != null:
		old_parent.remove_child(prev)
	layer.add_child(prev)


## 引擎自动拖拽入口：返回 null 彻底禁用引擎自动拖拽。
## 拖拽完全由 _gui_input 中的 force_drag 单链路发起（见 _start_drag），
## 避免与自动拖拽竞争 / 双触发（一次拖拽走两条路会造成双拖与重复 card_drag_started）。
func _get_drag_data(_position: Vector2) -> Variant:
	return null


## 拖拽预览：与真卡**同一份构建代码**（外框 + 名字在上 + 立绘在下），保证预览与卡面一致。
func _build_preview() -> Control:
	var prev := Panel.new()
	prev.name = "DragPreview"
	# 关键：拖拽预览是顶层控件，不处于任何容器布局中，custom_minimum_size 不生效。
	# 必须显式设置 size，否则预览尺寸为 (0,0)，拖拽时看不到卡牌跟随鼠标（视觉上「拖不动」）。
	prev.size = CARD_SIZE * face_scale
	_apply_style(prev)
	_build_face(prev)
	return prev


## 作为已放置卡时，把"被拖放到身上"的事件转发给 drop_target（卡槽/卡牌区）。
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if drop_target != null and drop_target.has_method("_can_drop_data"):
		return drop_target._can_drop_data(_at, data)
	return false


func _drop_data(_at: Vector2, data: Variant) -> void:
	if drop_target != null and drop_target.has_method("_drop_data"):
		drop_target._drop_data(_at, data)
