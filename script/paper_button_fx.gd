extends Node2D
## 纸按钮动效 —— 悬浮画一圈铅笔 / 按下下沉。挂在 **Button 之下当子节点**。
##
## ▍为什么是「子节点」而不是挂在 Button 上的脚本（这是实装时的关键取舍）：
##   全局挂载器 `ButtonSkin` 要给「全工程每一个 Button」加动效。若用 `set_script()`，
##   会**顶掉按钮自己的脚本** —— 工程里 `main_ui.gd` / `card_area.gd` / `dialogue_ui.gd`
##   都有挂了脚本的按钮，被顶掉后**不报任何错**，只是那个按钮的业务逻辑静默失效。
##   做成子节点则完全不碰宿主 Button 的脚本，只读写它的 position / scale / pivot_offset。
##
## ▍🔴 为什么必须是 `Node2D` 而不是 `Node`（2026-10-06 实测抓到的真 bug，别改回去）：
##   笔圈（`Line2D`）挂在本节点之下，于是链是 **Button → 本节点 → Line2D**。
##   Godot 的 `CanvasItem::get_parent_item()` **只看直接父节点**、不往上找：
##   中间夹一层**普通 `Node`（不是 CanvasItem）**，整条画布变换链就断了 ——
##   `Line2D.get_global_transform()` 直接退化成**画布坐标**（= 相对视口原点）。
##   症状：鼠标悬浮任意按钮，**铅笔圈画在屏幕左上角**（圆心 = 按钮 size/2，
##   因为 `_ring.position` 仍然被当成局部坐标用），按钮再远也一样；**零报错**。
##   实测取证（`debug/_cvs_parent_test.tscn`，Control@(500,300) 里 Line2D@(100,30)）：
##     A 直挂 Button→Line2D        → 全局原点 (600,330) ✓
##     B 跨普通 Node               → 全局原点 **(100,30)** ✗（Button 的变换被丢掉）
##     C 跨 Node2D                 → 全局原点 (600,330) ✓
##   ⇒ 本节点是 CanvasItem ⇒ 笔圈自动继承 Button 的位置 / 缩放（按下下沉时圈跟着沉）。
##   ⚠️ 连带约束：`ButtonSkin._attach_fx` 里建节点必须用 `Node2D.new()` ——
##      写成 `Node.new()` + `set_script(本脚本)` 会因「脚本继承自 Node2D」直接报错。
##   ⚠️ `debug/_btn_anim_demo.gd::_report_geometry` 当初把「圈的中心」直接当按钮中心算，
##      **没有量 `Line2D` 的真实全局变换** ⇒ 尺子编错，把这个 bug 放过去了。
##      验收笔圈一律量 `ring.get_global_transform() × pts`（回归探针 `debug/_ring_probe.tscn`，判据 BAD=0）。
##
## ▍动效语言（直接沿用 components/scene_spot.gd 的 v3/v4，**已过用户验收**）：
##   ① 悬浮时**本体不动**，只做「拿铅笔把它圈一圈」。
##      —— v3/v4.2 的教训：放大 + 上浮 + 提亮**三个一起上**读作「这块 UI 被选中了」＝
##         「屏幕在动」；纸上该发生的是「有个东西被圈了出来」。所以这里只有笔圈一个通道。
##   ② 离开**不是倒放**：像橡皮**顺着笔迹从头擦过去**（可见段 [tail, head]，
##      动 tail 而不是缩短整条线）。倒放读作「倒带」，一眼假。
##   ③ 只有「点得动」的按钮才画圈：圈是「这里能点」的承诺，disabled 给它画圈等于骗玩家。
##
## ▍本项目新加的唯一一个动作 = **按下**。
##   按下不是「圈」，是「压」：整块纸片往下沉 PRESS_SINK px，松手弹回。
##   刻意**不复用笔圈语言** —— 圈是「标记」，下沉是「力」，两件事。
##
## ▍起笔三件（缺一不可，scene_spot 在这里栽过 6 轮）：
##   ① 所有参与进度的量（head / tail）**一起归零**；
##   ② 归零后**立刻刷新几何**（Line2D.points 不自清，不刷新会在起笔第一帧闪一下整圈）；
##   ③ 补间**显式从 0.0 起**（写成「从当前值到终点」→ 第 2 次悬浮是 1.0→1.0，一个点都不长）。

## 石墨褐。**不用纯黑**：纯黑压在彩铅画面上立刻出「数码味」（scene_spot RING_COLOR 原话）。
const GRAPHITE := Color(0.361, 0.271, 0.204, 1.0)
## 屏上笔宽（px）。Line2D 挂在按钮之下、不受缩放影响，所以这里就是屏上真值。
const RING_WIDTH := 3.0
## 圈画在按钮矩形外多少 px，**横纵分开给**。
## 按钮多为 4:1 的宽矩形，一个「等比外扩」的圈在这里必然变成一根扁椭圆（切进按钮角上
## 40% 的点），观感像「一瓣月牙」。把纵向多放一点，圈就圆过来。
const RING_PAD_X := 10.0
const RING_PAD_Y := 16.0
## 折线点数。96 段足以让 393px 宽的长弧看不出折角。
const RING_SEGMENTS := 96
## 一圈画完 / 擦完的时间。
const RING_DRAW_TIME := 0.32
const RING_ERASE_TIME := 0.22
## 起笔相位与总跨度：起点在左下、多绕 9% → **首尾交叠出头**，手画的圈从不闭合。
const RING_START := -PI * 0.66
const RING_SPAN := TAU * 1.09
## 谐波：让圈不是几何椭圆。按钮是宽矩形，横向幅度给得比纵向小一点，
## 否则长轴上一点抖动会被放大成很夸张的波浪。
const RING_WOB_X := 0.030
const RING_WOB_Y := 0.050

## 按下的下沉量（px）。3px 在 99px 高的按钮上「感觉得到但说不出」。
const PRESS_SINK := 3.0
## 按下 / 弹回的时间（同 scene_spot 的 _tween_press）：按下要脆，回弹要软。
const PRESS_DOWN_TIME := 0.08
const PRESS_UP_TIME := 0.14

var _btn: Button = null
var _ring: Line2D = null
var _pts := PackedVector2Array()
## 笔迹可见段 = 折线的 [tail, head] 区间
var _head := 0.0
var _tail := 1.0
var _head_tw: Tween = null
var _tail_tw: Tween = null
## 按下进度 0..1
var _sink := 0.0
var _sink_tw: Tween = null
var _base_pos := Vector2.ZERO
## 父节点是 Container 时不能用 position 做下沉（容器会覆写它，下一帧就被拉回去）→
## 改用 scale（容器不管 scale）。两条路径的**观感等价**，见 `_apply_sink()`。
var _in_container := false


func _ready() -> void:
	_btn = get_parent() as Button
	if _btn == null:
		push_warning("PaperButtonFX: 父节点不是 Button，本节点自毁")
		queue_free()
		return
	_base_pos = _btn.position
	_in_container = _btn.get_parent() is Container
	_btn.mouse_entered.connect(fx_hover)
	_btn.mouse_exited.connect(fx_unhover)
	_btn.button_down.connect(fx_down)
	_btn.button_up.connect(fx_up)
	_btn.resized.connect(_rebuild_ring)
	_make_ring()
	_rebuild_ring()


## 悬浮笔圈。挂在 Button 之下当子节点 → 自动跟着按钮的位置变换走（按下时一起下沉），
## 不需要两边各自同步。
func _make_ring() -> void:
	_ring = Line2D.new()
	_ring.name = "PencilRing"
	_ring.default_color = GRAPHITE
	# 工程全局 default_texture_filter=0（NEAREST）→ 笔画这类带软边的矢量必须自己开 AA，
	# 否则斜线是台阶（scene_spot 同款处理）。
	_ring.antialiased = true
	_ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_ring.end_cap_mode = Line2D.LINE_CAP_ROUND
	_ring.joint_mode = Line2D.LINE_JOINT_ROUND
	_ring.width = RING_WIDTH
	_ring.width_curve = _make_press_curve()
	_ring.visible = false
	add_child(_ring)


## 笔压曲线：起笔轻 → 中段实 → 收笔细。Line2D 的 width 会乘这条曲线的 y 值。
func _make_press_curve() -> Curve:
	var cu := Curve.new()
	cu.add_point(Vector2(0.00, 0.22))
	cu.add_point(Vector2(0.05, 1.00))
	cu.add_point(Vector2(0.86, 0.92))
	cu.add_point(Vector2(0.96, 0.55))
	cu.add_point(Vector2(1.00, 0.10))
	return cu


## 生成一条「手画一圈」的折线，形状 = **按钮矩形的外扩椭圆** + 两条谐波 + 收笔甩出。
##   · 椭圆（不是贴边描边）：手随手圈一件很宽的东西，圈出来就是个扁椭圆。
##     贴边描边读作「描了个边」，那是排版而不是圈注。
##   · 起点比整圈多绕 9% → 首尾交叠出头
##   · 最后 12% 渐渐离开原轨迹（甩笔）
func _build_ring_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	if _btn == null:
		return pts
	var sz := _btn.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return pts
	var rx := sz.x * 0.5 + RING_PAD_X
	var ry := sz.y * 0.5 + RING_PAD_Y
	for i in range(RING_SEGMENTS + 1):
		var u := float(i) / float(RING_SEGMENTS)
		var a := RING_START + RING_SPAN * u
		var wx := 1.0 + RING_WOB_X * sin(a * 3.0 + 0.7) + RING_WOB_X * 0.6 * sin(a * 5.0 - 1.9)
		var wy := 1.0 + RING_WOB_Y * sin(a * 2.7 + 2.3) + RING_WOB_Y * 0.6 * sin(a * 6.3 - 0.4)
		var flick := 1.0 + 0.07 * pow(clampf((u - 0.88) / 0.12, 0.0, 1.0), 2.0)
		pts.append(Vector2(cos(a) * rx * wx * flick, sin(a) * ry * wy * flick))
	return pts


## 尺寸一变就得重算：① 折线按新矩形重建 ② 折线原点挪到新中心
## ③ pivot 归到中心（容器路径的缩放要绕中心缩）。
func _rebuild_ring() -> void:
	if _ring == null or _btn == null:
		return
	_ring.position = _btn.size * 0.5
	_btn.pivot_offset = _btn.size * 0.5
	_pts = _build_ring_points()
	_sync_ring()


func _is_live() -> bool:
	return _btn != null and _btn.visible and not _btn.disabled


func fx_hover() -> void:
	if _is_live():
		_draw_ring(true)


func fx_unhover() -> void:
	_draw_ring(false)


func fx_down() -> void:
	if _is_live():
		_tween_sink(1.0)


func fx_up() -> void:
	_tween_sink(0.0)


func _draw_ring(on: bool) -> void:
	if _ring == null:
		return
	if _head_tw != null and _head_tw.is_valid():
		_head_tw.kill()
	if _tail_tw != null and _tail_tw.is_valid():
		_tail_tw.kill()
	if on:
		# ⚠️ 见文件头「起笔三件」。scene_spot 里曾经只归 tail，
		#    而擦除只动 tail、head 擦完停在 1.0 → 第 2 次悬浮整圈瞬间出现，一个点都不长。
		_head = 0.0
		_tail = 0.0
		_tail_tw = null
		_sync_ring()
		_head_tw = create_tween()
		# EXPO/OUT：起笔快、收笔缓 —— 手画一圈的节奏（先果断绕过去，最后在找收笔位置）
		_head_tw.tween_method(_set_head, 0.0, 1.0, RING_DRAW_TIME) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	else:
		if not _ring.visible:
			return
		_tail_tw = create_tween()
		# QUAD/IN：先慢后快，像橡皮压上去再一路擦过去
		_tail_tw.tween_method(_set_tail, _tail, 1.0, RING_ERASE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _set_head(v: float) -> void:
	_head = clampf(v, 0.0, 1.0)
	_sync_ring()


func _set_tail(v: float) -> void:
	_tail = clampf(v, 0.0, 1.0)
	_sync_ring()


## 可见段 = 折线上 [tail, head] 这一段。擦除是从**前端**消失，不是把已有的缩短。
func _sync_ring() -> void:
	if _ring == null or _pts.size() < 2:
		return
	var a := int(round(_tail * float(RING_SEGMENTS)))
	var b := int(round(_head * float(RING_SEGMENTS))) + 1
	if b - a < 2:
		_ring.visible = false
		return
	_ring.visible = true
	_ring.points = _pts.slice(a, mini(b, _pts.size()))


func _tween_sink(target: float) -> void:
	if _sink_tw != null and _sink_tw.is_valid():
		_sink_tw.kill()
	_sink_tw = create_tween()
	_sink_tw.tween_method(_set_sink, _sink, target,
		PRESS_DOWN_TIME if target > _sink else PRESS_UP_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_sink(v: float) -> void:
	_sink = v
	_apply_sink()


func _apply_sink() -> void:
	if _btn == null:
		return
	if _in_container:
		# 容器路径：容器每帧会重排 position，写 position 会被拉回去（不报错，只是「没反应」）。
		# 用绕中心缩放代替下沉：0.97 缩向中心，读作「被按进去」。
		_btn.scale = Vector2.ONE * (1.0 - 0.03 * _sink)
	else:
		_btn.position = _base_pos + Vector2(0.0, PRESS_SINK * _sink)


## 一键清干净（录制起手 / 重进界面用）：把还挂在半路的补间杀掉、进度量归零、几何刷新。
func fx_reset() -> void:
	for tw in [_head_tw, _tail_tw, _sink_tw]:
		if tw != null and tw.is_valid():
			tw.kill()
	_head_tw = null
	_tail_tw = null
	_sink_tw = null
	_head = 0.0
	_tail = 1.0
	_sink = 0.0
	if _ring != null:
		_ring.visible = false
	_apply_sink()


## 供探针/调试读的当前态（不要直接读私有 var，读这个，将来改内部实现不会打断探针）。
func fx_state() -> Dictionary:
	return {
		"head": _head,
		"tail": _tail,
		"sink": _sink,
		"ring_visible": _ring != null and _ring.visible,
		"ring_points": _ring.points.size() if _ring != null else 0,
		"y_offset": (_btn.position.y - _base_pos.y) if _btn != null else 0.0,
		"scale": _btn.scale.x if _btn != null else 1.0,
		"in_container": _in_container,
	}
