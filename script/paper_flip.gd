extends Control
class_name PaperFlip

## ════════════════════════════════════════════════════════════════════════════
##  翻页过渡的统一引擎（2026-10-06）
## ════════════════════════════════════════════════════════════════════════════
##
## ▍它是什么
##   把**任意一棵子树**当成「一页纸」，用一条自左向右扫过的**斜折线**把它盖上 / 揭开，
##   折线旁带铅笔排线影（纸投在底下那一层的影子）。
##   网页稿 `design/settings_panel/index.html` 的 `clip-path` + 折线层，在这里收成一个可复用节点。
##
## ▍三个使用者（同一套几何、同一条缓动，所以「看起来是同一个动作」）
##   · `components/settings_menu.gd`  —— 设置页：折线左→右把它**盖上**（开）／**揭开**（关）
##   · `components/achievement_list.gd` —— 成就画卷：同上
##   · `script/scene_transition.gd`   —— 换场景：旧场景抓成一张图当纸，折线扫过时**揭开**露出新场景
##
## ▍一套几何、两个方向 —— 「盖上」和「揭开」为什么是同一个动作
##   折线 = 一根斜线（顶边超前 `TILT` px，读作「右上角先落」），x 从屏外左 → 屏外右。
##   `set_side(+1)`：保留折线**左侧** —— 要翻进来的那一页在左 ⇒ 折线扫过 = 把它盖上。
##   `set_side(-1)`：保留**右侧** —— 纸在右 ⇒ 折线扫过 = 把它揭掉，露出底下。
##   两条路径的**边界线逐像素重合**，只有「折线左右哪边是新内容」不同 ——
##   这正是「主界面的成就 / 新游戏 / 继续游戏和设置页用同一套动画」在实现层面的落点：
##   不需要两套动画，只需要同一个 `u_side`。
##
## ▍p 的含义（0..1）与时长 / 缓动
##   p = 折线扫过的比例。p=0 折线在屏左外（纸一点没露）／p=1 在屏右外（纸整张铺满）。
##   时长固定 `DUR`，缓动 `(1-cos πt)/2`（两端速度为 0：起步「纸被顶一下」、落地不飘）。
##
## 🔴 推进用**墙钟**（`Time.get_ticks_usec()`），**不用 Tween 当驱动**。
##   一句话理由：`play()` 常常是在**建树那一帧**里被调用的（设置页要现搭 ~50 个节点），
##   那一帧的 delta 是「开机 + 建树」的总时长 —— 按 delta 累加的 Tween 会把这份时间
##   **白送给动画**，于是第一拍就跳到 t≈0.3、0.5s 的翻页 0.28s 跑完。
##   实机探针的逐点台账（`debug/_flip_probe.txt`）就是这么逮到的。
##   ⚠️ **不要改成 EASE_OUT**：设置页正文只到纸页局部 x=686，EASE_OUT 会把 **60.1%** 的时长
##      花在扫右边那半张空白纸上；EASE_IN_OUT 压到 **44.5%**（同一把尺子量的，
##      见 `design/settings_panel/_ease.py`）。这个差别**在静止帧里逐像素一样**，只看图发现不了。
##
## ▍裁切怎么落到「整页」上（实装最容易做错的一步）
##   Godot 的材质**不沿节点树继承**：给页根挂 material，子节点照旧原样渲染。
##   所以这里对每个 root 走一遍子树，把**同一个** ShaderMaterial 发给每个 CanvasItem。
##   不用 `CanvasGroup`（是 Node2D，Control 布局会飘）、也不用 `clip_children`
##   （要靠父节点自己画 alpha 遮罩，与本工程「父节点不画东西」的结构冲突）。
##   ⚠️ 飞行中才挂、两端卸掉 —— 静止态一个材质都不留。
##   ⚠️ `node_added` 必须一起接：`ButtonSkin` 会在按钮就绪后往按钮下面塞 `PaperButtonFX`
##      （带一个 Line2D 笔圈），那是**飞行中途**才出现的子节点，不补挂就会露在裁切外。
##
## ▍🔴 不许把本节点自己（或它的祖先）当 root
##   `_apply_root_visibility()` 在 p=0 / p=1 会把 root 整棵设成 `visible = false`；
##   若某个 root 是本节点的祖先，连折线一起被藏起来 ⇒「看不见的翻页」。
##   `setup()` 会挡下这种用法并 push_error。**所以宿主必须给一个和本节点平行的页根**
##   （设置页的 `Page`、成就画卷的 7 个视觉子节点、换场景的快照 TextureRect 都是这么排的），
##   不要图省事写 `setup([self.get_parent()])`。
##
## ▍用法（宿主三行）
##   var flip := PaperFlip.new()
##   add_child(flip)                       # ⚠️ 必须排在**最后** —— 它就是画在最上面的那条线
##   flip.setup([page])                    # 一页纸的根（不含本节点）
##   flip.play(0.0, 1.0, func(): ...)      # 盖上
##   flip.play(1.0, 0.0, func(): ...)      # 揭开

## 一次翻页（p 走满 0→1）的时长，秒。
const DUR := 0.5
const SCR_W := 1920.0
const SCR_H := 1080.0

const FLIP_SHADER: Shader = preload("res://script/paper_flip.gdshader")

## 翻完了。参数 = 落地的 p（0 或 1）。
signal finished(p: float)
## 折线进度变化（每一帧）。宿主拿它做「p 到 0 就把页藏掉」之类的联动。
signal p_changed(p: float)

## 🔴 静止态「页根可见性」由谁管。默认 `true` = 本节点管（设置页 / 成就画卷用这条）。
##
## 设成 `false` = **宿主自己管**，`_apply_root_visibility()` 整个不执行。
## 换场景那条路（`scene_transition.gd`）**必须**设 false，原因见下：
##   它的「一页纸」是**全屏 `SceneSnapshot`（`mouse_filter = STOP`，CanvasLayer 120）**，
##   而本类在 `side = -1` 下 p=0 时算出的可见性是 **true**（「右侧那半张还露着」——
##   对翻页几何来说是对的）。于是 `SceneTransition._ready()` 里那句 `set_side(-1.0)`
##   会把这张**空贴图的全屏遮罩**点亮并**一直留着**（静止态 p 恒为 0）：
##   画面看不出任何异常（贴图为 null），但**全工程所有按钮、所有地图节点全部点不动**。
##   2026-10-06 实测抓到的就是这个 —— 真窗口探针里 hover 到的永远是
##   `SceneTransition/SceneSnapshot`，6 颗标题按钮 `pressed` 一个都不响。
##   ⚠️ 所以换场景那条路的 `_snap.visible` **只许**由 `scene_transition.gd` 自己收放
##      （`change_scene` / `flip_cover` 里置 true，`_finish()` 里置 false）。
var manage_visibility: bool = true
var _mat: ShaderMaterial = null
var _fold: PaperFold = null
var _roots: Array[CanvasItem] = []
var _clip_on: bool = false
var _p: float = 0.0
var _side: float = 1.0
var _busy: bool = false
## 本次飞行的起点 / 终点 p。
var _from: float = 0.0
var _to: float = 0.0
## 本次飞行的「已过时间占比」（0..1）。探针必须拿它跟 `p` **成对采**（见文件头）。
var _t: float = 0.0
## 本次飞行的时钟零点（`Time.get_ticks_usec()`）。**第一拍只用来对表**。
var _usec0: int = 0
## 落地后回调谁。存成成员而不是塞进闭包 —— 现在没有 Tween 可以挂它。
var _on_done: Callable = Callable()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# ⚠️ 跟着 `_busy` 走，**不要写死 false**：`_ensure()` 允许「先 `play()` 再 `add_child`」，
	#    写死就会把那种用法下已经开好的每帧处理关掉 ⇒ 翻页永远停在起点（且什么都不报）。
	set_process(_busy)
	_ensure()
	_set_p(_p)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## 建材质与折线层。幂等 —— `setup()` / `play()` 也会调一次，
## 这样即使调用方在 `add_child` 之前就用它也不会炸。
func _ensure() -> void:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = FLIP_SHADER
		_mat.set_shader_parameter("u_size", Vector2(SCR_W, SCR_H))
		_mat.set_shader_parameter("u_tilt", PaperFold.TILT)
		_mat.set_shader_parameter("u_side", _side)
	if _fold == null:
		_fold = PaperFold.new()
		_fold.name = "Fold"
		add_child(_fold)
		_fold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_tree() != null and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


# ================================================================ 配置
## 指定「当作一页纸」的子树根。可以给多个（各自整棵子树都会被裁）。
##
## ⚠️ root 里不许含本节点（或本节点的祖先），见文件头。
func setup(roots: Array) -> void:
	_ensure()
	_roots.clear()
	for r in roots:
		if r == null or not (r is CanvasItem):
			continue
		var ci := r as CanvasItem
		if ci == self or ci.is_ancestor_of(self):
			push_error("PaperFlip.setup: root %s 含本节点 —— 会把折线一起藏掉，已跳过" % ci.name)
			continue
		_roots.append(ci)
	if _clip_on:
		_apply_clip(true)      # 已在飞行中换 root：立刻补挂
	_set_p(_p)                 # 立刻按当前 p 定 root 的可见性（不能等到下一帧）


## 保留折线哪一侧。+1 = 左（盖上）/ -1 = 右（揭开）。
func set_side(side: float) -> void:
	_side = -1.0 if side < 0.0 else 1.0
	_ensure()
	_mat.set_shader_parameter("u_side", _side)
	_apply_p()


func side() -> float:
	return _side


# ================================================================ 缓动
## `(1 - cos πt) / 2`。两端速度为 0。
##
## 🔴 **必须自己算，别交给引擎的缓动**：
##   ① 这里同时要 `t`（笔锋节拍按**时间**走，见 `paper_fold.gd::set_p`）——
##      引擎只交出插值后的值，`t` 就拿不回来了；
##   ② 自己算 = 与网页稿的 `eager(t)`、与 `design/settings_panel/_ease.py`
##      量的那条曲线**逐位同源**，「缓动改没改」才有唯一答案。
static func ease_in_out(t: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(t, 0.0, 1.0))


# ================================================================ 播放
## 从 p=`from` 走到 p=`to`。`on_done` 在落地后调用（可选择直接 queue_free 宿主）。
##
## 🔴 **不建 Tween**：Tween 靠「把每帧 delta 累加」推进，而 `play()` 常常就在
##    **建树那一帧**里被调用（宿主在 `_ready()` 里现搭页面、紧接着 `play()`）。
##    那一帧的 delta 是「开机 + 建树」的总时长，累加式推进把这份时间**白送**给动画 ——
##    实机台账实测：第一拍 t 直接 0.300、第二拍 0.533，0.5s 的翻页 0.28s 就落地了。
##    墙钟推进下，长帧只表现为「这一帧跳得多」，总时长恒为 `DUR` —— 那才是观感契约。
func play(from: float, to: float, on_done: Callable = Callable()) -> void:
	_ensure()
	_busy = true
	_from = from
	_to = to
	_on_done = on_done
	_t = 0.0
	_usec0 = 0                  # 0 = 还没对表（第一拍在 `_process` 里只对表、不动 p）
	_set_clip(true)
	_set_p(from)
	set_process(true)


func _process(_delta: float) -> void:
	if _usec0 == 0:
		_usec0 = Time.get_ticks_usec()
		return                  # 这一拍只对表：把在此之前建树 / 入栈 / 抓帧的耗时切掉
	var span := DUR * absf(_to - _from)
	if span <= 0.000001:
		_done()
		return
	var t := clampf(float(Time.get_ticks_usec() - _usec0) / 1000000.0 / span, 0.0, 1.0)
	_t = t
	_set_p(_from + (_to - _from) * ease_in_out(t), t)
	if t >= 1.0:
		_done()


## 落地：定住 p、卸掉裁切、放回调。**幂等**（`_busy` 一关就不会再进）。
func _done() -> void:
	if not _busy:
		return
	set_process(false)
	_t = 1.0
	_set_p(_to)
	_set_clip(false)           # 静止态一个材质都不留（同网页稿「clip-path 只在飞行中挂」）
	_busy = false
	finished.emit(_to)
	var cb := _on_done
	_on_done = Callable()
	if cb.is_valid():
		cb.call()


func is_busy() -> bool:
	return _busy


func p() -> float:
	return _p


func fold() -> PaperFold:
	return _fold


## 折线中心 x。**必须与 `paper_fold.gd::fold_x()` 同源** ——
## 两处各写一份公式就等着「线和裁切对不上」，所以这里直接拿那边的常量算，不抄数字。
func fold_x(p: float) -> float:
	return PaperFold.SPAN * p - PaperFold.TILT


# ================================================================ 内部
## `t` = 已过时间占比（笔锋节拍用）；-1 表示「按 p 直接冻结」（出分镜图用）。
func _set_p(p: float, t: float = -1.0) -> void:
	_p = clampf(p, 0.0, 1.0)
	_apply_p()
	if _fold != null:
		_fold.set_p(_p, t)
	p_changed.emit(_p)


func _apply_p() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("u_fold", fold_x(_p))
	_apply_root_visibility()


## 一页纸「还露着多少」：side=+1 时 p>0 就露；side=-1 时 p<1 才露。
## 两端整棵 `visible=false`，既是省一次绘制，也是兜底 ——
## 万一有哪个 CanvasItem 漏挂了材质，也不会在 p=0 / p=1 露在折线外面。
##
## ⚠️ `manage_visibility = false` 时整段不跑（宿主自己收放页根可见性）——
##    换场景那条路的「页」是一张 `mouse_filter = STOP` 的全屏遮罩，在这里被点亮
##    会**静默吃掉全工程所有点击**，见 `manage_visibility` 的注释。
func _apply_root_visibility() -> void:
	if not manage_visibility:
		return
	var vis := (_p > 0.0005) if _side > 0.0 else (_p < 0.9995)
	for r in _roots:
		if is_instance_valid(r):
			(r as CanvasItem).visible = vis


func _set_clip(on: bool) -> void:
	if on == _clip_on:
		return
	if on and _roots.is_empty():
		# 静默失败的典型形态：「翻页动画在放，但那一页压根没被裁」——
		# 藏了一整个可见性 bug。宁可吵一句。
		push_warning("PaperFlip: 还没 setup() 就 play()，没有任何子树会被裁切")
	_clip_on = on
	_apply_clip(on)


func _apply_clip(on: bool) -> void:
	for r in _roots:
		if is_instance_valid(r):
			_clip_tree(r as CanvasItem, on)


func _clip_tree(n: Node, on: bool) -> void:
	if n is CanvasItem:
		(n as CanvasItem).material = _mat if on else null
	for c in n.get_children():
		if c is Window:
			continue
		_clip_tree(c, on)


## 飞行中途冒出来的 CanvasItem（ButtonSkin 的 PaperButtonFX / Line2D 笔圈）补挂裁切。
func _on_node_added(n: Node) -> void:
	if not _clip_on or not (n is CanvasItem):
		return
	for r in _roots:
		if is_instance_valid(r) and (r as CanvasItem).is_ancestor_of(n):
			(n as CanvasItem).material = _mat
			return


# ================================================================ 探针接口
## 一次把验收要用的读数交出去。**探针不要自己另算一遍几何**（尺子编错了会伪装成实现错了）。
func probe_state() -> Dictionary:
	var f := {}
	if _fold != null:
		f = _fold.geom()
	var n_total := 0
	var n_clipped := 0
	for r in _roots:
		if is_instance_valid(r):
			n_total += _count_canvas_items(r)
			n_clipped += _count_clipped(r)
	# 折线层上的 `u_fold`（材质里的那份）vs `fold_x(_p)`（线那边算的那份）——
	# 两个数必须一致，不然「线和裁切各走各的」。
	var mat_fold := -4000.0
	if _mat != null:
		mat_fold = float(_mat.get_shader_parameter("u_fold"))
	return {
		"p": _p,
		"t": _t,
		"side": _side,
		"busy": _busy,
		"clip_on": _clip_on,
		"roots": _roots.size(),
		"root_visible": bool(_roots[0].visible) if not _roots.is_empty() else false,
		"n_canvas_items": n_total,
		"n_clipped": n_clipped,
		"mat_fold": mat_fold,
		"fold": f,
		"fold_x_expected": fold_x(_p),
	}


func _count_canvas_items(n: Node) -> int:
	var c := 1 if n is CanvasItem else 0
	for ch in n.get_children():
		if ch is Window:
			continue
		c += _count_canvas_items(ch)
	return c


func _count_clipped(n: Node) -> int:
	var c := 0
	if n is CanvasItem and (n as CanvasItem).material == _mat:
		c = 1
	for ch in n.get_children():
		if ch is Window:
			continue
		c += _count_clipped(ch)
	return c
