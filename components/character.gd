## 地图人物卡 —— 地图上以「当前卡面」呈现的人物节点（不进手牌、不参与拖拽）。
##
## ▍2026-10-16 改版：卡面归 `CardChip`，本文件只管场景语义。
##   旧实现是「三段 StyleBoxFlat 硬画的米黄卡片 + VBox(立绘 / 名字)」—— 与手牌卡
##   （card.png 骨白纸面 + 铜双线）不是同一只笔，同屏的 TriggerSpot（赭黄菱形徽章）、
##   scene_spot（彩铅建筑 + 铅笔圈）凑成三套语言（`design/分系统体验审计_2026-10-14.md` §I3）。
##   现在直接实例化 `card_chip.tscn` 并 `face_scale = 200/90`：**地图上的人物卡
##   = 手牌里那张卡，放大 2.2222 倍**。外框 / 名字区 / 立绘 /「有话可说」金标
##   全部由 card_chip.gd 一处定义 —— 以后再改卡面，不会再漏掉地图这一份。
##
## ▍场景语义（沿用旧版，未改）：
##   · 点击 → 按 config_path 里的 dialogs 条件挑一段播（**不自动触发**，必须玩家点）；
##   · 「使用中」tag → 禁点 + 灰显 + 悬停提示（`Player.npc` 的中英文键各查一遍）；
##   · 悬停 → 卡面轻微放大（与 scene_spot 同档 1.04）+ tooltip 显示简介；
##   · 显隐**不由本文件定**：如家的管家认 `出现管家` tag，判据写在 `scene/home.gd`
##     （显隐是场景级问题，判据只该有一处）。
##
## ▍尺寸（2026-10-09 拍板「地图人物卡收到卡面比例 200×353」）：
##   `FACE_SCALE = 200 / 90` ⇒ 节点最小尺寸 200 × 353.33。
##   两张图里的 offset 已按此改齐（`map/home.tscn`、`map/prison_spot.tscn`）。
##
## ▍⚠️ ButtonSkin：本节点是「拿 Button 当点击热区」的自绘控件。`_apply_click_style()`
##   把五个状态槽清成 StyleBoxEmpty = `_self_drawn()` 的判据 ①，按钮皮与铅笔动效都会跳过
##   （写法同 trigger_spot.gd）。⚠️ 若哪天在这里设了非空样式盒，人物卡会被套上纸片背景。
##
## 用法：在编辑器中拖入地图场景，设置 charcter_name、config_path 即可。
extends Button

const CHIP_SCENE := preload("res://components/card_chip.tscn")

## 占用中（D-占用）：NPC 持有该 tag 时禁点 + 灰显 + 悬停提示。
const BUSY_TAG := "使用中"
const BUSY_HINT := "他似乎正在做什么，明天再来看看吧。"

## 占位文案的识别子串 —— `characters.json` 里几个地图小 NPC（狱卒 / 校长 / 教师 /
## 路人 A、B）的 `description` 至今还是当年的调试串（「狱卒，如果你看到了这个说明我的
## 程序出现了问题。」），**不是写给人看的角色简介**。
## 判据只认这一条、**不动数据**：拿它把这些卡的悬停提示板挡掉，等真正写了简介
## （或以后换掉占位串）提示板会自动回来。
const PLACEHOLDER_MARK := "说明我的程序出现了问题"

## 卡面放大倍率 = 目标宽 200 / 手牌卡宽 90。**尺寸的唯一来源**（改大小只改这一行）。
const FACE_SCALE := 200.0 / 90.0
## 悬停放大（与 scene_spot 的 HOVER_SCALE 同一档：「感觉得到但说不出」）。
const HOVER_SCALE := 1.04
const HOVER_TWEEN := 0.14

# ============================================================
#  tooltip 落点（2026-10-16）
#  旧版把提示板钉在 Button 的 (0,0) —— 卡面还是 219×322 时它就压在卡面上，
#  卡面放大到 200×353 后「盖住名字区」变得刺眼。现在**永远不压卡面**：
#    卡右侧 → 右边越界翻到左侧 → 两侧都放不下才落到卡下方（同轴贴卡顶边）。
#  ⚠️ 必须给 z_index：地图的树序是「人物卡在最前、触发器点在后」，
#    提示板挪到卡外之后正好压在邻座徽章的位置上，不抬 z 会被后画的徽章盖住。
# ============================================================
const TIP_GAP := 12.0
## 提示板最大宽度（超过就折行）。字号 14 的中文一行约 21 字。
const TIP_MAX_W := 300.0
## 内容边距。样式与「量宽度」共用同一组常量 —— 量的时候不许再写一遍字面量。
const TIP_PAD_X := 8
const TIP_PAD_Y := 4
## 提示板层级（同 scene_spot 的 PANEL_Z：只求压过同画布的兄弟节点）。
const TIP_Z := 60

@export var charcter_name: String
@export var config_path: String

## @deprecated: 保留以兼容现有 .tscn 实例序列化的 ordinary 属性。地图上的落位由节点 offset 定。
@export var ordinary := Vector2(120, 120)

@onready var _tooltip: PanelContainer = $TooltipPanel
@onready var _tooltip_label: Label = $TooltipPanel/Label

## 本卡的角色数据（与手牌里同一张卡同一来源：CardRegistry ← characters.json）。
var card: CardData = null
## config_path 里的对话配置。
var map: Dictionary = {}
var _busy := false
## 卡面容器（= CardChip 实例）。悬停缩放作用在**它**上面，不缩放 Button 自己
## （缩放 Button 会连带改变命中区；trigger_spot 同样是缩放 Badge 而非自己）。
var _face: Control = null
var _hover_tween: Tween = null


func _ready() -> void:
	_apply_click_style()
	_apply_tooltip_style()
	setup()
	EventSignal.dialogue_finished.connect(_on_dialogue_finished)
	EventSignal.day_changed.connect(_on_day_changed)


## 按钮本体不自绘任何东西：五个状态槽一律清成 StyleBoxEmpty。
##   ① 卡面完全由 CardChip 承担（与手牌同源），Button 只是覆盖整张卡的点击热区；
##   ② 这同时是给 ButtonSkin 的自绘判据 —— 命中后不再套纸片背景与铅笔动效。
##      ⚠️ `focus` 也必须清：Button 拿到焦点会在 normal 之上**再画一层** focus 框。
func _apply_click_style() -> void:
	var empty := StyleBoxEmpty.new()
	for slot in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		add_theme_stylebox_override(slot, empty)
	text = ""
	icon = null


## tooltip 样式（深底 + 铜边）。换卡面之前就在，配色未动，只把边距提成常量供落点测量共用。
func _apply_tooltip_style() -> void:
	_tooltip.visible = false
	_tooltip.z_index = TIP_Z
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	ts.border_color = Color(0.55, 0.42, 0.28, 1.0)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(4)
	ts.content_margin_left = TIP_PAD_X
	ts.content_margin_top = TIP_PAD_Y
	ts.content_margin_right = TIP_PAD_X
	ts.content_margin_bottom = TIP_PAD_Y
	_tooltip.add_theme_stylebox_override("panel", ts)
	_tooltip_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	_tooltip_label.add_theme_font_size_override("font_size", 14)


## 算提示板落点：右 → 左 → 下，**任何情况下都不压卡面**。
## 尺寸全部**自己算**（宽度量文本、高度按折行行数），再把宽高一起钉进 custom_minimum_size ——
## ⚠️ 不钉的话：Label 开 autowrap 后最小宽度会退化成 1 个字，最小高度按「当前宽度」自引用。
func _place_tooltip() -> void:
	var txt: String = _tooltip_label.text
	var f: Font = _tooltip_label.get_theme_font("font")
	var fs: int = _tooltip_label.get_theme_font_size("font_size")
	var inner_max: float = TIP_MAX_W - float(TIP_PAD_X) * 2.0
	var inner_w: float = inner_max
	var text_w: float = inner_max
	if f != null and txt != "":
		text_w = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		inner_w = minf(text_w, inner_max)
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 尺寸**自己算**，不读 Label 的最小尺寸：
	#   ① 面板的父节点不是 Container ⇒ 它的 size 只会被最小尺寸抬高、**永远不回收**，
	#      换过文案后旧高度会一直留着（实测卡在 149 上）；
	#   ② autowrap 的 Label 是「按当前宽度算高度」的，面板不可见 / 还没排过版时，
	#      它算出来的是旧宽度的结果（实测 141，正确值 33）。
	# 口径与 Label 自己一致：折行后的**行数 × 行高 + (行数−1) × line_spacing**（尾行无尾随间距）。
	# ✅ 实测：23 字 @284px → 2 行 → 高 41；17 字单行 → 高 23，与 Label 真渲染逐像素一致。
	var line_h: float = float(f.get_height(fs)) if f != null else float(fs)
	var line_sp: float = float(_tooltip_label.get_theme_constant("line_spacing", "Label"))
	var wrapped: Vector2 = Vector2(text_w, line_h)
	if f != null and txt != "":
		wrapped = f.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, inner_w, fs)
	var lines: int = maxi(1, int(round(wrapped.y / maxf(line_h, 1.0))))
	# 折行后的真实高度：尾行没有尾随 line_spacing。
	var lbl_h: float = float(lines) * line_h + float(lines - 1) * line_sp
	# 🔴 **宽度和高度都必须写进 `custom_minimum_size`**，否则尺寸收不回来 ——
	#    autowrap 的 Label 是「按**自己当前宽度**算最小高度」的自引用结构：面板还没排过版时
	#    它算的是 .tscn 里那句 "Tooltip" 留下的旧宽度（实测最小高 141，正确值 33）；
	#    而 `size` 的 setter 只会被最小尺寸**往上顶、永不缩回**（写 33 读回来还是 141）。
	#    只钉宽度不够：高度仍走那条自引用路径 ⇒ 必须一起钉死，最小尺寸才不再看「当前宽度」。
	var panel_size := Vector2(inner_w + float(TIP_PAD_X) * 2.0, lbl_h + float(TIP_PAD_Y) * 2.0)
	# ① 先把 Label 的**宽度**真正改掉（宽度不会被夹坏：autowrap 的最小宽只有 1 个字），
	#    它的「最小高度」是按当前宽度算的 ⇒ 宽度一改，最小高度才会从 141 掉回 33。
	_tooltip_label.size.x = inner_w
	# ② 再把宽高一起钉进 custom_minimum_size（内容最小 = max(自定义, 自算)，两边都得对）。
	_tooltip_label.custom_minimum_size = Vector2(inner_w, lbl_h)
	_tooltip.custom_minimum_size = panel_size
	_tooltip_label.size = Vector2(inner_w, lbl_h)
	_tooltip.size = panel_size

	var w: float = _tooltip.size.x
	var vp: Vector2 = get_viewport_rect().size
	var origin: Vector2 = global_position
	if origin.x + size.x + TIP_GAP + w <= vp.x:
		_tooltip.position = Vector2(size.x + TIP_GAP, 0.0)
	elif origin.x - TIP_GAP - w >= 0.0:
		_tooltip.position = Vector2(-(w + TIP_GAP), 0.0)
	else:
		_tooltip.position = Vector2(0.0, size.y + TIP_GAP)


func setup() -> void:
	card = CardRegistry.get_card(charcter_name)
	if card == null:
		# 数据缺失不该让地图上出现一块空白 / 死区：用 key 当名字的兜底卡面顶上，并吼一声。
		push_warning("[Character] characters.json 里没有 %s —— 用兜底卡面（名字取 key）" % charcter_name)
		card = CardData.from_character(charcter_name, {})
	_build_face()
	_tooltip_label.text = card.description
	if config_path != "":
		var cf := FileAccess.open(config_path, FileAccess.READ)
		if cf != null:
			map = JSON.parse_string(cf.get_as_text())
			cf.close()
	_refresh_busy()


## 卡面 = 手牌同一个组件（card_chip.tscn）放大 FACE_SCALE 倍。
## 鼠标一律穿透到 Button（`set_draggable(false)` → mouse_filter = IGNORE）：
## 地图上的卡不参与拖拽，点击必须落到 Button 的 `pressed` 上。
func _build_face() -> void:
	custom_minimum_size = CardChip.CARD_SIZE * FACE_SCALE
	var chip: CardChip = CHIP_SCENE.instantiate()
	chip.name = "Face"
	chip.set_draggable(false)
	chip.set_face_scale(FACE_SCALE)
	chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(chip)
	# 悬停放大的支点取卡面中心（Control 默认支点在左上角，放大只会朝右下长）。
	chip.resized.connect(func() -> void: chip.pivot_offset = chip.size * 0.5)
	# 卡面必须排在最底下：TooltipPanel 是同级的后一个子节点，
	# 而运行时 add_child 的卡面默认被追加到**末尾** ⇒ 悬停提示会被卡面盖住。
	move_child(chip, 0)
	chip.set_card(card)
	_face = chip


func _on_pressed() -> void:
	if _busy:
		return
	var target_dialog: Variant = get_dialog()
	if target_dialog == null:
		return
	PlotImporter.add_plot(target_dialog["path"], target_dialog["name"])


## 悬停：显示简介 + 卡面轻轻放大。
## ⚠️ 占位简介 / 空简介的卡**只放大、不弹提示板** —— 否则玩家会在卡边上读到
##    「如果你看到了这个说明我的程序出现了问题」这种调试串。
func _on_mouse_entered() -> void:
	if _tooltip_should_show():
		_place_tooltip()
		_tooltip.visible = true
	else:
		_tooltip.visible = false
	if not _busy:
		_tween_face_scale(HOVER_SCALE)


func _on_mouse_exited() -> void:
	_tooltip.visible = false
	_tween_face_scale(1.0)


## SINE/EASE_OUT：鼠标响应类缓动，不走 8fps 阶梯
## （按拍跳是给「重画线稿」的呼吸 / 抖动用的，不是给鼠标响应用的 —— 同 trigger_spot）。
func _tween_face_scale(to_scale: float) -> void:
	if _face == null:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	if is_equal_approx(_face.scale.x, to_scale):
		return
	_hover_tween = create_tween()
	_hover_tween.tween_property(_face, "scale", Vector2(to_scale, to_scale), HOVER_TWEEN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 禁用态下 `mouse_exited` 不一定送达（鼠标本来就停在上面），
## 不主动复位的话卡面会一直挂在放大态上。
func _reset_hover() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	if _face != null:
		_face.scale = Vector2.ONE


# ============================================================
#  占用中（D-占用）：NPC 持有「使用中」tag 时禁点 + 灰显 + 悬停提示。
#  键映射：剧情 effect 用中文键写 Player.npc（如「狱卒」），
#  charcter_name 是英文（如 "Jailer"），故中英文键都查一遍。
# ============================================================
func _refresh_busy() -> void:
	var cn_name: String = card.display_name if card != null else charcter_name
	_busy = Player.npc_has_tags(cn_name, [BUSY_TAG], 1) or Player.npc_has_tags(charcter_name, [BUSY_TAG], 1)
	_apply_busy_visual()


func _apply_busy_visual() -> void:
	var desc: String = card.description if card != null else ""
	if _busy:
		modulate = Color(0.55, 0.55, 0.55, 0.7)
		disabled = true
		_tooltip_label.text = BUSY_HINT
		_reset_hover()
	else:
		modulate = Color.WHITE
		disabled = false
		_tooltip_label.text = desc
	# 文案换过 ⇒ 宽度变了，落点要重算（鼠标正停在卡上时也会发生：过天 / 对话结束）。
	_place_tooltip()
	# 换成「没得看」的文案（占位 / 空）时，别把上一次留下的旧提示板晾在屏上。
	if not _tooltip_should_show():
		_tooltip.visible = false


## 这条简介值不值得给玩家看：空串、或仍是调试占位串 ⇒ 不值得。
func _has_real_description() -> bool:
	var d: String = card.description if card != null else ""
	d = d.strip_edges()
	return not d.is_empty() and not d.contains(PLACEHOLDER_MARK)


## 悬停时要不要弹提示板：有真简介；或「使用中」（那时文案固定是 BUSY_HINT）。
func _tooltip_should_show() -> bool:
	return _busy or _has_real_description()


func _on_dialogue_finished() -> void:
	_refresh_busy()


func _on_day_changed(_day: int) -> void:
	_refresh_busy()


# ============================================================
#  对话选择：按 conditions/limits 从 map.dialogs 中挑一个匹配的。
# ============================================================

func get_dialog() -> Variant:
	var dialogs = map.get("dialogs", {})

	for dialog_name in dialogs:
		var dialog = dialogs[dialog_name]
		var conditions = dialog.get("conditions", {})
		var limits = dialog.get("limits", {})
		var method = 1
		var flag := false

		#处理其他数值条件
		if "others" in conditions:
			var others = conditions.others
			for other in others:
				var res = Player[others[other].name] - others[other].value
				var sentence = others[other].sentence

				if sentence == 0:
					if res != 0:
						flag = true
						break
				if sentence == 1:
					if res < 0:
						flag = true
						break
				if sentence == -1:
					if res > 0:
						flag = true
						break

		# 处理玩家标签条件
		if "method" in conditions:
			method = conditions.method
		if "tags" in conditions:
			if not Player.player_has_tags(conditions.tags, method):
				continue
		if "num_tags" in conditions:
			var num_tags = conditions["num_tags"]
			for num_tag_name in num_tags:
				if not Player.player_meet_num_tag(num_tags[num_tag_name].name, num_tags[num_tag_name].left, num_tags[num_tag_name].right):
					flag = true
					break
		# 处理NPC条件
		if "npc" in conditions:
			var npc_conditions = conditions.npc
			# 遍历NPC条件字典
			for npc_name in npc_conditions:
				var npc = npc_conditions[npc_name]
				var npc_method = 1
				if "method" in npc:
					npc_method = npc.method
				if "tags" in npc:
					if not Player.npc_has_tags(npc_name, npc.tags, npc_method):
						flag = true
						break
				if "num_tags" in npc:
					var npc_num_tags = npc["num_tags"]
					for num_tag_name in npc_num_tags:
						if not Player.npc_meet_num_tag(npc_num_tags[num_tag_name].name, npc_name, npc_num_tags[num_tag_name].left, npc_num_tags[num_tag_name].right):
							flag = true
							break
					if flag:
						break

		if flag:
			continue

		# 处理限制条件
		if "method" in limits:
			method = limits.method
		if "tags" in limits:
			if Player.player_has_tags(limits.tags, method):
				continue
		if "num_tags" in limits:
			var lim_num_tags = limits["num_tags"]
			for num_tag_name in lim_num_tags:
				if Player.player_meet_num_tag(lim_num_tags[num_tag_name].name, lim_num_tags[num_tag_name].left, lim_num_tags[num_tag_name].right):
					flag = true
					break

		# 处理NPC限制条件
		if "npc" in limits:
			var npc_limits = limits.npc
			# 遍历NPC限制字典
			for npc_name in npc_limits:
				var npc = npc_limits[npc_name]
				var npc_method = 1
				if "method" in npc:
					npc_method = npc.method
				if "tags" in npc:
					if Player.npc_has_tags(npc_name, npc.tags, npc_method):
						flag = true
						break
				if "num_tags" in npc:
					var npc_num_tags = npc["num_tags"]
					for num_tag_name in npc_num_tags:
						if Player.npc_meet_num_tag(npc_num_tags[num_tag_name].name, npc_name, npc_num_tags[num_tag_name].left, npc_num_tags[num_tag_name].right):
							flag = true
							break
					if flag:
						break

		if flag:
			continue

		return dialog

	return null
