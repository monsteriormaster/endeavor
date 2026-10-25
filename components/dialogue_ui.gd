extends Control

const TextVars := preload("res://script/text_vars.gd")

## 设置页场景。对话界面右上角的「设置」按钮呼出它（含 保存进度 / 读取存档）。
const SETTINGS_MENU_PATH := "res://components/settings_menu.tscn"

@export_group("UI")
@export var character_name_text: Label
@export var text_box: Label
@export var option_box: VBoxContainer
@export var panel: Panel
## 纸面板底图（`art/ui/dlg_panel.png`）：纸面 + 手绘铜框 + 顶中菱形 + 四角饰线 + 顶影。
## **几何写死在 tscn**（工程 stretch = canvas_items + keep，逻辑分辨率恒 1920x1080 → 与验收稿逐像素一致）；
## 报纸布局的 Panel 是居中 720x420 的另一套尺寸，那时要把这张图藏起来。
@export var paper_art: TextureRect
## 说话人立绘。树序排在 Panel **之前** → 下半身被对话框天然盖住，不需要任何裁剪逻辑。
@export var portrait_rect: TextureRect
## 正文滚动容器：文字过长时可以向下翻。
@export var text_scroll: ScrollContainer
## 正文四周的内边距容器（`Panel/MarginContainer`）。下边距会被 `_snap_text_viewport()`
## 在运行时改写 —— 目的是让正文视口**恰好是行高的整数倍**，见该函数注释。
@export var content_margin: MarginContainer
## 历史记录入口按钮（Panel 内右上角）。**必须是 Button**：它默认 mouse_filter=STOP，
## 会先吃掉点击 → 不会穿透到 `Panel.gui_input → _on_click` 直接跳过一整段对话。
@export var history_button: Button
## 设置入口按钮（Panel 内右上角，「历史」的左侧）。呼出整屏设置页 ——
## 玩家在**对话中**就能存档 / 读档，且读档会回到这段剧情（D-SV10）。
## 与 history_button 同理必须是 Button：默认 mouse_filter=STOP 会先吃掉点击，
## 不会穿透到 `Panel.gui_input → _on_click` 白跳一句。
@export var settings_button: Button
## 历史浮层。**全屏**（galgame 式回想），树序排在 Panel 之后 → 画在对话框与立绘之上；
## **不进 OverlayRoot 栈**（对话本身已是模态覆盖层，再叠一层只会多一个 ModalBlocker + 一层 Esc 语义）。
@export var history_panel: Panel
@export var history_list: VBoxContainer
@export var history_scroll: ScrollContainer
## 右上角「共 N 条」计数。
@export var history_count: Label
## 名字签条。**整条**（纸片 + 手绘铜边 + 居中 Label）—— 开关时关整条，不是关里面的 Label：
## 只关 Label 会剩一张空纸片浮在对话框上方。
## ⚠️ 签条**完全落在纸沿之上**（底边距纸沿 10px），且树序排在 Panel 之后 → 任何框线压不住它。
@export var name_tag: PanelContainer
## 纸沿（面板上沿）到屏幕底的距离 → 纸沿在 y = 1080 - 180 = 900。
## ⚠️ 改这个数会连带 OptionsContainer / 签条 / 立绘露出的高度，见 _apply_layout 的注释。
@export var default_panel_height: float = 180.0
## 纸左右各留的白。与素材 dlg_panel.png 里纸面的位置一一对应（改这里必须同步重出素材）。
const PAPER_INSET_X: float = 48.0
## 纸底沉出屏幕的距离 —— 底边那道铜线**永远不出现在画面里**（和验收稿一样）。
const PAPER_BOTTOM_OVER: float = 34.0

## 正文四周的内边距（与验收稿对齐：`BY = 纸沿 + 42`）。
## ⚠️ 下边距只是**基准值**：真正的下边距由 `_snap_text_viewport()` 现算并覆写，
## 好让视口高落在行高的整数倍上。这里的 50 只决定「基准视口高」= 214-42-50 = 122。
const TEXT_MARGIN_TOP: float = 42.0
const TEXT_MARGIN_BOTTOM: float = 50.0

## 报纸弹窗尺寸（屏幕正中，固定宽高，内容过长会被裁切）
const NEWSPAPER_WIDTH: float = 720.0
const NEWSPAPER_HEIGHT: float = 420.0

enum LayoutMode { DEFAULT, NEWSPAPER }
## 避开原生 Control.layout_mode（Godot 4.7+ 已将其作为布局系统属性占用）。
var _layout: LayoutMode = LayoutMode.DEFAULT

# ============================================================
#  说话人立绘（M-ANI3）
# ============================================================
## 内容框底边的屏幕 y。屏幕高 1080 → 沉出屏幕 190px，下半身正好被纸面板（纸沿 y=900）吃掉：
## 玩家看到的是「站在对话框后面的人」，大腿以下不露面。
## 好处有二：① 不用写裁剪；② 避开全身立绘里最容易崩的脚部。
const PORTRAIT_BOTTOM: float = 1270.0
## 内容框的水平中心（屏幕右区）。
## ⚠️ **1470 不是随手挑的**：纸左右各留 48px 白之后（纸面 48..1872），
## 按 resoures/portraits.json 的 31 张内容框逐个核算渲染右缘 ——
## 原值 1550 时最宽的 louise.png 右缘到 **1922**，会露出纸外；
## 改成 1470 后最宽右缘 1842，**31 张全部进纸**（最窄那张仍留 30px 余量）。
const PORTRAIT_CENTER_X: float = 1470.0
## 内容框的**视觉身高**：所有角色统一。art/ 里 29 张立绘的内容框差异极大
## （宽 289~1028、高 974~1984），按整图缩放会让露易丝比阿尔温小一圈 —— 必须按内容框归一。
const PORTRAIT_TARGET_H: float = 1120.0
const PORTRAIT_FADE_IN: float = 0.20
const PORTRAIT_FADE_OUT: float = 0.16
## 入场起始的下沉量（px）：淡入的同时上浮，给「出场」一点重量。
const PORTRAIT_RISE: float = 12.0

## 正文滚动条：极细的墨色条，只在内容溢出时出现（SCROLL_MODE_AUTO）。
const SCROLLBAR_W: float = 6.0
const SCROLLBAR_TRACK := Color(0.0, 0.0, 0.0, 0.05)
const SCROLLBAR_GRAB := Color(0.220, 0.161, 0.118, 0.42)

## 历史条目里说话人名字的颜色（墨褐，与地图提示文字同源）与玩家选项行的颜色。
const HISTORY_NAME_COL := Color(0.220, 0.161, 0.118)
const HISTORY_MINE_COL := Color(0.353, 0.302, 0.243)
## 名字列固定宽度（条目行 = 名字列 + 正文列）。
const HISTORY_NAME_W: float = 132.0

## 羊皮纸底 / 铜边（与 `card_area.tscn` 的 TH_card 同源 token，全工程一套）。
const PAPER_SHEET_COL := Color(0.910, 0.863, 0.780)      # #E8DCC7
const COPPER_COL := Color(0.561, 0.424, 0.180, 0.71)     # #8F6C2E @ α0.71

# ---- 选项按钮：纸片外观自 2026-10-06 起由 Autoload `ButtonSkin` 统一提供 ----
## 选项纸片的**最小**宽度（验收稿里的定宽）。文本更长时按钮自己变宽，仍然居中。
const OPTION_MIN_W: float = 568.0
const OPTION_MIN_H: float = 52.0
const OPTION_FONT_SIZE: int = 20
## 选项文字用墨色（与面板正文同族）；不可选的那档用灰褐，但仍可读。
const OPTION_INK := Color(0.180, 0.141, 0.094)           # #2E2418
const OPTION_DISABLED_INK := Color(0.420, 0.380, 0.330)

## 面板/报纸两种底样式（懒建，避免每次 show_dialogue_group 都新建 StyleBox）。
var _sb_plain: StyleBox
var _sb_newspaper: StyleBox

## 当前立绘的图片路径。**同一个人连着说多句时一个字都不动**（不重播动画）——
## 只有说话人真的换了，才做「旧的淡出 / 新的淡入」。否则连续对白会一直在闪。
var _portrait_key := ""
var _portrait_tween: Tween


var main_dialogue: DialogueGroup
var dialogue_index: int = 0
var typing_tween: Tween

## ⚠️ 必须显式标注 String：Player.player_name 是 Autoload 的弱类型 @export，
## 不标注的话本变量是 Variant，任何 `:= hero.xxx()` 链式调用都会推断失败（见 CODE_MAP §8）。
var hero: String = Player.player_name

## 选项触发了"取名弹窗"等阻塞型 effect 时，暂存要跳转的下一步，等弹窗确认后再继续。
var _pending_next: int = -1

## ---- 历史记录（会话内，只读回看）----
## 元素：{name, text, mine}。mine=true = 玩家选过的选项。
## **只保当前这一段剧情**（一个 dialogue_ui 实例 = 一段剧情）：show_dialogue_group 时清空，
## 实例销毁即消失 —— 因此完全不碰 SaveLoader / PERSISTENT_FIELDS。
var _history: Array[Dictionary] = []
var _history_open := false


## `start_index` = 续播起点（D-SV10），默认 **-1 = 从头播**（落在第 0 句）。
## 读档恢复时由 PlotImporter 传入存档记下的句号（≥0），直接从那一句开始；
## 断点及之前的节点 effect 已被标为「已执行」（见 PlotImporter.execute_dialogue），
## 所以这一跳不会重复结算数值。
func show_dialogue_group(dialogue_group: DialogueGroup, start_index: int = -1) -> void:
	main_dialogue = dialogue_group
	var n: int = dialogue_group.dialogue_list.size()
	if n == 0:
		# 空剧情（本应被 add_plot 挡掉）→ 直接收场，绝不让 dialogue_list[0] 越界崩。
		Player.is_dialogue_exist = false
		Player.plot = {}
		visible = false
		_close_self()
		return
	dialogue_index = clampi(start_index, 0, n - 1)
	# 新的一段剧情 → 历史重新开始（会话内语义）。同一实例复用同一面板，必须显式复位。
	_history.clear()
	_history_open = false
	if history_panel != null:
		history_panel.visible = false
	_apply_layout(dialogue_group.layout)
	visible = true
	display_next_dialogue()


func _apply_layout(layout: String) -> void:
	if layout == "newspaper":
		_layout = LayoutMode.NEWSPAPER
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.offset_left = -NEWSPAPER_WIDTH / 2.0
		panel.offset_right = NEWSPAPER_WIDTH / 2.0
		panel.offset_top = -NEWSPAPER_HEIGHT / 2.0
		panel.offset_bottom = NEWSPAPER_HEIGHT / 2.0
		panel.custom_minimum_size = Vector2(NEWSPAPER_WIDTH, NEWSPAPER_HEIGHT)
		# 纸底图是按「贴屏幕底的整幅纸」烤死的，套到 720x420 居中框上必然错位 → 藏掉，
		# 换成羊皮纸平色底（顺带把「报纸对话也是黑板」这个老毛病一起修了）。
		if paper_art != null:
			paper_art.visible = false
		_set_panel_style(_style_newspaper())
		# 报纸弹窗不需要角色名 & 选项；报纸也没有「说话人」这个概念，立绘一并退场。
		_set_name_tag_visible(false)
		option_box.visible = false
		_hide_portrait_immediate()
		# 报纸走「点击任意处推进」，没有对话历史可言。
		# ⚠️ 设置按钮也一并收掉：报纸模式由 `_input` 对**任意**左键点击推进，
		#    而 `_input` 早于 GUI 分发、按钮的 mouse_filter 拦不住它 ——
		#    留着按钮会「点一下既推进又开设置页」。两件事一起发生。
		if history_button != null:
			history_button.visible = false
		if settings_button != null:
			settings_button.visible = false
		_history_open = false
		if history_panel != null:
			history_panel.visible = false
	else:
		_layout = LayoutMode.DEFAULT
		panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		# ⚠️ 四个 offset **必须全部显式给**：`set_anchors_preset()` 会按当前 rect 反推 offset，
		# 漏掉一个就会静默沿用上一次布局（报纸）的值 —— 不报错，只是纸跑到屏幕中间。
		panel.offset_left = PAPER_INSET_X
		# ⚠️ 右边距是 **47 不是 48**：本组件的根 Control 带 `offset_right = -1`，
		# 它的 rect 是 **1919** 宽而不是 1920 → 想在屏幕坐标里左右各留 48，
		# 右 offset 必须写 -(48-1)。写成对称的 -48 时面板右缘会比纸底图少 1px
		# （纸照画 1824、点击区少 1px —— 不报错，只有量 rect 才看得出来）。
		panel.offset_right = -(PAPER_INSET_X - 1.0)
		panel.offset_top = -default_panel_height
		panel.offset_bottom = PAPER_BOTTOM_OVER
		panel.custom_minimum_size = Vector2(0.0, default_panel_height)
		if paper_art != null:
			paper_art.visible = true
		_set_panel_style(_style_plain())
		_sync_name_tag()
		# 面板几何刚定下来 → 顺手把正文视口钉成行高整数倍（见 _snap_text_viewport）。
		_snap_text_viewport()
		option_box.visible = true
		if history_button != null:
			history_button.visible = true
		if settings_button != null:
			settings_button.visible = true


## Panel 自身只负责「一块透明底板 + 接收点击」，视觉全交给 PaperArt / StyleBoxTexture。
func _set_panel_style(sb: StyleBox) -> void:
	panel.add_theme_stylebox_override("panel", sb)


func _style_plain() -> StyleBox:
	if _sb_plain == null:
		_sb_plain = StyleBoxEmpty.new()
	return _sb_plain


## 报纸模式的面板底：羊皮纸 + 铜边（直角）。替代原来的引擎默认半透明黑板。
func _style_newspaper() -> StyleBox:
	if _sb_newspaper == null:
		var sb := StyleBoxFlat.new()
		sb.bg_color = PAPER_SHEET_COL
		sb.border_color = COPPER_COL
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(0)
		_sb_newspaper = sb
	return _sb_newspaper


## 开关**整条**名字签条 —— 不是关里面的 Label：只关 Label 会剩一张空纸片浮在框上方。
func _set_name_tag_visible(v: bool) -> void:
	if name_tag != null:
		name_tag.visible = v


## 按「当前这句有没有说话人」决定签条去留。
## ⚠️ 必须按**名字是否为空**收掉整条：旁白的 Label 宽度是 0，但 PanelContainer 自带
## 44+44 的内容边距 → 不收的话框上方会一直浮着一张没字的空纸片（不报错，只有看图才发现）。
func _sync_name_tag() -> void:
	if name_tag == null:
		return
	var has_name: bool = _layout == LayoutMode.DEFAULT \
			and not character_name_text.text.strip_edges().is_empty()
	name_tag.visible = has_name


func display_next_dialogue() -> void:
	if dialogue_index == -1:
		Player.is_dialogue_exist = false
		# D-SV10：剧情正常播完 → 清掉剧情位置锚点，下次读档不再续播这一段。
		Player.plot = {}
		visible = false
		EventSignal.emit_signal('dialogue_finished')
		_close_self()
		return

	clear_options()
	# D-SV10：把「当前句号」实时写回锚点 —— 玩家此刻点设置存档，记下的就是这一句。
	_sync_plot_index()

	var dialogue = main_dialogue.dialogue_list[dialogue_index]
	var full_text: String = TextVars.resolve(dialogue.content, dialogue.context)

	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
		text_box.text = full_text
		if dialogue.is_option == false:
			dialogue_index = _resolve_next(dialogue)
	else:
		character_name_text.text = TextVars.resolve(dialogue.character_name, dialogue.context)
		# 旁白（名字为空）要把整条签条收掉，见 _sync_name_tag 的注释。
		_sync_name_tag()
		# 记录用的是**解析后的完整文本**（full_text），不是打字中途的半截 ——
		# 所以历史面板里看到的就是这句最终的样子。旁白（名字为空）照样记。
		_record_history(character_name_text.text, full_text)
		# 立绘跟着「当前这句的说话人」走；旁白（名字空）/ 无素材会干净退场。
		_update_portrait(dialogue)

		typing_tween = get_tree().create_tween()
		text_box.text = ""
		for character in full_text:
			typing_tween.tween_callback(append_character.bind(character)).set_delay(0.05)
		if dialogue.is_option == false:
			typing_tween.tween_callback(func(): dialogue_index = _resolve_next(dialogue))
		# ⚠️ 收尾必须补一次：最后一个字敲完的**同一帧**，tween 就已 is_running()=false，
		# `_process` 的跟随就此断掉，而 Label 的高度（→ max_value）还要再结算一帧。
		# 实测 409 字那条会停在 131 / 287，画面差整整 5 行没露出来。
		typing_tween.tween_callback(_settle_scroll)


	if dialogue.effect != {} and !dialogue.is_effect_excute:
		dialogue.is_effect_excute = true
		var blocked := deal_effect(dialogue.effect)
		if blocked:
			# 步骤级阻塞型 effect（如 name_child）：弹窗确认后需自动推进到本步 next。
			# 选项级 name_child 由 on_option_entered 已设置 _pending_next，这里不覆盖。
			_pending_next = _resolve_next(dialogue)

	if dialogue.is_option:
		show_option(dialogue.options, dialogue.context)


## D-SV10：把当前句号写回 `Player.plot["index"]`，供「对话中存档」记录剧情位置。
## 锚点由 PlotImporter.add_plot 建好；此处只更新 index（空锚点 = 不在剧情中，什么都不做）。
func _sync_plot_index() -> void:
	var anchor: Variant = Player.plot
	if anchor is Dictionary and not (anchor as Dictionary).is_empty():
		(anchor as Dictionary)["index"] = dialogue_index


func append_character(character: String) -> void:
	text_box.text += character


func show_option(options, ctx: Dictionary) -> void:
	for option in options:
		if option["is_ava"]:
			var choice_text: String = TextVars.resolve(option.text, ctx)
			var option_label := _make_option_button(choice_text)
			# 把选项文本一并绑进回调，供历史记录写入「玩家说过的话」。
			option_label.pressed.connect(on_option_entered.bind(option.effect, option.next, choice_text))
			option_box.add_child(option_label)
		else:
			var option_label := _make_option_button(TextVars.resolve(option["condition"].description, ctx))
			option_label.disabled = true
			option_box.add_child(option_label)


## 选项纸片：纸面 + 手绘铜边（与面板同源），文字墨色居中。
##
## 居中靠 `SIZE_SHRINK_CENTER` —— `OptionContainer` 是整屏宽（1920）的 VBoxContainer，
## 不给这个 flag 按钮会被拉成 1920 宽把整条选项带铺满（旧实现就是这个毛病，
## 再加上引擎默认灰底 → 一眼就不属于这个世界）。
## `OptionContainer` 自身是居中锚点（屏中 960,540），所以按钮块天然落在屏幕正中。
func _make_option_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(OPTION_MIN_W, OPTION_MIN_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", OPTION_FONT_SIZE)
	b.add_theme_color_override("font_color", OPTION_INK)
	b.add_theme_color_override("font_hover_color", OPTION_INK)
	b.add_theme_color_override("font_pressed_color", OPTION_INK)
	b.add_theme_color_override("font_disabled_color", OPTION_DISABLED_INK)
	# 九宫格贴图会被平铺/拉伸 → 必须 LINEAR，否则细描边和纸纹被 NEAREST 点采样吃掉
	# （与 card_chip.gd 给 4x 卡面单开 LINEAR 同源）。
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 纸片样式（四态 + 九宫格）自 2026-10-06 起由 Autoload `ButtonSkin` 统一提供 ——
	# 这里只留尺寸 / 字号 / 字色。**不要再 add_theme_stylebox_override**：
	# ButtonSkin 挂在 node_added（早于本函数），覆盖顺序一旦变动就会静默长出第二套皮。
	return b


## 对话框右上角两颗小按钮（历史 / 设置）的字色 / 字号。小尺寸由 ButtonSkin 自动判档
## （短边 < 36px → 小档贴图），所以这里**不需要**再指定「小一号的九宫格边块」。
func _style_corner_button(btn: Button) -> void:
	if btn == null:
		return
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", OPTION_INK)
	btn.add_theme_color_override("font_hover_color", OPTION_INK)
	btn.add_theme_color_override("font_pressed_color", OPTION_INK)
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _ready() -> void:
	visible = false
	if history_panel != null:
		history_panel.visible = false
	# 文字大小：跟随全局设置（与触发器右侧正文一致），并监听滑块联动。
	_apply_text_font_size()
	if not Settings.text_font_size_changed.is_connected(_on_text_font_size_changed):
		Settings.text_font_size_changed.connect(_on_text_font_size_changed)
	_style_scrollbar(text_scroll)
	_style_scrollbar(history_scroll)
	_style_corner_button(history_button)
	_style_corner_button(settings_button)


## 把滚动条换成「极细墨色条」：引擎默认滚动条是灰底带箭头按钮，
## 与彩铅/纸的界面语言冲突。只在内容溢出时出现（AUTO），短句完全看不到它。
## 正文与历史列表共用同一套样式。
func _style_scrollbar(sc: ScrollContainer) -> void:
	if sc == null:
		return
	var sb: VScrollBar = sc.get_v_scroll_bar()
	sb.custom_minimum_size = Vector2(SCROLLBAR_W, 0.0)
	var track := StyleBoxFlat.new()
	track.bg_color = SCROLLBAR_TRACK
	sb.add_theme_stylebox_override("scroll", track)
	var grab := StyleBoxFlat.new()
	grab.bg_color = SCROLLBAR_GRAB
	grab.set_corner_radius_all(3)
	for st in ["grabber", "grabber_highlight", "grabber_pressed"]:
		sb.add_theme_stylebox_override(st, grab)


## 打字过程中每帧跟到最新一行（「文字过长时可以向下翻」的核心）。
##
## ⚠️ 不能改成「在 append_character 里滚一次」：Label 高度变化后 ScrollContainer 的
## `max_value` 要**晚一帧**才结算，每字调一次等于永远拿上一帧的上限 —— 实测长文本滚到底时
## `scroll_vertical` 停在 0，画面完全没动（而且不报任何错）。
func _process(_delta: float) -> void:
	if typing_tween != null and typing_tween.is_running():
		_follow_scroll()


## 跟着最新一行滚到底。短句不溢出时 scroll 恒为 0，等于什么都没发生。
func _follow_scroll() -> void:
	if text_scroll == null:
		return
	var vs: VScrollBar = text_scroll.get_v_scroll_bar()
	# ⚠️ 偏移上限是 `max_value - page`，**不是** `max_value`：Godot 里 `VScrollBar.max_value`
	# 是**内容总高**，`page` 才是视口高。设 max_value 会被引擎自己 clamp 成同一个值
	# （所以画面是对的），但语义错 —— 写判据时会把自己骗到（实测连续误判两轮「没滚到底」）。
	text_scroll.scroll_vertical = int(maxf(vs.max_value - vs.page, 0.0))


## 打字结束后的收尾跟随（挂在 typing_tween 末尾）。
## Label 的高度在最后一字落地后还要再结算几帧，`max_value` 才到最终值；
## 这里等它落定再把最后一屏钉到底，玩家不用手动滚。
## ⚠️ 固定等 6 帧而不是「等 max_value 稳定就 break」：后者在「高度还没开始涨」
## 的那一帧就会误判成已稳定，等于没滚。6 帧 ≈ 0.1s，玩家感知不到。
func _settle_scroll() -> void:
	if text_scroll == null:
		return
	for i in 6:
		await get_tree().process_frame
	_follow_scroll()


## ---- 立绘 ----
## 按当前这句的说话人更新立绘。三个分支：
##   ① 说话人没变（同一人连说多句）→ 什么都不做，一个字都不动；
##   ② 解析不到立绘（旁白 / 未接线角色）→ 淡出退场，只留文字；
##   ③ 换了人 → 旧的淡出、新的淡入。
func _update_portrait(dialogue) -> void:
	if portrait_rect == null:
		return
	var name_text: String = TextVars.resolve(dialogue.character_name, dialogue.context)
	var entry: Dictionary = PortraitRegistry.resolve(name_text, dialogue.portrait)
	var key: String = "" if entry.is_empty() else String(entry.get("image", ""))
	if key == _portrait_key:
		return
	_portrait_key = key
	if key == "":
		_fade_out_portrait()
		return
	_fade_in_portrait(entry)


## 按「内容框」等比缩放并摆位：内容框底边贴 PORTRAIT_BOTTOM、水平中心对 PORTRAIT_CENTER_X。
## ⚠️ 用 global_position 而不是 position —— 本控件的 global 原点在 y=-1（anchors 到底部），
## 用局部坐标会整块偏 1px。
func _fade_in_portrait(entry: Dictionary) -> void:
	var path: String = String(entry.get("image", ""))
	var tex: Texture2D = load(path)
	if tex == null:
		_fade_out_portrait()
		return
	var ts: Vector2 = tex.get_size()
	var bb: Rect2 = PortraitRegistry.bbox_of(entry, ts)
	if ts.x <= 0.0 or ts.y <= 0.0 or bb.size.y <= 0.0:
		_fade_out_portrait()
		return

	var s: float = PORTRAIT_TARGET_H / bb.size.y
	var scaled_pos: Vector2 = bb.position * s
	var scaled_size: Vector2 = bb.size * s

	portrait_rect.texture = tex
	portrait_rect.size = ts * s
	portrait_rect.global_position = Vector2(
		PORTRAIT_CENTER_X - scaled_pos.x - scaled_size.x * 0.5,
		PORTRAIT_BOTTOM - scaled_pos.y - scaled_size.y)

	portrait_rect.visible = true
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	var base_y: float = portrait_rect.global_position.y
	portrait_rect.modulate.a = 0.0
	portrait_rect.global_position.y = base_y + PORTRAIT_RISE
	_portrait_tween = create_tween().set_parallel(true)
	_portrait_tween.tween_property(portrait_rect, "modulate:a", 1.0, PORTRAIT_FADE_IN)
	_portrait_tween.tween_property(portrait_rect, "global_position:y", base_y, PORTRAIT_FADE_IN)


func _fade_out_portrait() -> void:
	if portrait_rect == null or not portrait_rect.visible:
		return
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	_portrait_tween = create_tween()
	_portrait_tween.tween_property(portrait_rect, "modulate:a", 0.0, PORTRAIT_FADE_OUT)
	_portrait_tween.tween_callback(func(): portrait_rect.visible = false)


## 无条件立刻收起（报纸弹窗等场合，不要淡出动画）。
func _hide_portrait_immediate() -> void:
	if _portrait_tween != null and _portrait_tween.is_valid():
		_portrait_tween.kill()
	_portrait_key = ""
	if portrait_rect != null:
		portrait_rect.visible = false
		portrait_rect.modulate.a = 0.0


## 把正文视口高**钉成整行数**（多出来的那截并进下边距）。
##
## 为什么非做不可：视口若不是整行高，`_settle_scroll()` 滚到底之后
## **最上面那一行会被拦腰切成半行** —— 画面上看是「一行字被横着削掉一截」，像渲染坏了。
## 实测（`debug/_dlg_capacity_scan.gd`）：全工程 432 条台词里 3 条超过一屏，
## 其中 2 条会出这个现象（163 字/6 行 削 15px、168 字/5 行 削 12px）。
##
## ⚠️ 两个坑，都踩过：
##  ① **真实行距 ≠ `get_line_height()`**。Label 默认 `line_spacing = 3`（见 `card_chip.gd` L79），
##     真实行距 = `get_line_height() + line_spacing` = 26 + 3 = **29**。
##     按 26 去钉会钉出 104（= 3.59 个真实行），照样削半行。
##  ② **Label 高 = 行数 × 行距 − line_spacing**（最后一行后面没有间距）。
##     所以「R 行整好」的视口 = `R × 行距 − line_spacing`，不是 `R × 行距`；
##     多算那 3px 会让滚到底时顶行仍被削掉一点点。
## 按真实行距现算 → 玩家在设置里改「正文字号」后依然成立（写死 26 不行）。
func _snap_text_viewport() -> void:
	if content_margin == null or text_scroll == null or text_box == null:
		return
	content_margin.add_theme_constant_override("margin_top", int(TEXT_MARGIN_TOP))
	content_margin.add_theme_constant_override("margin_bottom", int(TEXT_MARGIN_BOTTOM))
	# 基准视口高要下一帧才结算 → 等一帧再量。
	await get_tree().process_frame
	var sp: float = float(text_box.get_theme_constant("line_spacing", "Label"))
	var pitch: float = maxf(1.0, text_box.get_line_height() + sp)
	var avail: float = text_scroll.size.y
	var rows: float = maxf(1.0, floorf((avail + sp) / pitch))
	var want: float = rows * pitch - sp
	var extra: float = avail - want
	if extra <= 0.5:
		return
	# 只往「更小」的方向收 → 不会形成「改了又被自己改回来」的回环。
	content_margin.add_theme_constant_override("margin_bottom",
			int(TEXT_MARGIN_BOTTOM + roundf(extra)))


## 把对话框正文文字大小设为全局设置的字号（说话人名 name 保持 25 不动）。
func _apply_text_font_size() -> void:
	if text_box != null:
		text_box.add_theme_font_size_override("font_size", Settings.text_font_size)


func _on_text_font_size_changed(_size: int) -> void:
	_apply_text_font_size()
	# 字号变了 → 行高变了 → 视口必须重新钉（否则会重新出现「半行被削」）。
	_snap_text_viewport()
	# 历史条目用同一字号，面板开着时要重建才跟得上。
	if _history_open:
		_render_history()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# 历史浮层打开时：Esc 关掉它，其余按键一律不推进对话（浮层盖着，跳句是静默丢剧情）。
	if _history_open:
		if event is InputEventKey:
			var hkey := event as InputEventKey
			if hkey.pressed and not hkey.echo and hkey.keycode == KEY_ESCAPE:
				_close_history()
				get_viewport().set_input_as_handled()
		return
	# 键盘推进：回车 / 小键盘回车 / 空格 → 下一句（两种布局都生效）。
	# ⚠️ `_input` 早于 GUI 分发，压在本对话之上的模态覆盖层（设置页等）挡不住它。
	# 只有自己还在业务栈顶时才推进 —— 否则按设置页里的键会连带跳掉一整句（静默丢剧情）。
	if event is InputEventKey:
		if OverlayRoot.top() != self:
			return
		if event.pressed and not event.echo \
				and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER \
					or event.keycode == KEY_SPACE):
			display_next_dialogue()
			get_viewport().set_input_as_handled()
			return
	# 报纸模式：点击任意位置推进（普通模式点击走 Panel.gui_input → _on_click）
	if _layout != LayoutMode.NEWSPAPER:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			display_next_dialogue()
			get_viewport().set_input_as_handled()
			return


func _on_click(event: InputEvent) -> void:
	# 普通模式：仅点击 Panel 区域推进（报纸模式由 _input 统一处理）
	if _layout == LayoutMode.NEWSPAPER:
		return
	# 历史浮层盖住对话框时，点它不能被当成「推进对话」（会平白跳过若干句）。
	if _history_open:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		display_next_dialogue()


func on_option_entered(effect, next: int, choice_text: String = "") -> void:
	# 玩家选过的选项也进历史（记在「选项句」之后、下一句之前），回看时看得出走过哪条分支。
	if choice_text != "":
		_history.append({"name": _player_label(), "text": choice_text, "mine": true})
	var blocked := false
	if effect != {}:
		blocked = deal_effect(effect)
	if blocked:
		# 取名弹窗等阻塞型 effect：先别推进，等 confirmed 后再继续
		_pending_next = next
		return
	dialogue_index = next
	display_next_dialogue()


## 对白播完后销毁自身。
## 旧实现只把 visible 置 false，节点会永远挂在树上：每播一段剧情就多一个常驻实例
## （内存泄漏，且它的 _input 仍在抢输入）。接入 OverlayRoot 后更不能留 ——
## 只要它还在模态栈里，输入拦截层就不会撤，地图和 HUD 会彻底点不动。
func _close_self() -> void:
	if not OverlayRoot.close_overlay(self):
		queue_free()


func clear_options() -> void:
	for child in option_box.get_children():
		child.queue_free()


# ============================================================
#  历史记录（会话内，只读回看）
# ============================================================
#  设计口径（2026-10-01 用户拍板）：
#   - 范围：**只保当前这一段剧情**。一个 dialogue_ui 实例 = 一段剧情，
#     show_dialogue_group 清空、实例销毁即消失 → 零存档改动、零跨场景状态。
#   - 语义：**只读回看**。点条目不做任何事 —— 因为 effect（tags/金钱/物品）
#     在进入该句时就已经落地了，回跳只能重播文字、回滚不了数值，
#     会造成「看起来能重来、其实不能」的误导。

## 玩家选项行的名字标签。有真名用真名，否则兜底「你」。
## 排除 player.gd 的初始占位串（`@export var player_name = "请输入你的名字"`）——
## 只有在建角流程被跳过时才会遇到（调试场景），真机上一定有真名。
func _player_label() -> String:
	# ⚠️ hero 来源是 Player.player_name（Autoload 的弱类型 @export），解析器推断不出
	# 链式返回值类型 → 这里必须显式标注，写 `var n := hero.strip_edges()` 会
	# `Cannot infer the type of "n"` 让**整个 dialogue_ui.gd 解析失败**（见 CODE_MAP §8）。
	var n: String = hero.strip_edges()
	if n.is_empty() or n == "请输入你的名字":
		return "你"
	return n


## 记录一句到历史。text 必须是**解析后的完整文本**（与 text_box 打字内容同源），
## 否则回看会看到半截话。旁白（名字为空）照记。
func _record_history(who: String, full_text: String) -> void:
	_history.append({"name": who, "text": full_text, "mine": false})


## 右上角「设置」→ 呼出整屏设置页（保存进度 / 读取存档 / 音量 / 字号 / 返回标题 / 退出）。
## ⚠️ 入栈选项 `esc_closes: false, persist: true` 是**契约**（与 main_ui / loading 同一套）：
##    · esc_closes:false ⇒ 不走 `OverlayRoot.close_top` 的 queue_free 兜底，0.5s 翻页演得完
##      （Esc 由设置页自己接）；少了它，翻页会死在第 0 帧。
##    · persist:true ⇒ 设置页里点「返回主菜单」「读取存档」都会换场景，
##      没有 persist 的话它在 `_on_scene_changed` 那一刻就被清掉，翻页演不完。
func _on_settings_pressed() -> void:
	var scene: PackedScene = load(SETTINGS_MENU_PATH)
	if scene == null:
		push_error("DialogueUI: 找不到设置菜单场景 %s" % SETTINGS_MENU_PATH)
		return
	var menu: Node = scene.instantiate()
	OverlayRoot.push_overlay(menu, {
		"modal": true,
		"esc_closes": false,
		"persist": true,
	})


func _on_history_pressed() -> void:
	if _history_open:
		_close_history()
	else:
		_open_history()


func _open_history() -> void:
	if _history_open or main_dialogue == null:
		return
	# 先把当前句快进完，再开面板。
	# ⚠️ 这一步不能省：打字机在后台跑完会**自动推进游标**（见 display_next_dialogue
	# 的 tween_callback），关掉历史后玩家会莫名跳掉一句。
	_fast_forward_typing()
	_history_open = true
	_render_history()
	if history_panel != null:
		history_panel.visible = true
	_scroll_history_to_bottom()


func _close_history() -> void:
	if not _history_open:
		return
	_history_open = false
	if history_panel != null:
		history_panel.visible = false


## 快进当前句 —— 与「打字中点一下直接出全文」同一语义：
## kill 打字机 → 立刻铺满完整文本 → 非选项句推进游标（选项句不推进，等玩家选）。
func _fast_forward_typing() -> void:
	if typing_tween == null or not typing_tween.is_running():
		return
	typing_tween.kill()
	var dialogue = main_dialogue.dialogue_list[dialogue_index]
	text_box.text = TextVars.resolve(dialogue.content, dialogue.context)
	if dialogue.is_option == false:
		dialogue_index = _resolve_next(dialogue)
	_follow_scroll()


## 重建历史列表。条目量级 = 一段剧情的句数（几十条），每次打开重建的代价可忽略，
## 换来的是「不用维护增量插入 + 滚动位置」。
func _render_history() -> void:
	if history_list == null:
		return
	# queue_free 是延迟的，同一帧 get_children() 仍会返回旧节点 —— 必须先 remove_child。
	for child in history_list.get_children():
		history_list.remove_child(child)
		child.queue_free()
	if history_count != null:
		history_count.text = "共 %d 条" % _history.size()
	# 条目**从顶部往下排**（2026-10-13 用户改口径：「从上到下进行记录」）。
	# 旧做法是在头部塞一个 SIZE_EXPAND_FILL 的 spacer 把内容**顶到底部**（当时按
	# galgame 回想「越往下越新」定的），代价是条目少时上面一整屏空白、两行字挤在
	# 屏幕最下沿挨着 Hint；现在就是普通顶对齐 —— 条目少 → 留白在下方；
	# 条目超一屏 → ScrollContainer 照常滚到最新（见 _scroll_history_to_bottom）。
	for entry in _history:
		history_list.add_child(_make_history_row(entry))


## 单条：`名字列(定宽) + 正文列(autowrap 撑满)`。
## 用 Container 布局（不是手动 offset）→ autowrap Label 的高度由引擎结算，
## 不必踩「换行后真实高度要 2 帧才落定」那个坑。
func _make_history_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var who := Label.new()
	who.text = String(entry.get("name", ""))
	who.custom_minimum_size = Vector2(HISTORY_NAME_W, 0.0)
	# 名字列必须**定宽**（否则长名字会把正文挤到右边、竖排参差不齐）。
	# ⚠️ 光给 custom_minimum_size 不够：autowrap 关着时 Label 的最小宽度由文本宽度决定，
	# 长名会撑破定宽 → 必须开 clip_text 真正裁掉超出的部分。
	who.clip_text = true
	who.add_theme_font_size_override("font_size", Settings.text_font_size)
	who.add_theme_color_override("font_color", HISTORY_NAME_COL)

	var mine: bool = bool(entry.get("mine", false))
	var body := Label.new()
	body.text = ("> " if mine else "") + String(entry.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", Settings.text_font_size)
	if mine:
		body.add_theme_color_override("font_color", HISTORY_MINE_COL)

	row.add_child(who)
	row.add_child(body)
	return row


## 打开时滚到最新一条。
## ⚠️ Container 里新增子节点的尺寸要**下一帧**才结算，当帧读 max_value 会滚不到底
## （与正文自动滚动同源的问题）。偏移上限同样是 `max_value - page`，不是 `max_value`。
func _scroll_history_to_bottom() -> void:
	if history_scroll == null:
		return
	await get_tree().process_frame
	var vs: VScrollBar = history_scroll.get_v_scroll_bar()
	history_scroll.scroll_vertical = int(maxf(vs.max_value - vs.page, 0.0))


## 步骤推进时解析最终 next：
## 若该步配置了 nexts（条件跳转），按顺序取首个命中条件的 next；
## 无条件（缺 condition 或为空）的条目作为默认兜底；无命中则回落到固定 next。
## condition 写法与 option.condition 一致，复用 PlotImporter.sentence_condition（含 child 键）。
## 2026-09-09 总数值口径：传入该节点 context —— 触发器触发的剧情里 attrs 条件
## 按 _investigators 生效属性求和判定（tags = 玩家 ∪ 队伍），普通剧情回退玩家判定。
func _resolve_next(dialogue) -> int:
	var nexts = dialogue.nexts
	if nexts is Array and nexts.size() > 0:
		var dctx: Dictionary = dialogue.context
		for entry in nexts:
			var cond = entry.get("condition", {})
			if cond == {} or PlotImporter.sentence_condition(cond, dctx):
				return int(entry.get("next", -1))
	return int(dialogue.next)


func deal_effect(dialogue_effects) -> bool:
	# 对话系统 effect 处理统一转发 EffectProcessor（三系统共用同一套 effect 契约）。
	# name_child 为阻塞型：通过 on_name_child 回调触发取名弹窗，apply 返回 blocked=true，
	# 调用方（display_next_dialogue / on_option_entered）据此暂存 _pending_next，等弹窗确认后推进。
	if not (dialogue_effects is Dictionary):
		return false
	return EffectProcessor.apply(dialogue_effects, {
		"on_name_child": _open_name_child_popup,
		"on_newspaper": _open_newspaper,
	})


func translate_condition(condition) -> String:
	return condition.description


## ---- 孩子取名弹窗（name_child effect） ----
const NameChildPopup := preload("res://components/name_child_popup.tscn")

## 弹出取名弹窗。孩子 npc 条目已由 EffectProcessor._add_child_npc 在 apply name_child 时创建
## （含 child 标签，名字先填 default），这里只负责弹窗并把确认的名字写回 Player.npc[child_id]["name"]。
func _open_name_child_popup(cfg: Dictionary) -> void:
	var default_name: String = cfg.get("default", "伊莱克")
	var child_id: String = cfg.get("id", "adopted")

	var popup = NameChildPopup.instantiate()
	popup.confirmed.connect(_on_child_named.bind(child_id))
	OverlayRoot.push_overlay(popup, {"modal": true, "esc_closes": false})
	# setup 必须在弹窗入树、_ready 跑完（@onready 节点就绪）之后调用，
	# 否则 _input 仍为 Nil：默认名写不进输入框，确认时 _emit 取不到名字，
	# 导致 name_child 取名彻底失效。
	popup.setup.call_deferred(default_name)


## 玩家在弹窗里确认名字后：写回名字；若由选项触发则继续推进对话。
func _on_child_named(name: String, child_id: String) -> void:
	if name != "" and Player.npc.has(child_id):
		Player.npc[child_id]["name"] = name
	if _pending_next != -1:
		var n := _pending_next
		_pending_next = -1
		dialogue_index = n
		display_next_dialogue()


## ---- 报纸弹窗（newspaper effect） ----
const NewspaperScene := preload("res://components/newspaper.tscn")

## 弹出报纸组件（newspaper effect）。报纸 closed 后继续对话（复用 name_child 的 _pending_next 机制）。
func _open_newspaper(data: Dictionary) -> void:
	var paper := NewspaperScene.instantiate()
	paper.closed.connect(_on_newspaper_closed)
	OverlayRoot.push_overlay(paper, {
		"modal": true,
		"esc_closes": true,
		"close_method": "close",
		"persist": true,
	})
	paper.show_newspaper(data)


## 报纸关闭 → 继续推进对话。kill 打字机 tween，避免与「打字完成自动推进」竞态跳步。
func _on_newspaper_closed() -> void:
	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
	if _pending_next != -1:
		var n := _pending_next
		_pending_next = -1
		dialogue_index = n
		display_next_dialogue()
