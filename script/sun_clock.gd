## 太阳时钟（M-SUN1 v2，2026-10-17 用户拍板「文明6 式：只留光影，不做显式太阳」）
##
## ▍定位
##   影子与地图色温的**唯一时间源**。纯装饰、不进存档、不参与任何 gameplay 判定。
##   没有显式太阳精灵（用户明确否掉方案 2）—— 玩家从影子的方向、长短、浓度
##   和地图色温读时间，太阳本身在画面外。
##
## ▍时间模型：cycle ∈ [0, 2)
##   · [0, 1) 白天：0=日出，0.5=正午，1=日落。**走真实时间，10 分钟走完**。
##     走到 1.0 就**停住**（黄昏悬停）—— 回合制里玩家不点「下一天」，时间就不该自己跑。
##     天色停在黄昏本身就是「该过天了」的暗示。
##   · [1, 2) 夜：**不占真实时间**。夜只存在于「下一天」的快进动画里被扫过
##     （night = sin(π·(cycle-1))：日落 0 → 夜深 1 → 次日日出 0，与白天对称）。
##   · cycle 到 2.0 等价于次日的 0.0（mod 2）。
##
## ▍「下一天」快进
##   `fast_forward_to_dawn()`：约 1 秒内把 cycle 从当前值推到 2.0 再归 0 ——
##   影子沿弧快速滑过剩余白天、掠过整个夜、停回清晨。连点安全（旧补间直接杀掉重开）。
##
## ▍影子口径（scene_spot 读取的三个量）
##   · shadow_len()      0.25..1.0  太阳越低影子越长
##   · shadow_alpha()    正午最实 0.28，早晚摊薄 0.12，夜只剩月光 0.05
##   · shadow_skew_dir() -1..1，+1 = 顶端朝屏幕左倒（太阳在东 → 影朝西）
##   昼夜两套参数线性混合，任何 cycle 上都连续，快进时不会跳变。
##
## ▍为什么是 autoload 而不是静态类
##   v1 用「真实时间取模」可以无状态；v2 要支持「下一天快进」和「停在黄昏」，
##   必须有状态 → 变成 autoload Node。⚠️ **autoload 名不能与 class_name 同名**，
##   所以这里**不写 class_name**，调用处一律走单例名 `SunClock.xxx`。
extends Node

## 白天（cycle 0→1）的真实秒数。用户拍板：10 分钟。
const DAY_REAL_SECONDS := 600.0
## 快进回日出的时长（秒）。用户拍板：约 1 秒。
const FF_SECONDS := 1.0
## 夜里的影子参数。
const LEN_MOON := 0.45
const ALPHA_MOON := 0.05
## 白天影子参数：alt=0（贴地平线）与 alt=1（当头）两端。
const LEN_HORIZON := 1.0
const LEN_NOON := 0.25
const ALPHA_HORIZON := 0.12
const ALPHA_NOON := 0.28

## 测试 / 截图用：>=0 时把 cycle 冻结在这个值（0..2），真实时间与快进都不再生效。
var phase_override := -1.0

## 当前进度 0..2。读档后从 0（清晨）重新走 —— 不进存档（已拍板）。
var _cycle := 0.0
var _ff_tween: Tween = null


func _process(delta: float) -> void:
	if phase_override >= 0.0:
		return
	if _ff_tween != null and _ff_tween.is_valid():
		return
	if _cycle < 1.0:
		_cycle = minf(_cycle + delta / DAY_REAL_SECONDS, 1.0)


## 「下一天」按下时调用：约 1 秒滑回次日清晨。
## 挂在 main_ui._on_next_day_pressed 的过天分支里（拦截 return 之后才走到）。
func fast_forward_to_dawn() -> void:
	if phase_override >= 0.0:
		return
	if _ff_tween != null and _ff_tween.is_valid():
		_ff_tween.kill()
	# 已经是清晨（玩家秒点）就不演动画，直接归位。
	if _cycle <= 0.001:
		_cycle = 0.0
		return
	_cycle = minf(_cycle, 1.999)
	_ff_tween = create_tween()
	_ff_tween.tween_method(_set_cycle, _cycle, 2.0, FF_SECONDS) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_ff_tween.tween_callback(func() -> void: _cycle = 0.0)


func _set_cycle(v: float) -> void:
	_cycle = v


## 调试用 / 探针：把 cycle 钉在指定值。
func set_phase_override(c: float) -> void:
	phase_override = c
	if c >= 0.0:
		_cycle = c
		if _ff_tween != null and _ff_tween.is_valid():
			_ff_tween.kill()


## 当前 cycle 0..2。
func cycle() -> float:
	if phase_override >= 0.0:
		return phase_override
	return _cycle


## 太阳高度角 0..1（夜 = 0）。
func sun_altitude() -> float:
	var c := cycle()
	if c >= 1.0:
		return 0.0
	return sin(PI * c)


## 太阳方位 -1..1：-1 = 东（屏幕右），+1 = 西。夜里停在 +1（月光方向）。
func sun_azimuth() -> float:
	return -1.0 + 2.0 * minf(cycle(), 1.0)


## 夜的深度 0..1。白天恒 0；夜里 sin(π·(cycle-1))：刚日落 0 → 夜深 1 → 快天亮 0。
func night_factor() -> float:
	var c := cycle()
	if c < 1.0:
		return 0.0
	return clampf(sin(PI * (c - 1.0)), 0.0, 1.0)


## 影子长度系数 0.25..1.0。
func shadow_len() -> float:
	var day := lerpf(LEN_HORIZON, LEN_NOON, sun_altitude())
	return lerpf(day, LEN_MOON, night_factor())


## 影子浓度。
func shadow_alpha() -> float:
	var day := lerpf(ALPHA_HORIZON, ALPHA_NOON, sun_altitude())
	return lerpf(day, ALPHA_MOON, night_factor())


## 影子倾倒方向：太阳在东 → 影朝西 → 顶点朝屏幕左倒 = +1。
func shadow_skew_dir() -> float:
	return -sun_azimuth()


## ── 地图色温（day_tint 读这个）──────────────────────────
## 正午近乎无色 → 早晚暖橙 → 夜蓝灰。alpha 上限压在 0.13，
## 叠在地图上、不盖 UI —— 只到「读得出天色」的程度，不许变成滤镜。
const TINT_CLEAR := Color(1.0, 0.97, 0.90, 0.0)      # 正午：无
const TINT_DAWN := Color(1.0, 0.72, 0.45, 0.10)      # 清晨/黄昏：暖橙
const TINT_NIGHT := Color(0.55, 0.62, 0.85, 0.13)    # 夜：蓝灰


func tint_color() -> Color:
	var c := cycle()
	var night := night_factor()
	# 白天端：正午(c=0.5) 无色，向两端(c=0 或 1)渐暖。
	var day_edge := 0.0
	if c < 1.0:
		day_edge = 1.0 - sin(PI * c)
	var day := TINT_CLEAR.lerp(TINT_DAWN, clampf(day_edge, 0.0, 1.0))
	return day.lerp(TINT_NIGHT, night)


## 调试用人话标签（探针截图打在日志里）。
func phase_label() -> String:
	var c := cycle()
	if c < 0.15:
		return "清晨"
	elif c < 0.40:
		return "上午"
	elif c < 0.60:
		return "正午"
	elif c < 0.85:
		return "午后"
	elif c < 1.0:
		return "黄昏"
	return "夜"
