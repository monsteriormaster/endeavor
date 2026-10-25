extends Control

## 成就画卷面板。列出全部成就，已解锁显示详情，未解锁只给铅笔定位框 / 隐藏描述（防剧透）。
## 由 AchievementManager.open_list 呼出。
##
## ▍入场 / 出场：**翻页**（2026-10-06，用户口径「主界面成就……也做同样的动画」）
##   与设置页同一套几何（`script/paper_flip.gd`）：折线左→右扫过，画卷整幅盖上 / 揭开。
##   ⚠️ 因此 `open_list` 入栈必须用 **`esc_closes: false`**，Esc 由本组件自己接
##      （`_unhandled_key_input`）。理由见 `settings_menu.gd` 文件头：
##      `OverlayRoot.close_top()` 会在 close_method 之后兜底 `close_overlay` ⇒ 立刻 queue_free，
##      0.5s 的翻页会被砍在第 0 帧。
##   ⚠️ 画卷由 **7 个平行的视觉子节点**组成（两张全屏暗纱 + 卷身 + 列表 + 两块题签 + 收起按钮），
##      没有单一的包一层容器 ⇒ 直接把 7 个都交给 `PaperFlip.setup()`（它支持多 root）。
##      **不要**图省事写 `setup([self])`：本翻页层就是 self 的孩子，
##      把自己藏掉 = 把折线一起藏掉（`PaperFlip.setup` 会挡下这种用法并报错）。
##   ⚠️ 暗纱（VeilWarm/VeilDark）**也一起裁**：不然折线两侧的压暗突然断一截，反而露馅；
##      折线与排线影正好画在那条缝上，把它盖住了。
##
## 视觉（对齐 overview.md 的 A 集：纸 / 铜 / 墨，直角、无发光、无纯黑）：
##   art/ui/achievement/scroll_body.png  —— 木轴 + 纸 + 卷首插画（小七画的城景）+ 纸边压暗
##   art/ui/achievement/tag_plate.png    —— 手绘题签底板，经 theme/ach_tag_plate.tres 九宫格拉伸
##   画框类贴图烘成「白 + alpha」，颜色在这里用 modulate 上色，一形两态（铜 / 铅笔灰）
##
## 概念：整块界面 = 小七画的一幅画卷。
##   已解锁  → 她画好了（画框 + 画面；暂无配图时显示她的铅笔草稿占位 slot_sketch）
##   未解锁  → 她还没画到那里（纸上只有铅笔定位框）
##   隐藏未解锁 → 只有四角铅笔括号，练「仍有空白待填」
##   ⚠️ v0.2 旧稿的「path 缺省 = 纯黑 ColorRect」已废弃：纯黑违反工程「不用纯黑」的冻结规矩。
##
## 字段与显示规则（对齐 achievements.json）：
##   hidden（默认 false）：
##     - hidden=true 且 未达成 → how 默认隐藏，显示「点击揭晓」；点该条目改为「达成条件：<how>」并常显。
##       关闭面板再打开仍隐藏（_revealed 每次 setup 重置，不持久化）。
##     - hidden=false → how 常显。
##     - 已达成 → 显示 description 与 how（成就既已解锁，无剧透顾虑）。
##   name：始终显示（未达成灰显），让玩家感知"仍有未知成就待发掘"。
##   point：写在成就名后面的手写批注，铅笔圈住；未达成灰显。
##
## _row_data：供测试检视的引用表 {id: {row, how, how_text, desc, name, point, hidden, achieved}}。

const FRAME_UNLOCKED := preload("res://art/ui/achievement/frame_unlocked.png")
const FRAME_LOCKED := preload("res://art/ui/achievement/frame_locked.png")
const FRAME_HIDDEN := preload("res://art/ui/achievement/frame_hidden.png")
const SKETCH := preload("res://art/ui/achievement/slot_sketch.png")
const RING := preload("res://art/ui/achievement/ring_score.png")

const COL_INK_NAME := Color(0.180392, 0.141176, 0.094118)   # #2E2418
const COL_INK := Color(0.262745, 0.215686, 0.164706)        # #43372A
const COL_INK_SOFT := Color(0.419608, 0.360784, 0.290196)   # #6B5C4A
const COL_PENCIL := Color(0.541176, 0.494118, 0.431373)     # #8A7E6E
const COL_PENCIL_LT := Color(0.650980, 0.603922, 0.537255)  # #A69A89
const COL_HOW_HID := Color(0.690196, 0.643137, 0.572549)    # #B0A492
const COL_HOW_LOCK := Color(0.619608, 0.572549, 0.501961)   # #9E9280
const COL_COPPER_LT := Color(0.560784, 0.423529, 0.180392)  # #8F6C2E
const COL_COPPER := Color(0.450980, 0.333333, 0.145098)     # #735525

const SIZE_NAME := 27
const SIZE_DESC := 16
const SIZE_HOW := 14
const SIZE_PT := 17

## 画框贴图边长（内容区 = 边长 - 2*FRAME_INSET = 128）
const FRAME_SIDE := 144
const FRAME_INSET := 8
const ROW_H := 150
const TEXT_GAP := 20
const SCORE_BOX := Vector2(76, 56)

@onready var _summary: Label = $SumTag/SumLabel
@onready var _entry_scroll: ScrollContainer = $EntryScroll
@onready var _entry_list: VBoxContainer = $EntryScroll/EntryList
@onready var _close_button: Button = $CloseButton

## 画卷的「一页纸」= 这 7 个平行视觉子节点（不含本翻页层）。
## ⚠️ 改 .tscn 里这几个节点名要同步改这里，否则 `paper_flip` 会 push_error 说「没东西可裁」。
const SHEET_NODES := [
	"VeilWarm", "VeilDark", "ScrollBody", "EntryScroll", "TitleTag", "SumTag", "CloseButton",
]

var _flip: PaperFlip = null
var _closing: bool = false
## 本次打开会话内已手动点开的隐藏成就 how（关闭重开重置，不持久化）。
var _revealed: Dictionary = {}
## 条目引用表（见文件头注释）
var _row_data: Dictionary = {}


func _ready() -> void:
	_close_button.pressed.connect(close)
	_style_scrollbar()
	# 翻页层：**最后加** ⇒ 画在整幅画卷之上。
	_flip = PaperFlip.new()
	_flip.name = "Flip"
	add_child(_flip)
	var sheets: Array = []
	for nm in SHEET_NODES:
		var n := get_node_or_null(nm)
		if n == null:
			push_warning("AchievementList: 找不到 %s，这一块不会被翻页裁切" % nm)
			continue
		sheets.append(n)
	_flip.setup(sheets)
	_flip.set_side(1.0)     # 折线左侧是画进来的画卷 ⇒ 扫过 = 把它盖上
	# `setup()` 会在 p=0 把画卷整幅藏掉 —— 所以入场动画必须等 setup() 里建完条目再开
	# （否则第一帧的画卷是空的，最后一行会「半路冒出来」）。见 setup() 末尾。


## 滚动条改成「纸上一道铅笔槽 + 铜滑块」，跟画卷同材质；宽度靠样式盒的 content_margin 撑出来。
func _style_scrollbar() -> void:
	var bar: VScrollBar = _entry_scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 8.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.18, 0.13, 0.09, 0.13)
	track.content_margin_left = 4.0
	track.content_margin_right = 4.0
	bar.add_theme_stylebox_override("scroll", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(COL_COPPER_LT.r, COL_COPPER_LT.g, COL_COPPER_LT.b, 0.42)
	var grab_hi := StyleBoxFlat.new()
	grab_hi.bg_color = Color(COL_COPPER_LT.r, COL_COPPER_LT.g, COL_COPPER_LT.b, 0.62)
	var grab_pr := StyleBoxFlat.new()
	grab_pr.bg_color = Color(COL_COPPER.r, COL_COPPER.g, COL_COPPER.b, 0.72)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hi)
	bar.add_theme_stylebox_override("grabber_pressed", grab_pr)


## 渲染成就列表。由 AchievementManager.open_list 在 push_overlay 后调用（@onready 已就绪）。
func setup() -> void:
	_revealed.clear()
	_row_data.clear()
	for child in _entry_list.get_children():
		child.queue_free()

	var all: Dictionary = AchievementManager.get_all()
	var unlocked_points := AchievementManager.get_unlocked_points()
	var total_points := AchievementManager.get_total_points()
	var unlocked_count := AchievementManager.get_unlocked_count()
	var total_count := all.size()
	_summary.text = "已获积分 %d / %d    ·    已解锁 %d / %d" % [unlocked_points, total_points, unlocked_count, total_count]

	for id in all:
		var cfg: Dictionary = all[id]
		var unlocked: bool = AchievementManager.is_unlocked(id)
		var entry := _make_entry(id, cfg, unlocked)
		_entry_list.add_child(entry["row"])
		_row_data[id] = entry

	# 条目建完才开始翻页进场（`_ready` 里那一步只把画卷摆到 p=0）。
	if _flip != null:
		_flip.play(0.0, 1.0)


## 构造单条成就条目，返回 {row, how, how_text, desc, name, point, hidden, achieved}。
func _make_entry(id: String, cfg: Dictionary, unlocked: bool) -> Dictionary:
	var hidden: bool = bool(cfg.get("hidden", false))

	# 整行可点击（隐藏成就点开展示达成条件）。
	# mouse_filter 用 PASS：本行收到 gui_input 后事件继续冒泡给 ScrollContainer，
	# 拖拽滚动才不会被行吃掉（用 STOP 会让「在条目上按住拖」失效）。
	var row := MarginContainer.new()
	row.name = "Entry"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.gui_input.connect(_on_entry_gui_input.bind(id))

	var hbox := HBoxContainer.new()
	hbox.name = "RowBox"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", TEXT_GAP)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	# 画框区：帧贴图 144x144，画面内缩 8 即 128x128
	var slot := Control.new()
	slot.name = "ArtSlot"
	slot.custom_minimum_size = Vector2(FRAME_SIDE, FRAME_SIDE)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(slot)

	var art_path := String(cfg.get("path", ""))
	if unlocked and art_path != "" and ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = load(art_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(art)
		_inset(art, FRAME_INSET)
	elif unlocked:
		# 已解锁但还没配图 → 小七的铅笔草稿占位（不再用纯黑 ColorRect）
		var sketch := TextureRect.new()
		sketch.name = "Sketch"
		sketch.texture = SKETCH
		sketch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sketch.stretch_mode = TextureRect.STRETCH_SCALE
		sketch.modulate = Color(COL_PENCIL.r, COL_PENCIL.g, COL_PENCIL.b, 0.72)
		sketch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(sketch)
		_inset(sketch, FRAME_INSET)

	var frame := TextureRect.new()
	frame.name = "Frame"
	if unlocked:
		frame.texture = FRAME_UNLOCKED
		frame.modulate = COL_COPPER_LT
	elif hidden:
		frame.texture = FRAME_HIDDEN
		frame.modulate = COL_PENCIL
	else:
		frame.texture = FRAME_LOCKED
		frame.modulate = COL_PENCIL
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(frame)
	_inset(frame, 0)

	# 文字列
	var col := VBoxContainer.new()
	col.name = "TextCol"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(col)

	# 名字行：成就名 + 手写批注（积分写在名字正后方，铅笔圈住）
	# 两处都取 SHRINK_BEGIN：圈的横向位置跟着名字长度走，而不是被推到行尾。
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = String(cfg.get("name", id))
	name_lbl.add_theme_font_size_override("font_size", SIZE_NAME)
	name_lbl.add_theme_color_override("font_color", COL_INK_NAME if unlocked else COL_PENCIL)
	name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_lbl)

	var score_box := Control.new()
	score_box.name = "ScoreBox"
	score_box.custom_minimum_size = SCORE_BOX
	score_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(score_box)

	var ring := TextureRect.new()
	ring.name = "ScoreRing"
	ring.texture = RING
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	if unlocked:
		ring.modulate = COL_COPPER
	else:
		# 贴图里主笔 alpha 0.58，乘 0.42 ≈ 设计稿欠解锁态的 0.24
		ring.modulate = Color(COL_PENCIL_LT.r, COL_PENCIL_LT.g, COL_PENCIL_LT.b, 0.42)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_box.add_child(ring)
	_inset(ring, 0)

	var point_lbl := Label.new()
	point_lbl.name = "ScoreLabel"
	point_lbl.text = "%d" % int(cfg.get("point", 0))
	point_lbl.add_theme_font_size_override("font_size", SIZE_PT)
	point_lbl.add_theme_color_override("font_color", COL_INK_NAME if unlocked else COL_PENCIL)
	point_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	point_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	point_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_box.add_child(point_lbl)
	_inset(point_lbl, 0)

	# 描述：已达成显示；未达成隐藏（description 含剧情线索，隐藏防剧透）
	var desc_lbl := Label.new()
	desc_lbl.name = "DescLabel"
	desc_lbl.add_theme_font_size_override("font_size", SIZE_DESC)
	desc_lbl.add_theme_color_override("font_color", COL_INK)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if unlocked:
		desc_lbl.text = String(cfg.get("description", ""))
	else:
		desc_lbl.visible = false
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc_lbl)

	# 达成条件（how）：隐藏成就默认只给「点击揭晓」；非隐藏 / 已达成直接给全文。
	var how_text := String(cfg.get("how", ""))
	var how_lbl := Label.new()
	how_lbl.name = "HowLabel"
	how_lbl.add_theme_font_size_override("font_size", SIZE_HOW)
	how_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if how_text == "":
		how_lbl.text = ""
		how_lbl.add_theme_color_override("font_color", _how_color(hidden, unlocked))
		how_lbl.visible = _how_should_show(hidden, unlocked)
	else:
		if hidden and not unlocked:
			how_lbl.text = "点击揭晓"
			how_lbl.add_theme_color_override("font_color", COL_HOW_HID)
			how_lbl.visible = true
		else:
			how_lbl.text = "达成条件：" + how_text
			how_lbl.add_theme_color_override("font_color", _how_color(hidden, unlocked))
			how_lbl.visible = _how_should_show(hidden, unlocked)
	col.add_child(how_lbl)

	return {
		"row": row,
		"how": how_lbl,
		"how_text": how_text,
		"how_color": _how_color(hidden, unlocked),
		"desc": desc_lbl,
		"name": name_lbl,
		"point": point_lbl,
		"hidden": hidden,
		"achieved": unlocked,
	}


## 入树后再设 anchors + 内缩：入树前设的尺寸会被改写成贴图原始尺寸（工程实测坑）。
func _inset(n: Control, px: int) -> void:
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.offset_left = float(px)
	n.offset_top = float(px)
	n.offset_right = -float(px)
	n.offset_bottom = -float(px)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _how_color(hidden: bool, achieved: bool) -> Color:
	if achieved:
		return COL_INK_SOFT
	if hidden:
		return COL_HOW_HID
	return COL_HOW_LOCK


## how 是否应显示：已达成 → 显；隐藏+未达成 → 默认隐（点击才显）；非隐藏 → 常显。
func _how_should_show(hidden: bool, achieved: bool) -> bool:
	if achieved:
		return true
	if hidden:
		return false
	return true


## 点击条目：隐藏且未达成的成就，点开展示达成条件（本次会话内，关闭重开仍隐藏）。
func _on_entry_gui_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		reveal_how(id)


## 显式点开某成就的达成条件（供点击与测试调用）。
func reveal_how(id: String) -> void:
	if not _row_data.has(id):
		return
	var row: Dictionary = _row_data[id]
	if not bool(row["hidden"]) or bool(row["achieved"]):
		return  # 非隐藏 / 已达成无需点开
	if _revealed.has(id):
		return  # 本次已点开
	_revealed[id] = true
	var how_lbl: Label = row["how"]
	how_lbl.text = "达成条件：" + String(row["how_text"])
	how_lbl.add_theme_color_override("font_color", row["how_color"])
	how_lbl.visible = true


## 关闭面板。Esc 与「收起画卷」按钮共用；重复调用安全。
##
## ⚠️ 先翻出去、动画跑完再出栈 —— 不能先出栈：`close_overlay` 会立刻 `queue_free`，
##    翻页会死在第 0 帧。（这也是 `open_list` 必须传 `esc_closes: false` 的原因。）
func close() -> void:
	if _closing:
		return
	_closing = true
	if _flip == null:
		_release()
		return
	_flip.play(1.0, 0.0, _release)


func _release() -> void:
	if not is_inside_tree():
		return
	if not OverlayRoot.close_overlay(self):
		queue_free()


## Esc 自己接（`open_list` 用的是 `esc_closes: false`，OverlayRoot 那条路不会替我们关）。
## 覆盖层比 autoload 深 ⇒ `_unhandled_input` 先到我们手上，抢在 OverlayRoot 之前处理掉。
func _unhandled_key_input(event: InputEvent) -> void:
	if _closing:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## 探针接口：一次把验收要用的读数交出去（不要自己另算几何）。
func probe_state() -> Dictionary:
	return {
		"closing": _closing,
		"flip": _flip.probe_state() if _flip != null else {},
		"sheets": SHEET_NODES.size(),
		"rows": _entry_list.get_child_count() if _entry_list != null else -1,
	}


func flip_layer() -> PaperFlip:
	return _flip
