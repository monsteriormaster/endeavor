## 触发器交互点 —— 地图/场景中可点击的区域按钮。
## 点击打开 TriggerPopup 弹窗（悬浮提示 hint 已于 2026-09-25 移除，触发点不再有任何悬浮文案）。
## 使用：在编辑器中拖入场景，设置 trigger_id 即可。
class_name TriggerSpot
extends Button

## 触发点由 TriggerManager.popup_scene_for 统一按 resolver 选场景，这里不再硬编码 POPUP_SCENE。

## 点击后打开的触发器 ID
@export var trigger_id: String = ""

## 2026-09-25：悬浮 hint **已彻底移除**（原 `hover_hint` 导出属性 + TooltipPanel + 鼠标进出回调一并删除）。
## 触发点不再有悬浮提示；场景里的 hover_hint 数据也已清空。

# ============================================================
#  徽章视觉（2026-10-08 实装：菱形小徽章 + 类别符号 + 状态角标）
#
#  四态：未开始 / 持续中 / 结算 / 已消耗。**类别与状态是两条独立通道**：
#    · 中心 = 类别符号（trigger.json 顶层 "badge"，15 枚之一），**四态完全不变**；
#    · 状态 = 菱形右上**外侧**一枚小圆章（空心圆 / 沙漏 / 感叹号 / 叉）；
#    · 底图本身也给第二重提示：赭黄 → 退灰 → 金底金环 → 褪色 + 斜划。
#  为什么拆两条：中心只有一个位置 —— 放了类别符号，状态就没地方表达。
#
#  素材 112x112（菱形 56 居中，四周留白给金环与角标），三层同尺寸同位置叠放：
#      底(Base) → 符号(Symbol) → 角标(Mark)
#  「持续中」的符号减淡、「已消耗」的整体褪色一律走 modulate，不另烤图
#  ⇒ 将来加类别只加一张符号图，不用动底。
#
#  规格 design/触发器图标_分类方案_v1.md
#  生成脚本 design/_tools/make_trigger_badge_assets.py（几何 / 亮度判据都在里面跑）
# ============================================================
const BADGE_DIR := "res://art/ui/"
## 底图：四态各一张（状态差的不只是颜色，金环与斜划各画各的）
const BASE_FILES := {
	"idle": "trig_badge_idle.png",
	"busy": "trig_badge_busy.png",
	"ready": "trig_badge_ready.png",
	"consumed": "trig_badge_consumed.png",
}
## 状态角标：四态各一张
const MARK_FILES := {
	"idle": "trig_badge_mark_empty.png",
	"busy": "trig_badge_mark_wait.png",
	"ready": "trig_badge_mark_ready.png",
	"consumed": "trig_badge_mark_done.png",
}
## 15 枚类别符号（键 = trigger.json 的 "badge" 值 = 文件名里的中文）
const SYM_FILES := {
	"营生": "trig_badge_sym_营生.png",
	"采买": "trig_badge_sym_采买.png",
	"研读": "trig_badge_sym_研读.png",
	"探问": "trig_badge_sym_探问.png",
	"交游": "trig_badge_sym_交游.png",
	"医养": "trig_badge_sym_医养.png",
	"观演": "trig_badge_sym_观演.png",
	"回家": "trig_badge_sym_回家.png",
	"越狱": "trig_badge_sym_越狱.png",
	"出航": "trig_badge_sym_出航.png",
	"夜探": "trig_badge_sym_夜探.png",
	"裁决": "trig_badge_sym_裁决.png",
	"托付": "trig_badge_sym_托付.png",
	"掘取": "trig_badge_sym_掘取.png",
	"窃取": "trig_badge_sym_窃取.png",
}
## 触发器没写 badge / 写了未知值时的回落（「探问」是覆盖面最广的一类）
const DEFAULT_BADGE := "探问"
## 「持续中」时类别符号的减淡系数（不另烤一张减淡的符号图）
const BUSY_SYMBOL_ALPHA := 0.5
## 「已消耗」整枚徽章的褪色系数（斜划已烤在底图里）
const CONSUMED_ALPHA := 0.38
## 悬浮时整枚徽章放大 —— 与 scene_spot 的 HOVER_SCALE 同一档口径（「感觉得到但说不出」）
const HOVER_SCALE := 1.06
const HOVER_TWEEN := 0.14
## 标签墨色（同 scene_spot：写在纸上的墨，**绝不用纯黑**）
const NAME_COLOR := Color(0.220, 0.161, 0.118, 1.0)
## 名字字号（2026-10-25：18 → 22）。
## 18px 的 Light 中文在这个距离上读起来是「一排灰点」——玩家要凑近才敢确认点的是哪。
## 22px 与徽章（可见菱形 56px）配起来更顺，也在 1920 宽的地图上「一眼扫得完」。
const NAME_FONT_SIZE := 22
const STATUS_COLOR := Color(0.361, 0.271, 0.204, 1.0)
## 状态字号（等待N回合）。14 → 15：它和名字同屏出现，小一档是层级，不是看不清。
const STATUS_FONT_SIZE := 15
## 地图墨字字体：全局字族（Resource Han Rounded）就地加粗 0.8px。
## 见 `theme/font_map_ink.tres` 的文件头 —— 不换字族、不动全局主题，字形宽度零变化。
const MAP_FONT_PATH := "res://theme/font_map_ink.tres"
## 2026-10-21：二级地图换成更满、更暗的插画之后（剧院雨棚、监狱石墙），
## 名字直接压在画上对比不够。给一圈**纸色**描边 —— 不是白描边，是「纸的颜色」，
## 与徽章新加的奶油外圈同一条思路：深色底靠浅圈托，浅色底靠墨色立。
const NAME_OUTLINE_COLOR := Color(0.961, 0.945, 0.898, 1.0)
## 描边宽度（2026-10-25：4 → 3）。4px 在**浅色纸底**上是纯粹的负担：
## 描边色（纸色）比纸底还亮，它不「托」字，只是从四周把 1px 的细笔画啃掉一圈，
## 于是浅底上的标签反而比无描边的更虚（A/B 对比 `debug/_map_text_ab_zoom_0.png` A vs B）。
## 3px 配 0.8 的加粗，既保住了暗底（剧院雨棚/石墙）那一边，也不再把浅底的字磨毛。
const NAME_OUTLINE_SIZE := 3
const STATUS_OUTLINE_SIZE := 3

## ── 深底档（2026-10-25）──
## 「墨字 + 纸色描边」在浅纸底上最优，但压在**深色插画**上会反过来：
## 深墨字与深底对比不足，只剩一圈亮描边在"发亮"，读起来是一团糊。
##
## 实测（`debug/_map_text_maps.gd` 把标签藏起来截空底、按标签矩形采平均亮度）：
##   主城 / 家 / 商业街 / 学校 / 医院 / 孤儿院 / 监狱 = **0.48~0.85**（浅底，墨字最优）
##   剧院柱廊「夜间调查剧院」= **0.38**、「与经理交涉」= 0.48（深底，墨字不够）
## 全工程 33 个标签里只有这两个真的需要反过来。
##
## ⚠️ 不做「运行时采样底图自动反色」：同一张地图上的标签一会儿黑一会儿白，比糊更难看；
##    而且它坏了没人能发现（没有报错，只有玩家看错）。改为**逐点显式声明**：
##    哪个点压在深色上，就在那个实例里写 `label_on_dark = true`。
const DARK_NAME_COLOR := Color(0.961, 0.945, 0.898, 1.0)
const DARK_STATUS_COLOR := Color(0.878, 0.855, 0.804, 1.0)
const DARK_OUTLINE_COLOR := Color(0.220, 0.161, 0.118, 1.0)

## 按钮上方的标签（可选）
@export var label_text: String = ""

## 这个点的名字压在深色插画上 → 名字/状态改用「纸色字 + 墨色描边」。
## 只给实测亮度低于 0.45 的点打开（见上面深底档的注释），默认 false。
@export var label_on_dark := false

## 弹窗成功打开后发出（参数：新建的弹窗实例），便于上层连接 cards_returned 等。
signal popup_opened(popup: TriggerPopup)

## 亲历鉴定（D-C1/D-C2）：主角专属触发器是否已消耗（非重复 → 永久禁用）。
## 普通触发器走 _on_flow_completed 同样置位，供 dialogue_finished 统一判断是否恢复。
var _consumed := false

## 非重复异步触发器：执行时已提交行动（ActionQueue），先不 consume；
## 待结算完成（行动从队列移除）再禁用，否则触发点会被永久变灰、无法点击原触发点结算。
var _async_submitted := false

## 对话占用标记（protagonist 触发器播放中 → 禁用，但不改灰/文案；结束由 EventSignal.dialogue_finished 复位）。
var _dialogue_active := false

## 四态样式盒缓存（旧实现）→ 2026-10-08 起改为徽章贴图，见文件头。
## 贴图缓存做成可漏的静态字典：23 张图，30 个触发点共享同一份，不必各持一份。
static var _tex_cache: Dictionary = {}

## 悬浮缩放补间（换态 / 禁用时要能打断）
var _hover_tween: Tween = null

@onready var _badge: Control = $Badge
@onready var _tex_base: TextureRect = $Badge/Base
@onready var _tex_sym: TextureRect = $Badge/Symbol
@onready var _tex_mark: TextureRect = $Badge/Mark
@onready var _name_label: Label = $NameLabel
@onready var _status_label: Label = $StatusLabel


func _ready() -> void:
	custom_minimum_size = Vector2(80, 80)
	_apply_default_style()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	if not label_text.is_empty():
		_name_label.text = label_text
		_name_label.visible = true
	# F6 反重入：对话结束后恢复可重复触发器（已消耗的非重复触发器保持禁用）。
	EventSignal.dialogue_finished.connect(_on_dialogue_finished)
	EventSignal.day_changed.connect(_on_day_changed)
	# 2026-10-16（家业主线）：任一触发器结算后，全局重算本点显隐。
	# 背景：popup.flow_completed 是**直连本实例**的信号（见 _on_pressed 里的 connect），
	# A 点结算授了 tag，同场景里被该 tag 门控的 B 点收不到 —— 玩家在「群死凶器」拿到
	# 「一个名字的印象」后，「调查丹尼斯」要过天/重进场景才长出来。挂总线一层，
	# 所有场景（家 / 商业街 / 主城）的所有 spot 都受益；_refresh_visibility 幂等，无副作用。
	if not EventSignal.trigger_flow_completed.is_connected(_on_global_flow_completed):
		EventSignal.trigger_flow_completed.connect(_on_global_flow_completed)
	# 异步行动队列变化 → 结算完成后补上延迟的 consume（见 _on_flow_completed）。
	if not ActionQueue.actions_changed.is_connected(_on_actions_changed):
		ActionQueue.actions_changed.connect(_on_actions_changed)
	# D-显隐：触发器按 trigger.json 的 show_when 条件显隐（进入场景时首次刷新）。
	_refresh_visibility()
	# D-按钮特效：按 ActionQueue 现有行动恢复四态（换场景重建时状态不丢）。
	_refresh_state()


## 默认视觉。按钮本体**不再自绘任何东西**：
##   ① 五个状态样式盒（normal/hover/pressed/disabled/focus）一律清成 StyleBoxEmpty
##      —— 旧实现是四个 StyleBoxFlat，那正是「原始感」的来源；
##      ⚠️ `focus` 也必须清：Button 获得焦点时会在 normal 之上**再画一层** focus 框。
##   ② 文字清空 —— 视觉改由 Badge 那三层 TextureRect 承担。
##   ③ 名字 / 状态两个 Label 的墨色与字号在这里统一给（override 而非改全局主题）。
func _apply_default_style() -> void:
	var empty := StyleBoxEmpty.new()
	for slot in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		add_theme_stylebox_override(slot, empty)
	text = ""
	# 工程全局 default_texture_filter = NEAREST。徽章是 1:1 贴图（112 画 112），
	# 平时看不出差别，但悬浮会放大到 1.06 —— 那一下点采样会把铅笔细描边啃成台阶。
	for tr in [_tex_base, _tex_sym, _tex_mark]:
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 深底档：整个反过来（纸色字 + 墨色描边）。只有实测亮度低于 0.45 的点会打开它，
	# 见 DARK_NAME_COLOR 那一段的采样数据。
	var name_col := DARK_NAME_COLOR if label_on_dark else NAME_COLOR
	var status_col := DARK_STATUS_COLOR if label_on_dark else STATUS_COLOR
	var outline_col := DARK_OUTLINE_COLOR if label_on_dark else NAME_OUTLINE_COLOR
	_name_label.add_theme_color_override(&"font_color", name_col)
	_name_label.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	_status_label.add_theme_color_override(&"font_color", status_col)
	_status_label.add_theme_font_size_override(&"font_size", STATUS_FONT_SIZE)
	# 字形要「实」才读得清（见 theme/font_map_ink.tres 的文件头）：
	# 全局 Light 在 18~22px 的中文上笔画断成一串灰点，加粗 0.8px 就变回墨。
	var map_font: Font = load(MAP_FONT_PATH)
	if map_font != null:
		_name_label.add_theme_font_override(&"font", map_font)
		_status_label.add_theme_font_override(&"font", map_font)
	# 描边：浅底用纸色托、深底用墨色收。
	# ⚠️ Label 的描边是**外扩**的，会吃掉一点边距 —— 这圈只在 4px 以下，不影响布局。
	# ⚠️ 别调成纯白 (1,1,1)：纯白在浅色天空上反过来把字咬毛，纸色与整个 UI 同族。
	for lbl in [_name_label, _status_label]:
		lbl.add_theme_color_override(&"font_outline_color", outline_col)
	_name_label.add_theme_constant_override(&"outline_size", NAME_OUTLINE_SIZE)
	_status_label.add_theme_constant_override(&"outline_size", STATUS_OUTLINE_SIZE)
	_tex_sym.texture = _badge_tex(_sym_file())


## 贴图加载 + 缓存。走 load() 而不是 preload：23 张图不必在脚本编译期全部驻留，
## 且缺图（素材没拷进来 / 没导入）时能给出**可读的**报错，而不是静默空白。
static func _badge_tex(file_name: String) -> Texture2D:
	if not _tex_cache.has(file_name):
		var path := BADGE_DIR + file_name
		var t: Texture2D = load(path)
		if t == null:
			push_error("TriggerSpot: 徽章素材缺失或未导入 → %s" % path)
		_tex_cache[file_name] = t
	return _tex_cache[file_name]


## 本触发器的类别符号文件名（trigger.json 顶层 "badge"）。
## 缺字段 / 写了 15 枚之外的值 → 回落 DEFAULT_BADGE，不崩、不留空。
func _sym_file() -> String:
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	var b := String(raw.get("badge", ""))
	if not SYM_FILES.has(b):
		b = DEFAULT_BADGE
	return SYM_FILES[b]


## 换态**唯一入口**（旧 `_set_visual` 的继任者）。
## 四态 = 底图 + 角标 + 两条 modulate，别的什么都不动。
func _apply_state(state: String, status_text: String = "") -> void:
	_tex_base.texture = _badge_tex(BASE_FILES[state])
	_tex_mark.texture = _badge_tex(MARK_FILES[state])
	# 类别符号四态不变，只有「持续中」减淡
	_tex_sym.modulate.a = BUSY_SYMBOL_ALPHA if state == "busy" else 1.0
	# 「已消耗」整枚褪色（斜划已烤在底里，不要再画一遍）
	_badge.modulate.a = CONSUMED_ALPHA if state == "consumed" else 1.0
	_status_label.text = status_text
	_status_label.visible = not status_text.is_empty()


## 刷新徽章四态。优先级：已消耗 > 持续中 > 结算 > 未开始。
##  - 已消耗（`_consumed`）：褪到 38% + 斜划 + 角标叉，禁用；
##  - 持续中（独占触发器有未完成行动）：退灰 + 沙漏，名字下方写「等待N回合」，禁用；
##  - 结算（行动倒计时归零、可点）：金底金环 + 感叹号，可点（点击 = 结算）；
##  - 未开始：赭黄底 + 空心圆；仅对话占用时禁用，不改外观。
## ⚠️ 顺序即优先级，别把 `disabled` 的赋值挪到分支外面去。
func _refresh_state() -> void:
	if _name_label == null:
		return  # _apply_default_style 之前的安全兜底
	var state := "idle"
	var status := ""
	if _consumed:
		state = "consumed"
	elif not trigger_id.is_empty() and TriggerLoader.is_exclusive(trigger_id):
		if not ActionQueue.get_completed_by_trigger(trigger_id).is_empty():
			state = "ready"
		else:
			var pending: Dictionary = ActionQueue.get_pending_by_trigger(trigger_id)
			if not pending.is_empty():
				state = "busy"
				status = "等待%d回合" % int(pending.get("wait", 0))
	_apply_state(state, status)
	match state:
		"idle":
			disabled = _dialogue_active
		"ready":
			disabled = false
		_:
			disabled = true
	# 禁用态下 `mouse_exited` 不一定送达（鼠标本来就停在上面），
	# 不主动复位的话徽章会一直挂在放大 1.06 上。
	if disabled:
		_reset_hover()


## 悬浮：整枚徽章轻轻放大（与 scene_spot 同一条通道，同一档量级）。
func _on_mouse_entered() -> void:
	if disabled:
		return
	_tween_badge_scale(HOVER_SCALE)


func _on_mouse_exited() -> void:
	_tween_badge_scale(1.0)


func _tween_badge_scale(to_scale: float) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	if is_equal_approx(_badge.scale.x, to_scale):
		return
	_hover_tween = create_tween()
	# SINE/EASE_OUT：这是「位移类」缓动（缩放同族），不用 8fps 阶梯 ——
	# 按拍跳是给「重画线稿」的呼吸 / 抖动用的，不是给鼠标响应用的。
	_hover_tween.tween_property(_badge, "scale", Vector2(to_scale, to_scale), HOVER_TWEEN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _reset_hover() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	_badge.scale = Vector2.ONE


func _on_pressed() -> void:
	if trigger_id.is_empty():
		push_warning("TriggerSpot: trigger_id 为空，无法打开触发器弹窗")
		return

	# 亲历鉴定（D-C1/D-C2）：主角专属 → 跳过拖卡弹窗，自动主角入槽 + 直接结算入剧情。
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	# 首次进店剧情（D-首次进店）：触发器带 gate_tag + entry_plot，玩家尚未持有 gate_tag 时，
	# 直接播放 entry_plot 剧情（剧情 effect 授予 gate_tag），不开触发器窗。
	if _try_first_visit_plot(raw):
		return
	if not raw.is_empty() and bool(raw.get("protagonist_only", false)):
		# F6 反重入：已消耗，或正处于另一段对话播放中 → 拒绝。
		if _consumed or Player.is_dialogue_exist:
			return
		# open_protagonist_trigger 内部负责 consume()/mark_dialogue_active（失败则不改状态）。
		TriggerManager.open_protagonist_trigger(trigger_id, self)
		return

	# 已完成（待结算）的异步行动：点击原触发点直接结算，与 ActionPanel「结算」按钮同语义。
	# 必须放在 exclusive 拦截之前：has_active 连「已完成」也算，否则会被误挡成「进行中」。
	var done: Dictionary = ActionQueue.get_completed_by_trigger(trigger_id)
	if not done.is_empty():
		ActionQueue.settle(String(done.get("id", "")))
		return

	# 普通触发器：原有拖卡弹窗流程
	# 全局单弹窗：任意触发器弹窗打开中 → 阻止再开（防连点同点出多弹窗 + 不同触发器同屏冲突）
	if _has_existing_popup():
		return

	# E-独占（默认 true）：该触发器有进行中 / 待结算的异步行动时禁用打开
	# （如酒馆打工持续1回合：执行→冻结→提交，下一天才结算，期间不可再开）。
	# exclusive=false 的触发器跳过此限制（允许进行中重开）。
	if TriggerLoader.is_exclusive(trigger_id) and ActionQueue.has_active(trigger_id):
		push_warning("TriggerSpot: %s 有进行中行动，禁用打开（exclusive）" % trigger_id)
		return

	# D-DOC14（打听）：按 resolver 选场景（inquiry → 继承子类弹窗）。
	var popup := TriggerManager.popup_scene_for(trigger_id).instantiate() as TriggerPopup
	if popup == null:
		push_error("TriggerSpot: 无法实例化 TriggerPopup")
		return

	# 全流程结束后回调：非重复触发器消耗自身（禁用按钮）
	popup.flow_completed.connect(_on_flow_completed)

	# 统一交给覆盖层管理器（D-UI6）：负责挂载层级、模态输入拦截、Esc 只关最上层、
	# 以及场景切换时的自动清理。此处是按钮回调（不在 _ready 阶段），可同步 push。
	OverlayRoot.push_overlay(popup, {
		# 非模态：触发器弹窗需从卡牌区拖卡入卡槽，故不可插全屏输入拦截层
		# （否则 ModalBlocker 会吞掉卡牌区的鼠标事件，卡无法拖拽）。
		"modal": false,
		"esc_closes": true,
		"close_method": "close",
	})

	var ok: bool = popup.setup(trigger_id)
	if not ok:
		if not OverlayRoot.close_overlay(popup):
			popup.queue_free()
		push_warning("TriggerSpot: 触发器 %s 加载失败" % trigger_id)
		return

	# D-HAND2：卡牌归还的唯一入口在弹窗自己那侧（`TriggerPopup._return_to_hand`），
	# 这里不再接 cards_returned —— 绑死在当前视图上的连接，切个场景就变成对着僵尸发信号，
	# 玩家那张卡会静默消失。购得的书卡走 TriggerManager.deliver_card（同样每次现问视图）。
	popup.book_acquired.connect(TriggerManager.deliver_card)

	popup_opened.emit(popup)
	EventSignal.trigger_opened.emit(trigger_id)


## 首次进店剧情：触发器带 gate_tag + entry_plot，且玩家尚未持有 gate_tag 时，
## 直接播放 entry_plot 剧情（剧情 effect 授予 gate_tag），返回 true 表示已处理（不开触发器窗）。
## 后续点击因已持有 gate_tag，走正常触发器流程。重入保护由 PlotImporter.add_plot 内部完成。
func _try_first_visit_plot(raw: Dictionary) -> bool:
	var gate_tag: String = String(raw.get("gate_tag", ""))
	if gate_tag == "":
		return false
	var entry_plot: Variant = raw.get("entry_plot", null)
	if not (entry_plot is Dictionary):
		return false
	if Player.player_has_tags([gate_tag], 1):
		return false
	var ep: Dictionary = entry_plot
	var pp := String(ep.get("path", ""))
	var pn := String(ep.get("name", ""))
	if pp == "" or pn == "":
		push_warning("TriggerSpot: %s 的 entry_plot 缺 path/name，退回正常触发器流程" % trigger_id)
		return false
	PlotImporter.add_plot(pp, pn)
	return true


## 防止同一触发器重复打开。弹窗现在由 OverlayRoot 托管，不再挂在 tree.root 下，
## 因此改为向覆盖层管理器查询（旧写法遍历 root 的子节点，改造后会永远查不到 → 可重复打开）。
func _has_existing_popup() -> bool:
	for overlay in OverlayRoot.get_overlays():
		if overlay is TriggerPopup:
			return true
	return false


## 全局总线版「流程完成」：只为重算显隐（本 spot 的 consume 走实例直连的 _on_flow_completed）。
func _on_global_flow_completed(_trigger_id: String, _success: bool) -> void:
	_refresh_visibility()

## 全流程结束回调：非重复触发器 → 自身消耗（禁用按钮）。success 透传真实结局（非 fail_harvest）。
## D-夜探（2026-09-08）：触发器可配 consume_when_tags —— 即使 repeatable=true，只要结束时玩家已持有
## 所列 tag（method=all）也照常消耗。用于「失败可重试、成功即关闭」的夜间调查等场景。
func _on_flow_completed(_trigger_id: String, repeatable: bool, success: bool) -> void:
	EventSignal.trigger_flow_completed.emit(_trigger_id, success)
	var will_consume := _will_auto_consume()
	if not will_consume:
		return
	# 异步流程：执行即提交行动（_commit_action 先 enqueue 再发本信号）。此时若立刻 consume 会把
	# 触发点永久变灰、无法点击原触发点结算。改为延迟 consume：行动结算移除后才禁用
	# （见 _on_actions_changed）。
	if ActionQueue.has_active(_trigger_id):
		_async_submitted = true
		return
	if _auto_consume_ready():
		consume()


## 结算/提交后是否需要（潜在）自动消耗：
## 非重复触发器恒需；可重复触发器需已配置 consume_when_tags（是否真的消耗看 tag 落地情况）。
func _will_auto_consume() -> bool:
	if not TriggerLoader.is_repeatable(trigger_id):
		return true
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	var ctags: Array = raw.get("consume_when_tags", [])
	return not ctags.is_empty()


## 现在是否满足「自动消耗」条件：非重复 → 是；可重复 → 玩家已持有全部 consume_when_tags。
func _auto_consume_ready() -> bool:
	if not TriggerLoader.is_repeatable(trigger_id):
		return true
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	var ctags: Array = raw.get("consume_when_tags", [])
	if ctags.is_empty():
		return false
	return Player.player_has_tags(ctags, 1)


## 非重复异步触发器：执行时先不 consume，等结算完成（行动从队列移除）再禁用。
## D-按钮特效：任何队列变化都先刷新四态（执行中→灰、待结算→金、结算后→回空闲/已消耗）。
func _on_actions_changed() -> void:
	_refresh_state()
	if trigger_id.is_empty() or _consumed or not _async_submitted:
		return
	if ActionQueue.has_active(trigger_id):
		return
	_async_submitted = false
	if _auto_consume_ready():
		consume()


## 亲历鉴定 / 普通触发器 通用：标记本 spot 已「消耗」（非重复触发器结算后永久禁用）。
func consume() -> void:
	_consumed = true
	_refresh_state()


## 亲历鉴定（可重复）：标记对话播放中（禁用，待 dialogue_finished 恢复）。
func mark_dialogue_active() -> void:
	_dialogue_active = true
	_refresh_state()


## F6 反重入：一段对话结束 → 恢复仍可重复 / 未消耗的 spot（已消耗的非重复 spot 保持禁用）。
func _on_dialogue_finished() -> void:
	_dialogue_active = false
	_refresh_visibility()
	_refresh_state()


## D-显隐：触发器按 trigger.json 的 show_when 条件显隐。
## 支持 tags（+ method），为空表示恒显。
## D-按钮特效：过天同时刷新「执行中：等待N回合」倒计时文案（ActionQueue 先于本处收到 day_changed）。
func _on_day_changed(_day: int) -> void:
	_refresh_visibility()
	_refresh_state()


## D-DOC20（2026-09-09）：show_when 可选 `unless_tags`（数组）——玩家持有**任一**所列 tag
## 即强制隐藏（优先于 tags 正向判定）。用途：「触发条件已达成/前置已满足 → 本触发器提前结束」，
## 首例：阿尔温的未来（已持有 获得了阿尔温 → 不再需要安置剧情，触发点直接消失）。
##
## 2026-10-15（孩子线二轮「这几天」）：show_when 再补两种判据，都只在此处落地、不复制第二份：
##   · `num_tags`  —— 可堆叠词条区间，写法同 trigger_loader._conditions_ok 的同名键
##                    {"学校学习": {"min": 1}}。用途：「至少送过一次学」这种**计数**门槛，
##                    tags 只认有无，表达不了次数。
##   · `chance`    —— 按天确定性概率 + 隔天保底，写法 {"key": "唯一名", "p": 0.6, "carry": true}。
##                    可见 = 今天掷中 或（carry 时）昨天没掷中 → 即「第 x 天没出现则第 x+1 天必现」。
##                    掷骰走 Player.make_rng/make_rng_for_day（种子含 campaign_seed + 天数）：
##                    同局同天结果恒定，读档、重进场景、反复 _refresh 都不会翻脸，也不需要存档状态。
##
## 判定顺序 = 逐条**短路**（任一条不过即隐藏），与既有 tags/unless_tags 的无条件恒显共存：
## show_when 为空 = 恒显；写了哪几条就判哪几条。
func _refresh_visibility() -> void:
	var raw: Dictionary = TriggerLoader.get_trigger(trigger_id)
	if raw.is_empty():
		return
	visible = show_when_visible(raw, trigger_id)


## 触发器显隐的对外入口（2026-10-15 孩子线三事件起独立成 static，判定函数一并去实例化，
## 好让 TriggerManager 的组仲裁复用同一份 candidate 判定，不留第二套口径）。
## 先判自身资格（show_when_candidate_ok），再判随机事件组仲裁（同 group 每回合只一个）。
static func show_when_visible(raw: Dictionary, tid: String) -> bool:
	if not show_when_candidate_ok(raw):
		return false
	var sw: Dictionary = raw.get("show_when", {})
	var group := String(sw.get("group", ""))
	if group != "" and TriggerManager.resolve_random_group(group) != tid:
		return false
	return true


## 触发器的**自身**资格判定 —— 逐条短路
## unless → tags → num_tags → npc_tags → npc_num_tags → child_tags → chance。
## show_when 为空 = 恒显；写了哪几条就判哪几条。
## ⚠️ **不含 group 仲裁**：组仲裁（show_when_visible → resolve_random_group）要调它，
## 反过来再判 group 就是无限递归。
static func show_when_candidate_ok(raw: Dictionary) -> bool:
	var show_when: Dictionary = raw.get("show_when", {})
	if show_when.is_empty():
		return true
	var unless: Array = show_when.get("unless_tags", [])
	if not unless.is_empty() and Player.player_has_tags(unless, 2):
		return false
	var tags: Array = show_when.get("tags", [])
	if not tags.is_empty():
		# method 缺省 1（全持有）；tags 为空视为「无此条约束」而不是「恒显」——
		# 因为 num_tags / child_tags / chance 可能单独存在。
		var method: int = int(show_when.get("method", 1))
		if not Player.player_has_tags(tags, method):
			return false
	if not _show_when_num_tags_ok(show_when.get("num_tags", null)):
		return false
	if not _show_when_npc_tags_ok(show_when.get("npc_tags", null)):
		return false
	if not _show_when_npc_num_tags_ok(show_when.get("npc_num_tags", null)):
		return false
	if not _show_when_child_tags_ok(show_when.get("child_tags", null)):
		return false
	if not _show_when_chance_ok(show_when.get("chance", null), raw):
		return false
	return true


## show_when.child_tags：按「唯一孩子」（首个带 child 标签的 npc）的**普通**词条判定，须全部持有。
## 用途：剧情按孩子**天赋档**二选一（gifted / common）—— 孩子会被取名窗改名，名字不可靠，
## 天赋 tag 才是稳定标识。空数组 / 非数组 → 放行（无此条约束）；非空但当前没有孩子 → 判否
## （避免 gifted 事件落到「还没收养」的状态上）。
static func _show_when_child_tags_ok(spec: Variant) -> bool:
	if not (spec is Array):
		return true
	var arr: Array = spec
	if arr.is_empty():
		return true
	var ck := PlotImporter.child_key_of()
	if ck == "":
		return false
	return Player.npc_has_tags(ck, arr, 1)


## show_when.num_tags：玩家可堆叠词条的闭区间判定（写法与 trigger_loader 的 num_tags 一致）。
## 非字典 / 缺字段 → 视为「无此条约束」，放行。
static func _show_when_num_tags_ok(spec: Variant) -> bool:
	if not (spec is Dictionary):
		return true
	for tn in (spec as Dictionary):
		var s: Variant = (spec as Dictionary)[tn]
		if not (s is Dictionary):
			continue
		var b: Array = _num_bounds(s as Dictionary)
		var val := int(Player.player_num_tags.get(String(tn), 0))
		if val < int(b[0]) or val > int(b[1]):
			return false
	return true


## show_when.npc_tags（2026-10-24）：指定 NPC 的**普通**词条判定，须全部持有。
## 写法 `{"Louise": ["还在练习"]}`；键可写 npc 条目键（Louise）或中文名（露易丝），
## 特例 `"child"` = 唯一孩子。
## ⚠️ NPC 键查不到 → 判否 + warning（键写错要吵，不能当无约束放行）。
static func _show_when_npc_tags_ok(spec: Variant) -> bool:
	if not (spec is Dictionary):
		return true
	for k in (spec as Dictionary):
		var v: Variant = (spec as Dictionary)[k]
		if not (v is Array):
			continue
		var tags: Array = v
		if tags.is_empty():
			continue  # 空数组 = 无此条约束
		var key := _show_when_npc_key(String(k))
		if key == "":
			# "child" 查不到 = 还没收养，属正常状态（同 child_tags 的语义），不吵。
			if String(k) != "child":
				push_warning("TriggerSpot: show_when.npc_tags 的 NPC 键 '%s' 在 Player.npc 里查不到 —— 该触发器判否（检查是不是写了中文名、条目却还没建出来）" % String(k))
			return false
		if not Player.npc_has_tags(key, tags, 1):
			return false
	return true


## show_when.npc_num_tags（2026-10-24 露易丝线）：指定 NPC 的**可堆叠数值**词条闭区间判定。
## 这是以前缺的那条 —— show_when 原本只能读玩家，读不到别人身上的数值（好感、次数之类）。
##
## 写法（键同 npc_tags，可写条目键 / 中文名 / "child"）：
##   "npc_num_tags": { "Louise": { "love": {"min": 3} } },
##   "npc_num_tags": { "露易丝": { "love": {"min": 1, "max": 2} } }
## 区间写法 `{min,max}`（触发器口径），也认 `{left,right}`（剧情 condition 口径）。
## ⚠️ NPC 键查不到 → 判否 + warning；数值词条不存在按 0 算。
static func _show_when_npc_num_tags_ok(spec: Variant) -> bool:
	if not (spec is Dictionary):
		return true
	for k in (spec as Dictionary):
		var body: Variant = (spec as Dictionary)[k]
		if not (body is Dictionary):
			continue
		var key := _show_when_npc_key(String(k))
		if key == "":
			if String(k) != "child":
				push_warning("TriggerSpot: show_when.npc_num_tags 的 NPC 键 '%s' 在 Player.npc 里查不到 —— 该触发器判否（NPC 条目要先由 effect.npc 建出来，中文名才会反查得到）" % String(k))
			return false
		for tn in (body as Dictionary):
			var s: Variant = (body as Dictionary)[tn]
			if not (s is Dictionary):
				continue
			var b: Array = _num_bounds(s as Dictionary)
			var val := Player.npc_num_tag_value(key, String(tn))
			if val < int(b[0]) or val > int(b[1]):
				return false
	return true


## NPC 键解析（show_when.npc_tags / npc_num_tags 共用）：
## 特例 `"child"` = 唯一孩子（走 PlotImporter.child_key_of）；
## 其余走 Player.resolve_npc_key（条目键精确命中 → 中文名反查）。查不到 → ""。
static func _show_when_npc_key(k: String) -> String:
	if k == "child":
		return PlotImporter.child_key_of()
	return Player.resolve_npc_key(k)


## 数值词条区间解析：`{min,max}` 优先，退回 `{left,right}`（剧情 condition 的老写法）。
## 都没写 → 全开区间（等于只判「有没有这条约束」以外的任何值都过）。
static func _num_bounds(spec: Dictionary) -> Array:
	var lo := -2147483648
	var hi := 2147483647
	if spec.has("min"):
		lo = int(spec["min"])
	elif spec.has("left"):
		lo = int(spec["left"])
	if spec.has("max"):
		hi = int(spec["max"])
	elif spec.has("right"):
		hi = int(spec["right"])
	return [lo, hi]


## show_when.chance：按天确定性概率 +（可选）隔天保底。
##   carry 缺省 true  → 今天没中、昨天也没中 ⇒ 今天必现（「隔天必触发」）
##   carry = false    → 纯每日独立概率（可能出现连续多天不露面）
## fetch 的 key 缺省用触发器自身的 id（raw["id"]）—— 同一触发器只 roll 一路，不会与别的触发器串号；
## 不同触发器务必给不同 key，否则会共享同一掷骰、同进同出。
static func _show_when_chance_ok(spec: Variant, raw: Dictionary) -> bool:
	if not (spec is Dictionary):
		return true
	var sp: Dictionary = spec
	var key := String(sp.get("key", raw.get("id", "")))
	var p := float(sp.get("p", 0.5))
	if Player.make_rng("show:" + key).randf() < p:
		return true
	if not bool(sp.get("carry", true)):
		return false
	# 隔天保底：查昨天那一掷 —— 昨天没中，今天就必须给出来。
	return Player.make_rng_for_day("show:" + key, Player.time - 1).randf() >= p
