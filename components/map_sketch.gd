extends Control
## 地图涂鸦层 —— 让「纸」对鼠标有回执。
##
## ▍要解决的问题
##   地图上除了十来个可点图标，其余全是死区：点下去没有任何回应，鼠标在地图上
##   「没有重量」。这一层给空白区一个最小但真实的手感回执 ——
##   单击留一个铅笔点，按住拖动留下铅笔轨迹。
##
## ▍为什么不做成「点击特效」
##   一次性播放的特效玩家看三次就免疫了。这里的做法是把交互直接映射成
##   「铅笔在纸上做的动作」：点一下是顿笔，拖过去是划一道。它跟 scene_spot
##   那支铅笔圈是同一个材质、同一个节奏（TICK = 0.125，8fps 按拍，绝不插值）。
##
## ▍挂在哪、为什么
##   挂在每个地图场景的 `background`（全屏 TextureRect）之下，作为它的子节点：
##     · 绘制顺序：子节点后画 → 涂鸦在底图之上、地图图标与 HUD 之下，
##       永远不会盖住图标和手牌。
##     · 输入顺序：Godot 的 GUI 拾取按绘制顺序**逆序**（后画的先拿），所以点图标 /
##       点手牌 / 点顶栏按钮时那些控件先吃事件，本层收不到；只有点在真正的空白处
##       事件才落到这里。**不需要维护任何禁点清单。**
##     · 按下之后 Godot 把 mouse_focus 钉在本层，后续 motion 一直发过来，
##       所以从空白起笔、划过建筑图标，笔迹不会断。
##
## ▍为什么不放进 map/*.tscn
##   `scene/*.tscn` 的节点顺序并不统一（main 是 background→map→Main_ui，
##   orphanage 是 background→Main_ui→map）。放进 map 里，在后一种场景中涂鸦会画到
##   HUD 之上，而且整块 STOP 会挡住手牌区。挂在 background 下与场景顺序无关，
##   9 张地图行为一致。
##
## ▍三道闸：痕迹的长度与寿命都受限（2026-10-13 用户：「痕迹的长度和存在时间要
##   限制一下，以保证不影响正常观感」）
##   「涂鸦一直留着」是这个效果的**卖点，也是它唯一的风险** —— 玩十分钟之后整张
##   地图全是线，地图本身反而看不见了。所以：
##     ① 单笔封顶 `STROKE_MAX_LEN`：一笔最多画这么长，到顶就**封笔** —— 玩家手还
##        按着，只是纸不再吃墨。不自动开新笔，免得一段拖拽刷出好几条。
##     ② 场上总量 `MAX_MARKS`：同时存在的痕迹条数（点、轨迹各算一条）。到顶时把
##        **最老的那条提前推进淡出**，而不是硬删 —— 硬删读起来是「啪一下没了」，
##        提前淡出读起来是「这条旧了，正在淡」。
##     ③ 到期淡出 `LIFE` / `FADE`：满亮 (LIFE - FADE) 秒，再用 FADE 秒线性淡出。
##        淡出走 alpha 通道连续衰减，**不加抖动** —— 抖动只属于「线在动」，
##        淡出是「线在走」，两回事。
##   三条一起，地图上任何时刻只有「最近几秒的少量痕迹」。

## 手绘节奏：8fps。与 scene_spot 的 TICK 同一个值 —— 同一支笔，同一种拍子。
const TICK := 0.125
## 抖动（line boil）幅度，px。铅笔线从来不是一条数学直线。
const BOIL_AMP := 0.75
## 抖动帧数。每拍换一帧，8Hz × 4 帧 ≈ 每半秒循环一次，看不出规律。
const BOIL_FRAMES := 4
## 轨迹采样间距，px。低于这个距离的新点直接丢掉 —— 既省绘制，
## 又让笔迹天然带一点「手势到位才落笔」的颗粒感。
const MIN_STEP := 5.0
## 单击笔点半径 / 轨迹笔宽，px。
const DOT_R := 2.6
const STROKE_W := 2.8
## 铅笔颗粒半径：沿轨迹撒的短笔屑，让线边缘不齐。
const GRAIN_R := 1.05
## 石墨色。**不是纯黑** —— 铅笔划在纸上没有纯黑，alpha 也压一档，
## 让它读成「一层浅浅的铅」而不是「一条 UI 描边」。
const INK := Color(0.180, 0.169, 0.157, 0.70)
const INK_SOFT := Color(0.180, 0.169, 0.157, 0.30)

## ── 三道闸：要调手感就改这几个数，结构不用动 ──────────────
## 每条痕迹的总寿命，秒。前 (LIFE - FADE) 秒满亮，之后淡出。
const LIFE := 5.0
## 淡出时长，秒。
const FADE := 1.5
## 场上最多同时存在几条痕迹（点 / 轨迹各算一条）。到顶挤掉最老的。
const MAX_MARKS := 8
## 单条轨迹最长多少 px。到顶封笔。
const STROKE_MAX_LEN := 1200.0
## 单条轨迹最多多少采样点。兜底：极慢的拖动会拉长同一条轨迹，光靠长度封不住点数。
const STROKE_MAX_PTS := 240
## 正在淡出的痕迹堆积到这个数就硬删（玩家疯狂连点时的兜底，正常玩碰不到）。
const HARD_MAX_MARKS := 36

## 可落笔的「地图区」（**屏幕 px**）。
##   上边 110 = 顶栏纸（0~100）之下；下边 822 = 手牌区 `CardArea.offset_top`
##   （见 `components/main_ui.tscn`）；左右 22 / 1898 = 地图节点 `Control` 的
##   `offset_left/right`（见 `map/*.tscn`，9 张一致）。
## 注意：手牌区高度改了要跟着改这里，否则会出现「点了没反应」或
##   「笔迹画在 HUD 底下、玩家看不见」。
const FIELD_POS := Vector2(22.0, 110.0)
const FIELD_SIZE := Vector2(1876.0, 712.0)

## 场上所有痕迹，先进先出。每项：
##   { "kind": "dot" | "stroke", "pts": PackedVector2Array, "born": float }
var _marks: Array[Dictionary] = []
## 正在画的那一笔（还没进 `_marks`，所以不参与淘汰）。
var _cur := PackedVector2Array()
var _cur_len := 0.0
var _drawing := false
## 本层自己的时钟。有痕迹时才走（见 `_sync_process`），空闲零开销。
var _now := 0.0
var _frame := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


# ============================================================
#  输入
# ============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# 手牌拖拽期间整块 GUI 都在传 drop 载荷，此时按下的左键不是「在纸上落笔」。
			if get_viewport().gui_is_dragging():
				cancel_stroke()
				return
			if mb.pressed:
				begin_stroke(mb.position)
			else:
				end_stroke()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			clear_all()
			accept_event()
	elif event is InputEventMouseMotion and _drawing:
		# 拖拽一介入就撤掉这一笔：玩家是去拖卡，不是去涂鸦。
		if get_viewport().gui_is_dragging():
			cancel_stroke()
			return
		extend_stroke((event as InputEventMouseMotion).position)


## 起笔。**按下即落点** —— 单击的手感不能等到松手才出现。
func begin_stroke(local_pos: Vector2) -> void:
	if not _in_field(local_pos):
		return
	_drawing = true
	_cur = PackedVector2Array([local_pos])
	_cur_len = 0.0
	_sync_process()
	queue_redraw()


## 沿线加点。低于 MIN_STEP 丢弃；移出地图区不记录；到顶封笔。
func extend_stroke(local_pos: Vector2) -> void:
	if not _drawing:
		return
	if not _in_field(local_pos):
		return
	var n := _cur.size()
	if n > 0:
		var d := _cur[n - 1].distance_to(local_pos)
		if d < MIN_STEP:
			return
		# 闸①：这一笔到顶了。手还按着，纸不再吃墨。
		if _cur_len + d > STROKE_MAX_LEN or n >= STROKE_MAX_PTS:
			return
		_cur_len += d
	_cur.append(local_pos)
	_sync_process()
	queue_redraw()


## 收笔。只有按下那一个点的 = 单击，补一个顿笔点；有长度的 = 一笔轨迹。
func end_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	if _cur.size() == 1:
		_push_mark("dot", _cur)
	elif _cur.size() > 1:
		if _cur_len < MIN_STEP * 0.9:
			# 手抖了一下，不算一笔
			_push_mark("dot", PackedVector2Array([_cur[0]]))
		else:
			_push_mark("stroke", _cur)
	_cur = PackedVector2Array()
	_cur_len = 0.0
	_sync_process()
	queue_redraw()


## 丢弃正在画的一笔（拖拽介入 / 切场景中止）。
func cancel_stroke() -> void:
	if not _drawing and _cur.is_empty():
		return
	_drawing = false
	_cur = PackedVector2Array()
	_cur_len = 0.0
	_sync_process()
	queue_redraw()


## 整张擦掉。
func clear_all() -> void:
	_drawing = false
	_cur = PackedVector2Array()
	_cur_len = 0.0
	_marks.clear()
	_sync_process()
	queue_redraw()


func _in_field(local_pos: Vector2) -> bool:
	return Rect2(FIELD_POS, FIELD_SIZE).has_point(get_global_transform() * local_pos)


# ============================================================
#  存活与淘汰
# ============================================================

func _push_mark(kind: String, pts: PackedVector2Array) -> void:
	_make_room()
	_marks.append({"kind": kind, "pts": pts, "born": _now})


## 闸②：到上限就把**超出的那几条**一起提前推进淡出，不硬删。
## 硬删（`pop_front`）读起来是「啪一下没了」，提前淡出读起来是「这条旧了」。
## ⚠️ 必须按「超出几条就提前几条」来推，不能只推 `_marks[0]` ——
##    只推最老那一条的话，第二次、第三次连点推的还是同一条（它 born 已经到位，no-op），
##    后面的旧痕迹压根不动，满亮条数照样无限涨。
func _make_room() -> void:
	var over := _marks.size() - MAX_MARKS + 1
	if over > 0:
		var want := _now - (LIFE - FADE)
		var i := 0
		while i < over and i < _marks.size():
			var m: Dictionary = _marks[i]
			if float(m["born"]) > want:
				m["born"] = want
			i += 1
	while _marks.size() > HARD_MAX_MARKS:
		_marks.pop_front()


## 当前透明度：前 (LIFE - FADE) 秒满亮，之后 FADE 秒线性淡出。
func _alpha_of(born: float) -> float:
	var age := _now - born
	var full := LIFE - FADE
	if age <= full:
		return 1.0
	if age >= LIFE:
		return 0.0
	return 1.0 - (age - full) / FADE


func _expire() -> void:
	var i := _marks.size() - 1
	while i >= 0:
		if _alpha_of(float(_marks[i]["born"])) <= 0.0:
			_marks.remove_at(i)
		i -= 1


## 有东西可画才走时钟 —— 空闲时本层零开销。
func _sync_process() -> void:
	set_process(_drawing or not _marks.is_empty())


func _process(delta: float) -> void:
	_now += delta
	_expire()
	# 抖动帧号从本层时钟派生：每 TICK 秒才换一帧。所以重绘虽然每帧都做
	#（淡出要连续），抖动仍然是 8fps 的按拍跳，不是连续插值。
	_frame = int(_now / TICK) % BOIL_FRAMES
	queue_redraw()
	if _marks.is_empty() and not _drawing:
		_sync_process()


# ============================================================
#  绘制
# ============================================================

func _draw() -> void:
	for m in _marks:
		var k := _alpha_of(float(m["born"]))
		if k <= 0.0:
			continue
		if m["kind"] == "dot":
			_draw_dot(m["pts"][0], k)
		else:
			_draw_stroke(m["pts"], k)
	if _drawing and _cur.size() > 0:
		_draw_stroke(_cur, 1.0)


## 一笔轨迹：抖动折线 + 沿线撒的笔屑 + 两端顿笔。
func _draw_stroke(src: PackedVector2Array, k: float) -> void:
	var n := src.size()
	if n == 0:
		return
	if n == 1:
		_draw_dot(src[0], k)
		return
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in range(n):
		pts[i] = src[i] + _wobble(i, 0) * BOIL_AMP
	draw_polyline(pts, _ink(k), STROKE_W, true)
	for i in range(1, n - 1, 3):
		draw_circle(src[i] + _wobble(i, 1) * (BOIL_AMP * 1.7), GRAIN_R, _ink_soft(k))
	# 顿笔：起笔重一点、收笔轻一点
	draw_circle(pts[0], STROKE_W * 0.46, _ink(k))
	draw_circle(pts[n - 1], STROKE_W * 0.40, _ink(k))


## 一个铅笔点。三个微偏移的小圆叠出来 —— 手点出来的点不是正圆。
func _draw_dot(p: Vector2, k: float) -> void:
	for i in range(3):
		var off := _wobble(i, 2) * 0.85
		var r := DOT_R * (1.0 - 0.17 * float(i))
		draw_circle(p + off, r, _ink(k) if i == 0 else _ink_soft(k))


func _ink(k: float) -> Color:
	return Color(INK.r, INK.g, INK.b, INK.a * k)


func _ink_soft(k: float) -> Color:
	return Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, INK_SOFT.a * k)


## 确定性伪随机偏移，返回 [-1, 1]²。
## 用点序号 + 帧号算，而不是每帧 randf() —— 同一帧内重绘多次结果一致，
## 且每拍（0.125s）整条线的抖动形态换一次，这就是 line boil。
func _wobble(i: int, salt: int) -> Vector2:
	var f := float(_frame)
	var a := sin(float(i) * 12.9898 + f * 78.233 + float(salt) * 3.1) * 43758.5453
	var b := sin(float(i) * 39.3468 + f * 11.135 + float(salt) * 7.7) * 24634.6345
	return Vector2(a - floor(a), b - floor(b)) * 2.0 - Vector2.ONE


# ============================================================
#  调试 / 探针接口（不改行为，只读状态）
# ============================================================

func debug_state() -> Dictionary:
	var dots := 0
	var strokes := 0
	var points := 0
	for m in _marks:
		if m["kind"] == "dot":
			dots += 1
		else:
			strokes += 1
			points += (m["pts"] as PackedVector2Array).size()
	return {
		"dots": dots,
		"strokes": strokes,
		"points": points,
		"marks": _marks.size(),
		"cur": _cur.size(),
		"cur_len": _cur_len,
		"frame": _frame,
		"drawing": _drawing,
		"ticking": is_processing(),
	}


## 场上每条痕迹当前的透明度（判定淡出用）。
func debug_alphas() -> Array:
	var out := []
	for m in _marks:
		out.append(_alpha_of(float(m["born"])))
	return out


## 手动推进本层时钟（探针用，免得真等 5 秒）。
func debug_advance(sec: float) -> void:
	_now += sec
	_expire()
	_frame = int(_now / TICK) % BOIL_FRAMES
	_sync_process()
	queue_redraw()


## 所有痕迹的包围盒（局部坐标）。空 = `Rect2()`（size 为 0）。
func debug_bounds() -> Rect2:
	var has := false
	var mn := Vector2.INF
	var mx := -Vector2.INF
	for m in _marks:
		for p in (m["pts"] as PackedVector2Array):
			mn = mn.min(p)
			mx = mx.max(p)
			has = true
	for p in _cur:
		mn = mn.min(p)
		mx = mx.max(p)
		has = true
	if not has:
		return Rect2()
	return Rect2(mn, mx - mn)


func debug_field_rect() -> Rect2:
	return Rect2(FIELD_POS, FIELD_SIZE)


func debug_stroke_points(idx: int) -> PackedVector2Array:
	var seen := 0
	for m in _marks:
		if m["kind"] != "stroke":
			continue
		if seen == idx:
			return m["pts"]
		seen += 1
	return PackedVector2Array()


func debug_dot(idx: int) -> Vector2:
	var seen := 0
	for m in _marks:
		if m["kind"] != "dot":
			continue
		if seen == idx:
			return (m["pts"] as PackedVector2Array)[0]
		seen += 1
	return Vector2.INF


func debug_limits() -> Dictionary:
	return {
		"life": LIFE,
		"fade": FADE,
		"max_marks": MAX_MARKS,
		"stroke_max_len": STROKE_MAX_LEN,
		"stroke_max_pts": STROKE_MAX_PTS,
	}
