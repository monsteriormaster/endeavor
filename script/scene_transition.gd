extends CanvasLayer

## 场景过场统一入口（autoload `SceneTransition`）—— M-ANI2 v3「原场景淡出 → 新场景淡入」。
##
## ▍要解决的问题
##   此前 `change_scene_to_file` 是硬切，画面「闪一下」就换场。玩家点的是地图上某个图标，
##   却没有任何过渡。
##
## ▍v3 为什么又改（用户原话：「点击后原场景淡出，新场景淡入」）
##   v1 是一块近黑墨渍从图标处扩散 —— 被否：「不好看，动画要符合我的游戏的风格，自然不突兀」。
##   v2 换成「铅笔从图标处涂开 → 铺满方格制图纸 → 整张纸被抽走」——
##     材质对了，但仍然有三个「动作」（涂开 / 停留 / 抽走），而用户要的只是**淡出淡入**。
##   v3 把动作全删掉，只留透明度变化，而且**中间不插任何颜色**：
##
##     ① 点击瞬间抓下**原场景当前这一帧**（`get_viewport().get_texture().get_image()`）
##     ② 换场 —— 新场景在这张快照底下建好，玩家看不到
##     ③ 快照不透明度 1→0 淡出 ＝ 新场景同时淡入
##
##   全程看到的只有「两张彩铅画在互相溶解」，**没有引入任何新材质** ——
##   这是最不可能再被说「突兀」的做法：连一块色块都没有。
##
## ▍为什么必须「抓快照」，不能只做一次颜色淡出
##   `change_scene_to_file` 是**原子替换**：旧场景在本帧末就被销毁，屏幕上不可能同时存在两个场景。
##   想做「原场景淡出」就必须先把旧场景**变成一张图**留下来，否则只能淡出到某个颜色
##   —— 那就又变成一块遮罩了，正是 v1/v2 挨批的同一个毛病。
##
## ▍用法
##   SceneTransition.change_scene("res://scene/theater.tscn")
##   SceneTransition.change_scene_flip("res://scene/main.tscn")   # 翻页版（主界面三颗按钮走这条）
##   SceneTransition.flip_cover(func(): return SaveLoader.load_game())  # 换场景的手不是自己时用这条
##   SceneTransition.is_busy()            # 过场中（此时输入被吞）
##   ⚠️ 过场中再次请求切换不会丢：排队一次，等本次收尾后自动接上（2026-10-25）。
##   SceneTransition.last_capture_ms()    # 上一次抓帧耗时（诊断用）
##
## ▍翻页过场（v4，2026-10-06）—— 与 `components/settings_menu.gd` 同一套几何
##   用户口径：「主界面成就、新的游戏、继续游戏，也做同样的动画」。
##   做法与 v3 只差「怎么把旧场景弄走」：
##     ① 抓下原场景这一帧（同一个 `_capture()`），**当成一页纸**贴在最上面；
##     ② `change_scene_to_file` → 新场景在纸底下建好（玩家看不到，同 v3）；
##     ③ 折线**左→右**扫过，纸从左往右消失，露出新场景。
##   几何 / 时长 / 缓动全部来自 `script/paper_flip.gd`，只有 `u_side` 不同：
##     · 设置页：`+1`（折线左侧是新翻进来的那一页）
##     · 换场景：`-1`（纸在折线右侧，折线扫过时它被揭掉）
##   两条路径的**边界线逐像素重合** ⇒ 观感是同一个动作。
##   ⚠️ 不要在这里自己写一遍折线/缓动 —— 两处各写一份就等着飘。
##
## ▍为什么「继续游戏」不直接调 change_scene_flip
##   读档换场景那一步在 `SaveLoader.load_game()` 里（它会自己 `change_scene_to_file`），
##   而**抓帧必须发生在换场景之前**。所以留了 `flip_cover(action)`：
##   抓帧 → 调 action（让它去换场景）→ 翻页揭开。action 返回 `false` 表示「没成事」
##   （比如读档失败、场景不存在）⇒ 不演那 0.5s 的哑剧，直接收摊。
##
## ▍契约（《地图场景跳转策划案》§5 / D-S3 / D-S4）
##   内部顺序固定为：抓帧 → `change_scene_to_file` → 发 `scene_entered` → 淡出/翻页。
##   `scene_entered` 必须在 `change_scene_to_file` 之后**立即**发（新场景 `_ready` 在下一帧）。
##   切场景失败 → `push_error` + 立刻收干净，**不得留在快照里**（同 D-S1 降级原则）。
##
## ▍为什么整条时序都收在这个 autoload 里，而不留在 `scene_spot.gd`
##   `change_scene_to_file` 会在本帧末销毁旧场景。若在 `scene_spot` 里 `await` 之后再收尾，
##   协程会随旧场景一起被销毁 —— 快照永远盖着，表现为「一点就卡死」。autoload 不随场景
##   销毁，`change_scene()` 整段都在这里跑，天然免疫。

## 快照层号。压过 OverlayRoot 的教学层（100），保证过场期间连教学高亮都被盖住。
const LAYER := 120
## 淡出时长。淡出与淡入是**同一件事**（同一个 alpha），所以只有一个时长。
## 取 0.45s：够看清「溶解」这个动作，又不至于让人干等。
const FADE_TIME := 0.45
## 抓帧看门狗的时限（秒）。`RenderingServer.frame_post_draw` 在窗口最小化 / 被完全遮挡时
## 可能长时间不来 —— 无限等就把 `_busy` 钉死在 true，玩家看到的是「点地图图标没反应」。
## 正常抓帧耗时 < 50ms（`last_capture_ms()` 可查），2s 已经极宽。
const CAPTURE_TIMEOUT := 2.0

var _snap: TextureRect = null
## 翻页层（折线 + 排线影 + 裁切材质）。挂在快照**之上**，是 `_snap` 的兄弟。
var _flip: PaperFlip = null
var _busy: bool = false
## 过场进行中被挡下的那一次切换（Callable）。排队**只留最后一次** —— 连点两个图标 = 去后点的那里。
var _queued_change: Callable = Callable()
## 抓帧令牌：每次过场自增。晚醒的协程拿旧令牌一比就知道自己该作废。
var _capture_token: int = 0
## 被看门狗判死的那个令牌号（-1 = 没有）。
var _aborted_token: int = -1
## 上一次抓帧耗时（毫秒）。抓帧是 GPU→CPU 回读，一次性开销，会卡住当帧，
## 留个读数，出问题时能立刻判断是不是它。初始 -1 = 还没抓过。
var _last_capture_ms: float = -1.0


func _ready() -> void:
	layer = LAYER
	# 过场期间即使树被暂停也要能跑完，否则会永远停在快照里
	process_mode = Node.PROCESS_MODE_ALWAYS

	_snap = TextureRect.new()
	_snap.name = "SceneSnapshot"
	# 快照就是整屏的一帧图，铺满整个视口；窗口大小变了也跟着拉伸
	_snap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_snap.stretch_mode = TextureRect.STRETCH_SCALE
	# 过场期间吃掉一切点击，防止连点两个图标
	_snap.mouse_filter = Control.MOUSE_FILTER_STOP
	_snap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_snap.visible = false
	add_child(_snap)

	# 翻页层必须排在快照**之后**（同层 CanvasLayer 里后加的画在上面）。
	_flip = PaperFlip.new()
	_flip.name = "Flip"
	add_child(_flip)
	# 🔴 快照的可见性**只由本文件收放**（`change_scene` / `flip_cover` 置 true，`_finish()` 置 false）。
	#    必须关掉 PaperFlip 那套「按 p 定页根可见性」—— 见 paper_flip.gd::manage_visibility：
	#    它在 side=-1、p=0 时会把页根判成「可见」，于是下面那句 `set_side(-1.0)`
	#    会把这张**空贴图的全屏 STOP 遮罩一直点亮**，全工程按钮从此点不动（2026-10-06 实测）。
	#    ⚠️ 必须在 `setup()` 之前设：`setup()` 里就有一发 `_set_p()` 会立刻刷可见性。
	_flip.manage_visibility = false
	# 快照就是那一页纸；`-1` = 保留折线右侧 ⇒ 折线扫过 = 把它从左往右揭掉。
	_flip.setup([_snap])
	_flip.set_side(-1.0)
	# 收尾对齐：此刻没有任何过场在跑 ⇒ 遮罩必须是灭的（构造时已是 false，这里显式钉一次）。
	_snap.visible = false


## 过场是否正在进行。进行中再次调用 change_scene 会被忽略（不是排队）。
func is_busy() -> bool:
	return _busy


## 上一次抓帧耗时（毫秒）。-1 表示还没抓过。
func last_capture_ms() -> float:
	return _last_capture_ms


# ============================================================
#  公共 API
# ============================================================

## 带过场切场景。
##
## `_focus_uv` 是为了兼容旧调用方的签名而保留的（`scene_spot` 仍会传 `focus_point()`）——
## v3 的交叉溶解没有「从哪一点铺开」这回事了，**这个参数不再影响任何画面**。
func change_scene(path: String, _focus_uv: Vector2 = Vector2(-1.0, -1.0)) -> void:
	if _busy:
		# 2026-10-25：原先是静默丢弃（只 push_warning），连续两次切换会「点了没反应」。
		# 改成排队一次：这一次过场收尾时 `_finish()` 会把它接上。
		push_warning("SceneTransition: 过场进行中，排队一次 → %s" % path)
		_queued_change = func() -> void: change_scene(path, _focus_uv)
		return
	if path.is_empty():
		push_error("SceneTransition: 空路径，忽略")
		return

	_busy = true
	# 合幕音（设计圣经 §3.6 `ui_scene_transition`）：纸面盖住旧场景的那一刻。
	# 放在 `_capture()` 的 await **之前** —— 点下去立刻响，不等抓帧那一帧。
	AudioManager.play_sfx("ui_scene_transition_close")

	# ① 抓下原场景当前这一帧。抓不到就退化成硬切（_capture 里已告警），
	#    但契约（换场 / 发信号）仍要落地。
	_capture_token += 1
	var my_token := _capture_token
	var tex := await _capture(my_token)
	# 被看门狗判死（抓帧超时）或已被更新的一次取代 ⇒ 本次作废，绝不能再去换场。
	if my_token != _capture_token or my_token == _aborted_token:
		return
	if tex != null:
		_snap.texture = tex
		_snap.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_snap.visible = true

	# ② 换场。新场景在这张快照底下建起来，玩家看到的一直是快照。
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneTransition: 切场景失败 %s（err=%d），停留原地" % [path, err])
		_finish()
		return
	# D-S4：契约要求紧接着 broadcast，不能挪到淡出之后
	EventSignal.scene_entered.emit(path)

	# 新场景的节点要到下一帧 _ready 才建好。这两帧是在快照底下等的，
	# 玩家看不到 —— 也正好把读盘 / 初建的耗时藏进过场里。
	await get_tree().process_frame
	await get_tree().process_frame

	# ③ 快照淡出 = 新场景淡入（同一件事，一个 alpha 管两头）
	# 揭幕音：新场景露出。与上面「合幕」成对 —— 设计圣经 §3.6 这条标了「×2」。
	AudioManager.play_sfx("ui_scene_transition_open")
	if _snap.visible:
		var tw := create_tween()
		# 交叉溶解要的是**两端都平滑地慢下来**，所以用 EASE_IN_OUT：这里没有位移，
		# 不存在「起步要立刻有动作」的问题，对称的溶解才是这种转场的正常观感。
		# （与 §5.1「合幕缓动不能用 EASE_IN」不矛盾 —— 那条针对**半径增长**这类有位移的
		#   动作：t⁴ 会让它前半段几乎不动、后半段猛冲。）
		tw.tween_property(_snap, "modulate:a", 0.0, FADE_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished

	_finish()


## 带**翻页**过场切场景。与 `change_scene` 同一份契约，只是把「溶解」换成「翻页」。
##
## 主界面「新的游戏 / 继续游戏」走这条（用户口径：和设置页同一个动画）。
func change_scene_flip(path: String) -> void:
	if path.is_empty():
		push_error("SceneTransition: 空路径，忽略")
		return
	# 不 await：`flip_cover` 是协程，跑完才是它自己的事；本 autoload 不随场景销毁，
	# 所以它一定跑得完（这正是把整条时序收在这里的原因）。
	flip_cover(func() -> bool:
		var err := get_tree().change_scene_to_file(path)
		if err != OK:
			push_error("SceneTransition: 切场景失败 %s（err=%d），停留原地" % [path, err])
			return false
		# D-S4：契约要求紧接着 broadcast，不能挪到翻页之后
		EventSignal.scene_entered.emit(path)
		return true)


## 通用「翻页遮住」过场：抓这一帧当纸 → 调 `action`（它负责换场景）→ 折线左→右揭开新场景。
##
## `action` 返回 **`false`** 表示「没成事」⇒ 不作动画，直接收摊（避免演一场 0.5s 的哑剧）。
## 返回其它东西（含 `null`）都当成功 —— 这条约定是为了让 `SaveLoader.load_game()` 这种
## 「返回 bool 但不认识本过场」的既有函数能被直接塞进来。
func flip_cover(action: Callable) -> void:
	if _busy:
		push_warning("SceneTransition: 过场进行中，翻页排队一次")
		_queued_change = func() -> void: flip_cover(action)
		return
	if not action.is_valid():
		push_error("SceneTransition: flip_cover 收到无效 Callable")
		return

	_busy = true
	AudioManager.play_sfx("ui_scene_transition_close")

	# ① 抓下原场景当前这一帧。抓不到就退化成硬切（_capture 里已告警），但契约仍要落地。
	_capture_token += 1
	var my_token := _capture_token
	var tex := await _capture(my_token)
	if my_token != _capture_token or my_token == _aborted_token:
		return
	if tex == null:
		var r0: Variant = action.call()
		_finish()
		return
	_snap.texture = tex
	_snap.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_snap.visible = true
	# ⚠️ 这里**故意不挂裁切**：接下来那两帧本来就是「整屏都是旧场景」，纸还没开始翻。
	#    裁切由 `_flip.play()` 自己挂（它在 p=0 时保留折线右侧 = 整屏，观感无跳变）。

	# ② 换场。新场景在这张纸底下建起来，玩家看到的还是旧场景那一帧。
	var result: Variant = action.call()
	if result is bool and not bool(result):
		_finish()                 # 没成事 ⇒ 别演哑剧
		return

	# 新场景的节点要到下一帧 _ready 才建好。这两帧是在纸底下等的，
	# 玩家看不到 —— 也正好把读盘 / 初建的耗时藏进过场里。（同 v3）
	await get_tree().process_frame
	await get_tree().process_frame

	# ③ 折线左→右扫过，纸被揭掉 = 新场景露出来。
	AudioManager.play_sfx("ui_scene_transition_open")
	_flip.play(0.0, 1.0, _finish)


# ============================================================
#  内部
# ============================================================

## 抓下「原场景当前这一帧」。
## ⚠️ 必须先 `await RenderingServer.frame_post_draw`：不等的话拿到的是上一帧（甚至半成品帧）。
##    代价是抓帧要等这一帧画完，所以整段过场晚一帧起手，肉眼无感。
func _capture(token: int) -> Texture2D:
	# 看门狗：`frame_post_draw` 在窗口最小化 / 被完全遮挡时可能长时间不来。
	# 真等到它就把 `_busy` 钉死了（玩家那边是「点了图标没反应」），所以超时直接收尾。
	# `token` 保证晚醒的旧协程不会去动新的一次过场。
	var tree := get_tree()
	if tree != null:
		var wd := tree.create_timer(CAPTURE_TIMEOUT)
		wd.timeout.connect(func() -> void:
			if token != _capture_token or not _busy:
				return
			_aborted_token = token
			push_warning("SceneTransition: 抓帧超时 %.1fs，放弃本次过场（不让 _busy 卡住）" % CAPTURE_TIMEOUT)
			_finish())
	await RenderingServer.frame_post_draw
	if token != _capture_token or token == _aborted_token:
		return null
	var t0 := Time.get_ticks_usec()

	var vp := get_viewport()
	if vp == null:
		push_warning("SceneTransition: 取不到 viewport，过场退化为硬切")
		return null
	var vtex := vp.get_texture()
	if vtex == null:
		push_warning("SceneTransition: 取不到 viewport 贴图，过场退化为硬切")
		return null
	var img := vtex.get_image()
	if img == null or img.is_empty():
		push_warning("SceneTransition: 抓不到画面（dummy 渲染器？），过场退化为硬切")
		return null

	_last_capture_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return ImageTexture.create_from_image(img)


## 收尾：快照藏起来并释放贴图，解锁。**任何路径（含失败）都必须走到这里**，
## 否则会停在「快照一直盖着」的状态 —— 就是 v1 那个「一点就卡死」的病。
func _finish() -> void:
	_snap.visible = false
	_snap.texture = null
	_busy = false
	# 接上排队的那一次（只留最后一次）。deferred 调用 —— 别在 tween 回调栈里再起一条协程。
	if _queued_change.is_valid():
		var next := _queued_change
		_queued_change = Callable()
		next.call_deferred()


## 探针接口：一次把验收要用的读数交出去（探针不要自己另算几何）。
func probe_state() -> Dictionary:
	return {
		"busy": _busy,
		"snap_visible": _snap != null and _snap.visible,
		"snap_texture": _snap != null and _snap.texture != null,
		"snap_clipped": _snap != null and _snap.material != null,
		"flip_p": _flip.p() if _flip != null else -1.0,
		"flip": _flip.probe_state() if _flip != null else {},
		"last_capture_ms": _last_capture_ms,
	}
