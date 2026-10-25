extends Control
class_name PaperFold

## 翻页的「折线 + 排线影」图层 —— 盖在翻页页面的最上面那一层。
##
## 网页稿 `design/settings_panel/index.html` 里这一层是 SVG + JS 逐帧写 `points`；
## 这里改成 `Control._draw()` 逐帧画，几何算法逐条照搬，参数一个不动：
##   · 折线是**斜的**（顶边比底边超前 TILT px）——读作「右上角先落」。
##     画成竖直线就退化成普通擦除，这是它与「擦除」唯一的区别。
##   · 折线外侧再压一条 +3.5px 的细线 = 纸的厚度（不然折线像一根浮在纸上的墨道）。
##   · 影子 = **与折线平行的短发笔**（不是跟随折线的横向刻线 —— 那读起来像梳子），
##     104 根**预生成**、固定种子、每帧只整体平移；离折线越近越密越深，往外自然淡出。
##   · 「手绘感 = 按拍不插值」：折线**位置连续插值**，笔锋抖动**按 8fps 阶梯跳**。
##
## ⚠️ 这一层**不挂折线裁切材质**（它就是那条线本身）。
## ⚠️ `mouse_filter = IGNORE`：它铺满全屏，绝不能被它吃掉点击。

## 折线两端水平差（顶边相对底边）。网页稿 8 → 15（实测 8 太像擦除，15≈2° 才读得出「斜」）。
const TILT := 15.0
## 折线竖跨的像素高度（本工程 1920x1080，折线纵贯整屏）。
const FH := 1080.0
## 折线中心在 p=0 / p=1 时的 x。
## ⚠️ 这里是 **屏幕宽 + 3×TILT**，不是网页稿的「纸宽 + TILT」：
##    裁切在飞行中一直挂着，若 p=1 时折线只走到 x=屏宽，屏幕**右下角**会留一个
##    15px 宽的透明楔形（顶边到了、底边还差 2×TILT）——静止帧立刻露馅。
##    多给 2×TILT 让两端都彻底出屏。（网页稿不需要这条，因为它在 p=0/1 两端
##    直接把 clip-path 卸掉了；引擎这边卸材质的时机在动画之后，救不了最后一帧。）
const SPAN := 1920.0 + TILT * 3.0
## 笔锋换形的节拍（秒）。8fps。
const TICK := 0.125
## 一次翻页的时长（秒）。与 `paper_flip.gd` 的 DUR 必须一致 ——
## 这里用它把「已过时间占比 t」换算成第几拍。
const DUR := 0.5
## 折线采样点数（网页稿固定 5 点：顶 / 3 个中点 / 底）。
const NPTS := 5

const COL_LINE := Color(0.420, 0.322, 0.157)     # #6B5228 折线
const COL_LINE2 := Color(0.561, 0.424, 0.180)    # #8F6C2E 纸厚线
const COL_HATCH := Color(0.341, 0.263, 0.122)    # #57431F 排线

var _p: float = 1.0
var _jit: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _tick: int = -1
var _stroke: Array = []          # 预生成：每根 [x0, y0, y1, w, alpha]
## 笔锋抖动幅度。网页稿 ±2.0；上下缘（第 0 / 4 点）收到 ±0.9，免得线头戳出纸外。
const JIT_A := 2.0
const JIT_EDGE := 0.9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hatch()
	visible = false
	queue_redraw()


## 与网页稿 `buildHatch()` 同一个种子与同一条密度曲线 ⇒ 任意帧的排线形状可复现。
func _build_hatch() -> void:
	var s := 20261006
	var rnd := func() -> float:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		return float(s) / float(0x7fffffff)
	for i in 104:
		var y0: float = rnd.call() * FH
		var t: float = y0 / FH
		# 楔形：越靠纸顶越厚（44 → 14），与网页稿一致
		var dmax: float = 44.0 + (14.0 - 44.0) * t
		var u: float = pow(rnd.call(), 1.7)          # 0=贴着折线，1=影子的外缘
		var x: float = TILT - 2.0 * TILT * t + u * dmax
		var y1: float = minf(FH, y0 + 46.0 + rnd.call() * 92.0)
		_stroke.append([x, y0, y1, 1.1 + rnd.call() * 0.9, 0.26 * (1.0 - u) + 0.05])


## 设定折线进度 p（0..1）。由翻页动画每帧调用。
##
## `t` = **已过时间占比**（0..1，线性）。为什么不能拿 p 当时间轴：
## 折线位置走的是缓动曲线 `(1-cos πt)/2`，p=0.25 对应的 t 是 **1/3** 而不是 1/4 ——
## 用 p 去数节拍会让**头三分之一的时间笔锋一动不动**（8fps 阶梯变成「三段式卡顿」）。
## 网页稿 `index.html` 的 `repen(t)` 收的就是 t，这里必须一致。
## 省略 `t` 时退回 `p`（只用于「直接冻结在某一帧」的场合，比如出分镜图）。
func set_p(p: float, t: float = -1.0) -> void:
	_p = clampf(p, 0.0, 1.0)
	visible = _p > 0.0005 and _p < 0.9995
	_repen(t if t >= 0.0 else _p)
	queue_redraw()


func get_p() -> float:
	return _p


## 8fps 换一次笔锋：位置连续、笔锋不插值。
func _repen(t: float) -> void:
	var k := int(t * DUR / TICK)
	if k == _tick:
		return
	_tick = k
	for i in range(1, NPTS - 1):
		_jit[i] = randf_range(-JIT_A, JIT_A)
	_jit[0] = randf_range(-JIT_EDGE, JIT_EDGE)
	_jit[NPTS - 1] = randf_range(-JIT_EDGE, JIT_EDGE)


func fold_x() -> float:
	return SPAN * _p - TILT


## 折线上 5 个采样点（含笔锋抖动）。两条线共用 —— 纸厚线就是它整体 +3.5px。
func _line_points(dx: float) -> PackedVector2Array:
	var fx := fold_x()
	var xt := fx + TILT
	var xb := fx - TILT
	var pts := PackedVector2Array()
	for i in NPTS:
		var t := float(i) / float(NPTS - 1)
		pts.append(Vector2(xt + (xb - xt) * t + _jit[i] + dx, t * FH))
	return pts


## 供探针读取的权威几何（探针不该自己重算一遍 —— 尺子编错了会伪装成实现错了）。
func geom() -> Dictionary:
	var fx := fold_x()
	var xt := fx + TILT
	var xb := fx - TILT
	return {
		"p": _p, "fx": fx, "xt": xt, "xb": xb,
		"top": xt + _jit[0], "bottom": xb + _jit[NPTS - 1],
		"slant": (xb + _jit[NPTS - 1]) - (xt + _jit[0]),
		"line_a": _line_alpha(), "hatch_a": _hatch_alpha(),
		"strokes": _stroke.size(),
		"visible": visible,
		# 当前是第几拍（`_repen` 的节拍计数，8fps）。探针用它证明「笔锋真的在跳，不是冻住的」。
		"tick": _tick,
		"jit": [_jit[0], _jit[1], _jit[2], _jit[3], _jit[4]],
	}


## 折线两端各 6% 淡入 / 淡出（进去时「笔尖落下」、出来时「笔尖离纸」）。
func _line_alpha() -> float:
	if _p <= 0.0005 or _p >= 0.9995:
		return 0.0
	if _p < 0.06:
		return _p / 0.06
	if _p > 0.94:
		return (1.0 - _p) / 0.06
	return 1.0


## 排线影：两端 10% 淡入、最后 15% 收掉 —— 这就是「落纸」那一拍。
func _hatch_alpha() -> float:
	if _p <= 0.0005 or _p >= 0.9995:
		return 0.0
	if _p < 0.10:
		return _p / 0.10
	if _p > 0.85:
		return maxf(0.0, (1.0 - _p) / 0.15)
	return 1.0


func _draw() -> void:
	if not visible:
		return
	var g := geom()

	# ---- 折线本体：5 点折线（顶 / 3 个中点 / 底），点上带笔锋抖动 ----
	var la: float = _line_alpha()
	draw_polyline(_line_points(0.0), Color(COL_LINE.r, COL_LINE.g, COL_LINE.b, la * 0.92), 2.2, true)
	# 纸的厚度：同一条折线整体右偏 3.5px
	draw_polyline(_line_points(3.5), Color(COL_LINE2.r, COL_LINE2.g, COL_LINE2.b, la * 0.40), 1.0, true)

	# ---- 排线影：整组平移 fx（形状预生成，不逐帧重算）----
	var ha: float = _hatch_alpha()
	if ha <= 0.001:
		return
	var slope := -2.0 * TILT / FH
	for st in _stroke:
		var x: float = float(st[0]) + g["fx"]
		var y0: float = float(st[1])
		var y1: float = float(st[2])
		var a: float = float(st[4]) * ha
		draw_line(Vector2(x, y0), Vector2(x + slope * (y1 - y0), y1),
			Color(COL_HATCH.r, COL_HATCH.g, COL_HATCH.b, a), float(st[3]), true)
