extends Node

## AudioManager（Autoload）—— 音频播放中枢（BGM 场景切换 + 五路音量接口）。
##
## 按 `design/音频系统策划案.md` 实现。本轮（2026-10-04「实装进游戏」）补齐两件事：
##   · **场景 → BGM 全量映射**（族 A 七首 + 商业街民谣 + 标题曲）；
##   · **可调音量的接口**（`set_bus_volume` / `get_bus_volume` / `set_muted` / `is_muted`），
##     音量按 **bus 名** 读写，并交给 `Settings` 落盘到 `user://settings.json`。
##
## ▍2026-10-08 一次替换 + 一次新增：
##   · 标题曲占位版 `bgm_title_flute.wav`（`make_test_bgm.py` 纯加法合成）→ 真音源重制版 `bgm_title.wav`
##     （「黎明启程」57.600 s）。替它的直接原因是占位曲自带白噪声底噪，且比族 A 响 12.9 LU。
##   · 新增 `bgm_tutorial.wav`（「旅途开始」53.333 s）→ 接 `tutorial_1.tscn`（此前该场景是静音）。
##     两首与族 A 同响度（−19.63 LUFS），切场景不再跳音量。
##
## 三条关键设计的落地：
##   1. **必须是 autoload**：`change_scene_to_file` 在本帧末销毁整棵旧场景树，
##      BGM 播放器挂场景里必被一起销毁 → 音乐在每个场景交界处被掐断。
##      （与 `SceneTransition` 必须做 autoload 是同一个根因。）
##   2. **冷启动不走 SceneTransition**：`run/main_scene` 由引擎直载，**不发 `scene_entered`**
##      → 标题 BGM 永远不会起（策划案 §4.4）。所以 `_ready()` 末尾自己补一次。
##   3. **同曲不重播**：切场景时若目标曲 == 当前曲 → 什么都不做，
##      这是「音乐跨场景不断」的核心（策划案 §4.3.1）。
##   4. **相位续播**（2026-10-06 追加）：切到**同族**的另一首时，新曲从**上一首此刻的位置**
##      接着放（不是从 0 开始）—— 族 A 七首同长/同速/同调/和声逐小节相同，
##      ⇒ 换曲点听起来是「同一首曲子换编制」，而不是「一首断了、另一首从头起」。
##      详见 `_resume_position()`。
##
## ▍「没有实装的区域先空着」（2026-10-04 用户拍板）
##   `SCENE_BGM` 里没有的场景 → **淡出停止**，**不沿用上一首**。
##   （旧行为是「保持当前音乐不断」，那会让剧院 / 教堂听起来像主城的一部分。
##     2026-10-06 第三波后族 A 覆盖 main/hospital/home/plaza/prison/transport/school/orphanage，
##     2026-10-17 第五波补上 theater（族 A 第九首）⇒ **只剩 church 留空** ——
##     教堂要等它自己的主题曲，不再靠"留空"当占位策略。）
##
## ▍音量的真值在 AudioServer；`_bus_linear` 只是「用户意图」的运行镜像，
##   落盘由 `Settings` 统一负责（它是 settings.json 的唯一出入口）。
##   ⚠️ autoload 顺序：`project.godot` 里 `Settings` 必须排在 `AudioManager` **之前**
##   （现役 Settings 第 14 位、AudioManager 第 15 位），否则 `_ready()` 里读不到已读盘的值。
##
## 音频总线用**运行时建**（AudioServer.add_bus）而不是静态 `.tres`：
## 手写 `.tres` 有污染 uid 缓存的风险，且本项目 15 个 autoload 都在 `project.godot` 声明，
## 运行时建同样可在代码里评审。幂等，已存在则跳过。

const FADE_TIME := 2.0      # 音乐软淡入淡出秒数（策划案 §4.2：画面 0.45s / 音乐 1.5-3s 分层）
const SILENT_DB := -60.0
## 需要**运行时创建**的总线（Master 由引擎自带，不在此列）。
const BUS_NAMES := ["Music", "SFX", "UI", "Ambience"]
## 可调音量全套总线（含 Master）。小写键 ↔ 总线名的大小写见 `_bus_index()`。
const MIX_BUSES := ["Master", "Music", "SFX", "UI", "Ambience"]

## ── 相位续播（2026-10-06 用户提案：「不换场景从 0 开始，而是从对应时间继续」）──
## 「同族」判据 = **路径前缀相同**。族 A（主城 + 七张变奏，将来含各图第二乐章）
## 共享 `family_a_` 前缀 ⇒ 同族；标题「黎明启程」/ 教程「旅途开始」/ 商业民谣各自独立成族
## （前缀天然不同，长度也不同）⇒ 它们之间**不做**相位续播。
const PHASE_FAMILY_PREFIX := "res://audio/bgm/family_a_"
## 同族内还要求**流长一致**（族 A 七首逐字节同长 = 12544044 B）。
## 差得超过这个值 ⇒ 小节对不上，相位续播无意义 ⇒ 回落成从 0 开始并告警。
const PHASE_LEN_TOL := 0.05

## 场景 → BGM 全量映射。
##   ① 标题流：loading / selection（同一首「黎明启程」）—— 100 BPM / 24 小节 / 57.600 s / 长笛+竖琴+大提琴+钢片琴
##   ② 新生教程：tutorial_1（「旅途开始」）—— 108 BPM / 24 小节 / 53.333 s / 竖笛+鲁特琴+小提琴+竖琴+手鼓
##   ③ 族 A：main + 八张变奏（hospital/home/plaza/prison/transport/school/orphanage/theater）——
##      同动机 / 同调 / 同速，整段可衔接（九首逐字节同长 = 3136000 帧）
##   ④ 商业区：独立民谣曲（不属于族 A）
## **未列出的场景 = 该区域还没实装音乐** → `_apply_for_scene()` 淡出停掉（留空）。
## ⚠️ 标题流 / 教程流 / 商业曲各自独立成族（前缀不同）⇒ 互相之间**不**做相位续播，从 0 起。
const SCENE_BGM := {
	# —— 标题流（同一首曲，跨场景不断）——
	"res://scene/loading.tscn": "res://audio/bgm/bgm_title.wav",
	"res://scene/selection.tscn": "res://audio/bgm/bgm_title.wav",
	# —— 新手教程（2026-10-08 新曲「旅途开始」：竖笛 + 鲁特琴 + 小提琴 + 竖琴 + 手鼓）——
	"res://scene/tutorial_1.tscn": "res://audio/bgm/bgm_tutorial.wav",
	# —— 族 A：主城 + 七张变奏（第三波 2026-10-06 追加 school / orphanage）——
	"res://scene/main.tscn": "res://audio/bgm/family_a_main.wav",
	"res://scene/hospital.tscn": "res://audio/bgm/family_a_hospital.wav",
	"res://scene/home.tscn": "res://audio/bgm/family_a_home.wav",
	"res://scene/plaza.tscn": "res://audio/bgm/family_a_plaza.wav",
	"res://scene/prison.tscn": "res://audio/bgm/family_a_prison.wav",
	"res://scene/transport.tscn": "res://audio/bgm/family_a_transit.wav",
	"res://scene/school.tscn": "res://audio/bgm/family_a_school.wav",
	"res://scene/orphanage.tscn": "res://audio/bgm/family_a_orphanage.wav",
	# —— 族 A 第九首：剧院（2026-10-17 第五波接线）——
	#    独奏小提琴主奏 + 长笛休止应答 + 竖琴句末点缀，132 音；71.111 s / −19.63 LUFS，
	#    与另外八首逐字节同长 ⇒ 进剧院走相位续播（同一条曲子换编制），不是从头起。
	#    报告 `design/族A_剧院.md`；素材原稿 `design/audio_preview/scenes_v4/`（已随设计目录瘦身移出工程）
	"res://scene/theater.tscn": "res://audio/bgm/family_a_theater.wav",
	# —— 商业区（独立民谣曲 · 街头手摇风琴圆舞曲 · F 大调 6/8 108 BPM 26.667 s）——
	#    2026-10-08 重做：占位曲 bgm_commercial_folk.wav（正弦合成 · −10.94 LUFS）退场，
	#    换成真音源正式曲（−19.60 LUFS，与族 A 全库对齐）。素材/分轨 → design/audio_preview/commercial/
	"res://scene/commercial.tscn": "res://audio/bgm/bgm_commercial.wav",
}

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _current_path := ""
var _fade_tween: Tween
var _stop_tween: Tween
## 上一次换曲的记录（探针判「相位续播生效没生效」用）：{from,to,mode,resume,prev_pos}
var _last_switch: Dictionary = {}

## 五路「用户意图」音量（线性 0..1），键 = `Settings.AUDIO_KEYS`（小写总线名）。
var _bus_linear: Dictionary = {}
var _muted := false


func _ready() -> void:
	# 与 OverlayRoot / SceneTransition 一致：暂停时也要继续跑补间（否则淡入淡出被冻结）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_player_a = _make_player()
	_player_b = _make_player()
	_active = _player_a
	# Settings 已在本节点之前 _ready（读盘完成），这里把音量/静音灌进 AudioServer
	_apply_settings()
	_preload_sfx()
	EventSignal.scene_entered.connect(_on_scene_entered)
	# 冷启动补一次（见文件头 2.）
	call_deferred("_play_for_current_scene")
	print("[AudioManager] ready. buses=%s mix=%s" % [str(_bus_report()), str(mix_snapshot())])


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p


## 幂等建总线：已存在则跳过，避免重复 add 导致索引漂移。
func _ensure_buses() -> void:
	for bus_name in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _bus_report() -> Dictionary:
	var d := {}
	for bus_name in BUS_NAMES:
		d[bus_name] = AudioServer.get_bus_index(bus_name)
	return d


## 小写键 → AudioServer 总线索引。总线名**大小写敏感**（"Music" ≠ "music"）。
func _bus_index(bus_key: String) -> int:
	match bus_key.to_lower():
		"master":
			return AudioServer.get_bus_index("Master")
		"music":
			return AudioServer.get_bus_index("Music")
		"sfx":
			return AudioServer.get_bus_index("SFX")
		"ui":
			return AudioServer.get_bus_index("UI")
		"ambience":
			return AudioServer.get_bus_index("Ambience")
	return -1


# ---------------------------------------------------------------- 对外接口 · 播放

## 播放 BGM。同曲且正在播 → 直接 return（不重播、不断）。
## ★ 换曲时默认走**相位续播**（见 `_resume_position`）：从上一首此刻的播放位置接着放。
func play_bgm(path: String, fade_time: float = FADE_TIME) -> void:
	if path == _current_path and _active != null and _active.playing:
		print("[AudioManager] 同曲，保持播放（不重播）：%s" % path.get_file())
		return
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("[AudioManager] load 失败：%s（新素材必须先被 Godot 导入）" % path)
		return
	_ensure_looping(stream, path)

	var next: AudioStreamPlayer = _player_b if _active == _player_a else _player_a
	var prev := _active
	var resume := _resume_position(prev, stream, path)   # ⚠️ 必须在 _current_path 改写前调用

	next.stream = stream
	next.volume_db = SILENT_DB
	next.play(resume)

	_current_path = path
	_active = next

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(next, "volume_db", 0.0, fade_time)
	if prev.playing:
		_fade_tween.tween_property(prev, "volume_db", SILENT_DB, fade_time)
		if _stop_tween != null and _stop_tween.is_valid():
			_stop_tween.kill()
		_stop_tween = create_tween()
		_stop_tween.tween_interval(fade_time)
		_stop_tween.tween_callback(prev.stop)

	print("[AudioManager] play_bgm -> %s (fade %.2fs)" % [path.get_file(), fade_time])


## ── 相位续播：算出新曲该从第几秒接着放 ────────────────────────────────────
## 「换场景不从 0 开始，而是从对应时间继续放对应音频」（2026-10-06 用户提案）。
##
## ▍为什么在我们这套素材上成立（是素材保证的，不是运气）
##   · 族 A 七首 WAV **逐字节同长**：12544044 B = 3136000 帧 = 71.111111 s（七首互差 **0 帧**）；
##   · 同 BPM 108 / 同调（G 宫）/ 同 32 小节 / 8 句 × 16 拍；
##   · 和声**逐小节相同** —— 五图变奏与主城都由 `make_melody_liangzhu_v1.CHORD_BARS / CHORD_PC`
##     派生（`make_scene_variants.py` 直接 import 那两个常量）。
##   ⇒ 「同一秒」= 「同一小节 + 同一个和弦 + 同一条乐句位置」。
##     于是把新曲 `play(上一首此刻的位置)`，两条流在输出缓冲里**逐样本对齐**，
##     交叉淡化期间听到的是「同一个和弦在换编制」，不会出现两条不同的和声叠在一起打架。
##
## ▍为什么要加 `get_time_since_last_mix()`
##   `get_playback_position()` 只在**每个混音块之后**更新（Godot 默认 512 帧 ≈ 11.6 ms @44.1k），
##   直接拿它当「此刻」最多差一个混音块。加上「距上次混音的时间」才是**此刻正在混**的位置。
##   ⚠️ 不需要减 `get_output_latency()`：两路流走同一条输出链路，延迟对二者完全相同，
##      做**相对**相位对齐时它会自己抵消；减掉反而会引入一个固定的错位。
##
## ▍回落条件（自动，不静默）
##   · 上一个播放器没在播（冷启动 / 刚从空区域淡出）→ 从 0 开始；
##   · 不同族（标题长笛 ↔ 商业民谣 ↔ 族 A）→ 从 0 开始；
##   · 同族但流长不同（例如把 71.1 s 的单乐章 与 141.7 s 的两乐章版混用）→ 从 0 开始**并告警**。
func _resume_position(prev: AudioStreamPlayer, stream: AudioStream, path: String) -> float:
	var mode := "restart"
	var pos := 0.0
	var prev_pos := -1.0
	if prev != null and prev.playing and prev.stream != null:
		prev_pos = prev.get_playback_position()
		var g_prev := _phase_group(_current_path)
		var same_family := g_prev != "" and g_prev == _phase_group(path)
		if same_family:
			var d_len: float = absf(prev.stream.get_length() - stream.get_length())
			if d_len <= PHASE_LEN_TOL:
				var L: float = stream.get_length()
				var now: float = prev_pos + clampf(AudioServer.get_time_since_last_mix(), 0.0, 0.05)
				pos = fposmod(now, L)
				mode = "phase"
			else:
				push_warning("[AudioManager] 相位续播被拒（同族但流长不同：%.3fs vs %.3fs）→ 从 0 开始：%s"
					% [prev.stream.get_length(), stream.get_length(), path.get_file()])
	_last_switch = {"from": _current_path, "to": path, "mode": mode, "resume": pos, "prev_pos": prev_pos}
	if mode == "phase":
		print("[AudioManager] 相位续播 %s → %s @ %.3fs（上一首此刻 %.3fs，差 %.1f ms）"
			% [_current_path.get_file(), path.get_file(), pos, prev_pos, (pos - prev_pos) * 1000.0])
	return pos


## 相位族：路径前缀相同 = 同族（同速 / 同调 / 同长），只有族内才允许相位续播。
## 族 A = `res://audio/bgm/family_a_*`（主城 + 七张变奏，将来含各图第二乐章 / 两乐章版）。
## ⚠️ 两乐章版（141.667 s）与单乐章（71.111 s）**同前缀但不同长** —— 靠 `PHASE_LEN_TOL` 兜住，
##    两组之间只会在边界处「重新开始」，不会错位续播。
func _phase_group(p: String) -> String:
	return PHASE_FAMILY_PREFIX if p.begins_with(PHASE_FAMILY_PREFIX) else ""


func stop_bgm(fade_time: float = FADE_TIME) -> void:
	if _active == null or not _active.playing:
		_current_path = ""
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var p := _active
	_fade_tween = create_tween()
	_fade_tween.tween_property(p, "volume_db", SILENT_DB, fade_time)
	_fade_tween.tween_callback(p.stop)
	_current_path = ""


func current_bgm_path() -> String:
	return _current_path


func is_bgm_playing() -> bool:
	return _active != null and _active.playing


# ---------------------------------------------------------------- 对外接口 · SFX / UI
## 池上限（`design/音频系统策划案.md` §3.4：demo 取 8）。
## ⚠️ 上限的意义**不是省内存** —— 是防止极端连点下几十个音效齐响把总线推成削波。
const SFX_POOL_SIZE := 8
## 同事件最小重触发间隔（策划案 §3.4 / 设计圣经 §3.6：30-80 ms，取中值）。
## 连点按钮时**丢弃**重复触发，不是排队 —— 排队会让声音滞后于手。
const SFX_RETRIGGER_MS := 50

## 事件名 → 变体文件表（同名多文件 = 随机轮播，破机械重复）。
## 键 = `design/音频设计圣经.md` §3.6 的事件名；素材由 `design/make_ui_sfx.py`
## 用 MuseScore GM 打击乐真音源渲染（15 条 = P0 十项 + 变体）。
const SFX_TABLE := {
	# —— 按钮点击 ——
	"ui_click_primary": [
		"res://audio/ui/ui_click_primary_01.wav",
		"res://audio/ui/ui_click_primary_02.wav",
	],
	"ui_click_secondary": [
		"res://audio/ui/ui_click_secondary_01.wav",
		"res://audio/ui/ui_click_secondary_02.wav",
	],
	# —— 卡牌交互 ——
	"ui_card_pickup": [
		"res://audio/ui/ui_card_pickup_01.wav",
		"res://audio/ui/ui_card_pickup_02.wav",
	],
	"ui_card_place_ok": [
		"res://audio/ui/ui_card_place_ok_01.wav",
		"res://audio/ui/ui_card_place_ok_02.wav",
	],
	"ui_card_reject": ["res://audio/ui/ui_card_reject_01.wav"],
	# —— 流程 ——
	"ui_next_day": ["res://audio/ui/ui_next_day_01.wav"],
	# —— 判定三档 ——
	"ui_verdict_fail": ["res://audio/ui/ui_verdict_fail_01.wav"],
	"ui_verdict_maybe": ["res://audio/ui/ui_verdict_maybe_01.wav"],
	"ui_verdict_pass": ["res://audio/ui/ui_verdict_pass_01.wav"],
	# —— 场景转场（合幕 / 揭幕，与 SceneTransition 的铅笔纸面视觉对齐）——
	"ui_scene_transition_close": ["res://audio/ui/ui_scene_transition_close.wav"],
	"ui_scene_transition_open": ["res://audio/ui/ui_scene_transition_open.wav"],
}

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_started_ms: Array[int] = []      # 每个池成员的起播时刻（oldest-first 抢占用）
var _sfx_last_ms: Dictionary = {}         # 事件名 → 上次触发 ms（重触发闸）
var _sfx_cache: Dictionary = {}           # 路径 → AudioStream（预载，热路径零 load）


## 播放一条 UI 音效（走 `UI` 总线）。`name_or_path` 可以是表里的**事件名**
## （自动随机选变体），也可以直接给 `res://` 路径。
func play_ui(name_or_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	return _play_sfx(name_or_path, "UI", volume_db, pitch)


## 播放一条玩法音效（走 `SFX` 总线）。放卡 / 判定等非 UI 语义走这条。
func play_sfx(name_or_path: String, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	return _play_sfx(name_or_path, "SFX", volume_db, pitch)


## 事件名 → 变体路径（随机轮播）。已经是 `res://` 路径则原样返回。
func _resolve_sfx(name_or_path: String) -> String:
	if name_or_path.begins_with("res://"):
		return name_or_path
	var vs: Array = SFX_TABLE.get(name_or_path, [])
	if vs.is_empty():
		push_warning("[AudioManager] 未知 SFX 事件名：%s" % name_or_path)
		return ""
	return String(vs[randi() % vs.size()])


## 取一个池位：优先空闲，全忙则**抢占最早起播的**（oldest-first）。
## 返回 -1 表示池没建起来。
func _take_sfx_index() -> int:
	if _sfx_pool.is_empty():
		return -1
	var oldest := 0
	for i in _sfx_pool.size():
		if not _sfx_pool[i].playing:
			return i
		if _sfx_started_ms[i] < _sfx_started_ms[oldest]:
			oldest = i
	return oldest


func _play_sfx(name_or_path: String, bus: String, volume_db: float, pitch: float) -> bool:
	var path := _resolve_sfx(name_or_path)
	if path == "":
		return false
	# 同事件最小重触发间隔：**丢弃**（不排队），否则声音会滞后于手
	var now := Time.get_ticks_msec()
	if _sfx_last_ms.has(name_or_path) and now - int(_sfx_last_ms[name_or_path]) < SFX_RETRIGGER_MS:
		return false
	var stream: AudioStream = _sfx_cache.get(path, null)
	if stream == null:
		stream = load(path)
		if stream == null:
			# ⚠️ 新素材没被 Godot 导入时 load() 返回 null，**不报错只静默哑掉**
			push_warning("[AudioManager] SFX 未导入，播放被跳过：%s" % path)
			return false
		_sfx_cache[path] = stream
	var idx := _take_sfx_index()
	if idx < 0:
		return false
	var pl := _sfx_pool[idx]
	pl.stream = stream
	# 只在这块池位**空闲**时改 bus —— 播到一半改会把音效突然改道（策划案 §3.4）
	pl.bus = bus
	pl.volume_db = volume_db
	pl.pitch_scale = pitch
	pl.play()
	_sfx_started_ms[idx] = now
	_sfx_last_ms[name_or_path] = now
	return true


## 预载：把 `SFX_TABLE` 里每条都 load 进缓存 + 建池。
## ⚠️ 必须等 Godot 导入完成后才有资源（新 wav 没导入时这里会 push_error）。
func _preload_sfx() -> void:
	var n := 0
	for key in SFX_TABLE:
		for p in SFX_TABLE[key]:
			if _sfx_cache.has(p):
				continue
			var st: AudioStream = load(p)
			if st == null:
				push_error("[AudioManager] SFX 加载失败：%s（素材要先被 Godot 导入）" % p)
				continue
			_sfx_cache[p] = st
			n += 1
	for i in SFX_POOL_SIZE:
		var pl := AudioStreamPlayer.new()
		pl.name = "Sfx%d" % i
		pl.bus = "UI"
		pl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(pl)
		_sfx_pool.append(pl)
		_sfx_started_ms.append(-1)
	print("[AudioManager] SFX 预载 %d 条，池 %d 位" % [n, _sfx_pool.size()])


## 给探针用的 SFX 状态快照。
func sfx_snapshot() -> Dictionary:
	var playing := 0
	for pl in _sfx_pool:
		if pl.playing:
			playing += 1
	var buses := {}
	for pl in _sfx_pool:
		buses[pl.name] = pl.bus
	return {
		"cached": _sfx_cache.size(),
		"pool": _sfx_pool.size(),
		"playing": playing,
		"table_events": SFX_TABLE.size(),
		"retrigger_ms": SFX_RETRIGGER_MS,
		# 事件名 → 上次触发时刻；探针靠它判「接线点真的调进来了」
		"last": _sfx_last_ms.duplicate(),
		# 每个池位当前挂的总线；探针靠它判「play_ui 走 UI、play_sfx 走 SFX」
		"buses": buses,
	}


# ---------------------------------------------------------------- 对外接口 · 音量

## 调一路音量（线性 0..1）。设置菜单 / 剧本 / 调试一律走这里。
## 立刻送进 AudioServer，同时把「用户意图」交给 `Settings` 落盘（settings.json）。
## `bus_name` 用总线原名（"Master"/"Music"/"SFX"/"UI"/"Ambience"），大小写不敏感。
##
## ⚠️ **每次调用都会落盘一次**（`Settings._save()` = 写 tmp + 读回校验 + rename）。
##    将来接设置菜单滑杆时**不要直接挂在 `value_changed` 上** —— 拖动时会一帧写一次盘；
##    用 `drag_ended` / 松开鼠标时提交，或做 200ms 去抖。
func set_bus_volume(bus_name: String, linear: float) -> void:
	var key := bus_name.to_lower()
	if _bus_index(key) == -1:
		push_warning("[AudioManager] 未知总线：%s（合法：%s）" % [bus_name, str(MIX_BUSES)])
		return
	var v := clampf(linear, 0.0, 1.0)
	_bus_linear[key] = v
	_apply_bus(key)
	Settings.set_audio_volume(key, v)


## 取一路音量（线性 0..1）—— 返回的是**用户意图**（静音不影响这个读数）。
func get_bus_volume(bus_name: String) -> float:
	return float(_bus_linear.get(bus_name.to_lower(), 1.0))


## 一键静音开关。作用于 **Master 总线的 mute 标志**（下游总线都会跟着静），
## 所以不需要记住 `_pre_mute_volume` —— 各总线自身的音量值原样保留。
func set_muted(muted: bool) -> void:
	if muted == _muted:
		return
	_muted = muted
	_apply_bus("master")
	Settings.set_audio_muted(muted)
	print("[AudioManager] 静音 = %s" % str(muted))


func is_muted() -> bool:
	return _muted


## 把一路的线性音量送进 AudioServer。
## ≤0.001 → 直接给该总线打 mute：`linear_to_db(0) == -inf`，各平台对 -inf 的处理不一致。
func _apply_bus(bus_key: String) -> void:
	var idx := _bus_index(bus_key)
	if idx == -1:
		return
	var linear: float = float(_bus_linear.get(bus_key, 1.0))
	var silent := linear <= 0.001
	# ⚠️ 这里必须 `to_lower()`：对外 API 是大小写不敏感的，别在内部留下一个
	#    「传 "Master" 就静默漏掉全局静音」的陷阱（`_bus_index` 已经 lowercase 了）。
	if bus_key.to_lower() == "master":
		silent = silent or _muted
	AudioServer.set_bus_mute(idx, silent)
	if not silent:
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))


## 启动时把 Settings 里存的用户意图灌进 AudioServer。
func _apply_settings() -> void:
	_muted = Settings.is_audio_muted()
	for key in Settings.AUDIO_KEYS:
		_bus_linear[key] = Settings.get_audio_volume(key)
		_apply_bus(key)


## 给探针 / 调试用的混音状态快照（引擎侧真值 + 意图值 + mute 标志）。
func mix_snapshot() -> Dictionary:
	var out := {"muted": _muted, "intent": _bus_linear.duplicate(), "engine": {}}
	var eng: Dictionary = out["engine"]
	for bus_name in MIX_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		eng[bus_name] = {
			"idx": idx,
			"db": AudioServer.get_bus_volume_db(idx) if idx != -1 else -999.0,
			"mute": AudioServer.is_bus_mute(idx) if idx != -1 else true,
		}
	return out


# ---------------------------------------------------------------- 内部接线

## BGM 必须循环 —— 不循环的 BGM 会在放完那一刻静音，而「跨场景不断」当场变成假的
## （只是还没放完而已）。这种坏法**不报错、不崩、当场也听不出来**，只有等到曲子放完
## 才暴露，所以在这里兜一道，并且**大声告警**（不静默修好，否则素材问题永远抓不到）。
##
## ⚠️ 坑：Godot 4 WAV 导入的 `edit/loop_mode` 是 **1-based** 的 ——
##    `0 = Detect From WAV`（读 wav 里的 smpl 块，我们程序生成的 wav 没有 → 等于关闭）、
##    `1 = Disabled`、`2 = Forward`、`3 = Ping-Pong`、`4 = Backward`。
##    写成「直觉上正确的」`1` 会得到 **关闭**，而且 `.import` 里看着像对的。
##    实测：`edit/loop_mode=2` → 资源 `loop_mode=1 (LOOP_FORWARD)`；`=1` → `0`。
func _ensure_looping(stream: AudioStream, path: String) -> void:
	if not (stream is AudioStreamWAV):
		return   # Ogg / MP3 自带 loop 属性，导入时设；不在这里兜
	var w := stream as AudioStreamWAV
	if w.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	push_warning("[AudioManager] BGM 没配循环 → 自动补 Forward，但请去改素材：%s（`edit/loop_mode=2`）" % path)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _on_scene_entered(scene_path: String) -> void:
	_apply_for_scene(scene_path)


func _play_for_current_scene() -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	_apply_for_scene(cs.scene_file_path)


func _apply_for_scene(scene_path: String) -> void:
	if scene_path == "":
		# 空路径 = 调用方没给出场景（正常不该发生）→ 什么都不做，
		# 免得落进下面「未实装」分支把正在放的音乐误停掉。
		return
	var bgm: String = SCENE_BGM.get(scene_path, "")
	if bgm == "":
		# 「没有实装的区域先空着」—— 不沿用上一首。
		if _current_path != "" or is_bgm_playing():
			print("[AudioManager] scene=%s 未实装 BGM → 淡出停止（该区域留空）" % scene_path.get_file())
			stop_bgm()
		else:
			print("[AudioManager] scene=%s 未实装 BGM → 保持静默" % scene_path.get_file())
		return
	print("[AudioManager] scene=%s → %s（当前=%s）"
		% [scene_path.get_file(), bgm.get_file(), _current_path.get_file()])
	play_bgm(bgm)


## 给探针用的状态快照。
##
## `active_stream_len` / `active_loop` 是给探针判「BGM 到底配没配循环」用的：
## 循环没配（loop=0）时曲子放完就静音，跨场景「不断」是假的 —— 只是还没放完而已。
func debug_state() -> Dictionary:
	var stream_len := -1.0
	var loop_mode := -1
	if _active != null and _active.stream != null:
		stream_len = _active.stream.get_length()
		if _active.stream is AudioStreamWAV:
			loop_mode = int((_active.stream as AudioStreamWAV).loop_mode)
	return {
		"current_path": _current_path,
		"active_playing": _active.playing if _active != null else false,
		"active_pos": _active.get_playback_position() if _active != null else -1.0,
		"active_vol_db": _active.volume_db if _active != null else 0.0,
		"active_stream_len": stream_len,
		"active_loop": loop_mode,
		"other_playing": (_player_b if _active == _player_a else _player_a).playing,
		"music_bus_idx": AudioServer.get_bus_index("Music"),
		# 相位续播：上一次换曲是「接着放」还是「从 0 开始」，以及接着放的位置
		"last_switch": _last_switch.duplicate(),
	}
