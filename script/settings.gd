## 全局设置单例（Autoload：Settings）。
##
## 当前管两项：
##   ① 对话框正文 / 触发器右侧正文的文字大小（保持一致且可持久化调节）；
##   ② 音频五路音量（Master / Music / SFX / UI / Ambience）+ 全局静音开关。
##
## ▍存储：`user://settings.json`（**独立于存档**，2026-10-04 与用户拍板）
##   老版本存的是 `user://settings.cfg`（ConfigFile，只有 text.font_size）。
##   `_load()` 里做一次性迁移：读老 cfg → 落 json → **确认 json 存在后立刻删 cfg**。
##   写盘失败就不删，下次启动重试 —— 不会丢用户已经调过的字号。
##
## ▍S1 原子写（**不可协商项**）：`settings.json.tmp` 写全 → **读回逐字节校验** → rename 覆盖。
##   直接覆盖真文件的话，进程若在 store_string 中途死掉，会留下半截 JSON；
##   下次启动 `JSON.parse_string` 返回 null → 用户所有设置被打回默认（**静默丢失**）。
##
## ▍音量按 **bus 名（String）** 存，不按索引：总线索引会随 AudioServer 重建而漂移，
##   存索引等于把「Music 变成 SFX」这种错位写进用户的设置文件。
##   键名由《音频系统策划案》§6.2 钉死（扁平，不是嵌套）：
##   ```json
##   { "version": 1,
##     "text":  { "font_size": 18 },
##     "audio": { "master_volume": 1.0, "music_volume": 0.8, "sfx_volume": 0.8,
##                "ui_volume": 0.8, "ambience_volume": 0.8, "muted": false } }
##   ```
##
## ▍职责边界（《音频系统策划案》§6.4）：本单例 = 设置的**真源 + 唯一写入方**；
##   把音量/静音**应用到 AudioServer** 的是 `AudioManager`。
##   对外入口是 `AudioManager.set_bus_volume()` / `set_muted()`，它应用后回调本单例落盘。
##
## ▍对外 API 的兼容约束（**别改名**，调用方如下）：
##   `text_font_size` / `text_font_size_changed` / `set_text_font_size()`
##     → components/settings_menu.gd、components/trigger_popup.gd、components/dialogue_ui.gd
##
## 不声明 class_name —— 注册为 Autoload 后，全局名 `Settings` 即指向本单例实例。
extends Node

signal text_font_size_changed(size: int)
signal audio_volume_changed(bus_key: String, linear: float)
signal audio_muted_changed(muted: bool)

const SETTINGS_PATH := "user://settings.json"
const TMP_PATH := "user://settings.json.tmp"
## 老版本的设置文件（ConfigFile）。迁移完即删，之后不再读写。
const LEGACY_CFG_PATH := "user://settings.cfg"

const DEFAULT_FONT_SIZE := 18
const MIN_FONT_SIZE := 12
const MAX_FONT_SIZE := 32

## 五个音量键 —— **小写**，与 AudioManager 的总线名（Master/Music/SFX/UI/Ambience）一一对应。
## JSON 键名 = `audio.<key>_volume`（**由《音频系统策划案》§6.2 表钉死**，别自己改成嵌套结构）。
const AUDIO_KEYS := ["master", "music", "sfx", "ui", "ambience"]
const DEFAULT_AUDIO := {
	"master": 1.0, "music": 0.8, "sfx": 0.8, "ui": 0.8, "ambience": 0.8,
}

## 当前文字大小（对话框正文与触发器右侧正文共用，保证「一致」）。
var text_font_size: int = DEFAULT_FONT_SIZE
## 五路音量（线性 0..1）。真值在 AudioServer，这里只是「用户意图」的持久化副本。
var audio_volumes: Dictionary = DEFAULT_AUDIO.duplicate()
var audio_muted: bool = false


func _ready() -> void:
	_load()


# ================================================================ 读取 / 迁移

func _load() -> void:
	var had_json := FileAccess.file_exists(SETTINGS_PATH)
	var ok := had_json and _read_json()
	if not ok and FileAccess.file_exists(LEGACY_CFG_PATH):
		_read_legacy_cfg()      # 只带得走 text.font_size
		_save()                 # 立刻落成 json（音频项取默认值）
	elif not ok:
		# §5.4 流程第 3 步 + 失败回退表：
		#   ① json 存在但坏了（且没有老 cfg 可迁）→ 用默认值**重建**，别一直留着坏文件；
		#   ② 干净首次启动（json / cfg 都没有）→ 也落一份默认 json，让真源从一开始就存在。
		if had_json:
			push_warning("[Settings] %s 已损坏，用默认值重建" % SETTINGS_PATH)
		else:
			print("[Settings] 首次启动：写入默认 %s" % SETTINGS_PATH)
		_save()
	_migrate_delete_legacy()


## S2 · **删 cfg 之前的逐字段读回校验**（策划案 §5.4 列为「必需」）。
##
## 与 `_save()` 里对 tmp 的**逐字节**校验不同：这一步校验的是 **rename 之后的真文件**，
## 证明「即将删掉 cfg 的那一刻，json 真的完整可用」，而不是「写调用返回了 OK」。
## 校验不过 → 调用方**不删 cfg**，下次启动重试（幂等）。
func verify_settings_file() -> bool:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(v) != TYPE_DICTIONARY:
		push_warning("[Settings] S2 校验失败：%s 读不回 / 不是合法 JSON" % SETTINGS_PATH)
		return false
	var d: Dictionary = v

	var t: Variant = d.get("text", {})
	if typeof(t) != TYPE_DICTIONARY \
			or _as_int((t as Dictionary).get("font_size", -1)) != text_font_size:
		push_warning("[Settings] S2 校验失败：text.font_size 与内存值（%d）不一致" % text_font_size)
		return false

	var a: Variant = d.get("audio", {})
	if typeof(a) != TYPE_DICTIONARY:
		push_warning("[Settings] S2 校验失败：缺 audio 段")
		return false
	var ad: Dictionary = a
	for k in AUDIO_KEYS:
		var jkey := _audio_json_key(k)
		var raw: Variant = ad.get(jkey)
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			push_warning("[Settings] S2 校验失败：缺音量键 %s" % jkey)
			return false
		if absf(float(raw) - get_audio_volume(k)) > 1e-6:
			push_warning("[Settings] S2 校验失败：%s 落盘 %.4f ≠ 内存 %.4f"
				% [jkey, float(raw), get_audio_volume(k)])
			return false
	if typeof(ad.get("muted")) != TYPE_BOOL or bool(ad.get("muted")) != audio_muted:
		push_warning("[Settings] S2 校验失败：audio.muted 与内存值不一致")
		return false
	return true


## 读 settings.json。返回 false = 文件不存在 / 空 / 不是合法 JSON 对象（调用方走老 cfg 兜底）。
func _read_json() -> bool:
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	if text == "":
		push_warning("[Settings] %s 读不出来（空文件 / 权限），改用默认值" % SETTINGS_PATH)
		return false
	var v: Variant = JSON.parse_string(text)
	if typeof(v) != TYPE_DICTIONARY:
		push_warning("[Settings] %s 解析失败（不是合法 JSON 对象），改用默认值" % SETTINGS_PATH)
		return false
	var d: Dictionary = v

	var t: Variant = d.get("text", {})
	if typeof(t) == TYPE_DICTIONARY:
		text_font_size = clampi(
			_as_int(t.get("font_size", DEFAULT_FONT_SIZE)), MIN_FONT_SIZE, MAX_FONT_SIZE)

	var a: Variant = d.get("audio", {})
	if typeof(a) == TYPE_DICTIONARY:
		var ad: Dictionary = a
		for k in AUDIO_KEYS:
			var raw: Variant = ad.get(_audio_json_key(k))
			# 只在数值类型上取值 —— 字符串 / null / 字典一律忽略，回落到默认值
			if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
				audio_volumes[k] = clampf(float(raw), 0.0, 1.0)
		var m: Variant = ad.get("muted")
		if typeof(m) == TYPE_BOOL:
			audio_muted = bool(m)
	return true


## 小写音量键 → JSON 键名（`music` → `music_volume`）。**唯一的一处映射**，读写共用。
func _audio_json_key(bus_key: String) -> String:
	return "%s_volume" % bus_key


func _read_legacy_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(LEGACY_CFG_PATH) != OK:
		return
	text_font_size = clampi(
		_as_int(cfg.get_value("text", "font_size", DEFAULT_FONT_SIZE)), MIN_FONT_SIZE, MAX_FONT_SIZE)
	print("[Settings] 读到老设置 %s（text.font_size=%d），将迁移到 %s"
		% [LEGACY_CFG_PATH, text_font_size, SETTINGS_PATH])


## 迁移收尾：**json 存在且通过 S2 逐字段读回校验，才删 cfg**（策划案 §5.4 的 S2 + S3）。
## 任一不过 → **保留 cfg**、下次启动重试（幂等）。
## 绝不出现「cfg 已经删了，而 json 其实不可用」—— 那一来回退层就真没了。
func _migrate_delete_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_CFG_PATH):
		return
	if not FileAccess.file_exists(SETTINGS_PATH):
		push_warning("[Settings] json 没落盘成功，暂时保留 %s，下次启动重试迁移" % LEGACY_CFG_PATH)
		return
	if not verify_settings_file():
		push_warning("[Settings] S2 未通过 → 保留 %s，下次启动重试迁移" % LEGACY_CFG_PATH)
		return
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_CFG_PATH))
	if err == OK:
		print("[Settings] 迁移完成：%s → %s（已删除旧 cfg）" % [LEGACY_CFG_PATH, SETTINGS_PATH])
	else:
		push_warning("[Settings] 旧 cfg 删除失败 err=%d，下次启动重试" % err)


## JSON 里的数字一律是 float；这里统一收敛成 int 且**不信任类型**（脏值回默认）。
func _as_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			return int(v)
		TYPE_FLOAT:
			return int(round(float(v)))
		TYPE_BOOL:
			return 1 if bool(v) else 0
		_:
			return DEFAULT_FONT_SIZE


# ================================================================ 文字大小（API 保持不变）

## 调节文字大小。钳制到 [12, 32]，与当前值相同则跳过（不触发信号、不写盘）。
func set_text_font_size(value: int) -> void:
	var v := clampi(int(value), MIN_FONT_SIZE, MAX_FONT_SIZE)
	if v == text_font_size:
		return
	text_font_size = v
	_save()
	text_font_size_changed.emit(text_font_size)


# ================================================================ 音频音量 / 静音

## 取某路音量的「用户意图」值（线性 0..1）。键取 AUDIO_KEYS（小写总线名）。
func get_audio_volume(bus_key: String) -> float:
	return float(audio_volumes.get(bus_key.to_lower(), 1.0))


## 记下某路音量并落盘。钳制 0..1；与当前值相同则跳过（不写盘）。
## ⚠️ 真正把音量送进 AudioServer 的是 `AudioManager.set_bus_volume()` —— 本单例只管「存」。
func set_audio_volume(bus_key: String, linear: float) -> void:
	var k := bus_key.to_lower()
	if not AUDIO_KEYS.has(k):
		push_warning("[Settings] 未知音量键：%s（合法：%s）" % [bus_key, str(AUDIO_KEYS)])
		return
	var v := clampf(linear, 0.0, 1.0)
	if is_equal_approx(get_audio_volume(k), v):
		return
	audio_volumes[k] = v
	_save()
	audio_volume_changed.emit(k, v)


func is_audio_muted() -> bool:
	return audio_muted


func set_audio_muted(muted: bool) -> void:
	if muted == audio_muted:
		return
	audio_muted = muted
	_save()
	audio_muted_changed.emit(audio_muted)


## 给探针 / 调试用的快照。
func audio_snapshot() -> Dictionary:
	return {
		"volumes": audio_volumes.duplicate(),
		"muted": audio_muted,
		"path": SETTINGS_PATH,
	}


# ================================================================ 落盘（S1 原子写）

func _snapshot() -> Dictionary:
	var audio := {}
	for k in AUDIO_KEYS:
		audio[_audio_json_key(k)] = float(audio_volumes.get(k, 1.0))
	audio["muted"] = audio_muted
	return {
		"version": 1,
		"text": {"font_size": text_font_size},
		"audio": audio,
	}


## S1 原子写：tmp 写全 → **读回逐字节校验** → rename 覆盖真文件。
## 任一步失败都**不动真文件**（宁可这次改动没存上，也不能让用户已有的设置变成半截）。
func _save() -> bool:
	var json := JSON.stringify(_snapshot(), "\t")

	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Settings] 打不开临时文件 %s (err=%d)"
			% [TMP_PATH, FileAccess.get_open_error()])
		return false
	f.store_string(json)
	f.flush()
	f.close()

	var back := FileAccess.get_file_as_string(TMP_PATH)
	if back != json:
		push_warning("[Settings] 临时文件读回校验不一致（写 %d 字符 / 读回 %d 字符），放弃本次保存"
			% [json.length(), back.length()])
		return false

	var from := ProjectSettings.globalize_path(TMP_PATH)
	var to := ProjectSettings.globalize_path(SETTINGS_PATH)
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		# 少数平台 rename 不覆盖已存在的目标 → 退一步：先删真文件再 rename。
		# ⚠️ **只删文件，绝不递归删目录** —— `DirAccess.remove_absolute()` 对目录是**递归删除**，
		#    一旦 `to` 因为任何原因是个目录（实测可复现），会把整棵目录树**静默**删掉。
		#    宁可本次保存失败（真文件原样不动、tmp 留着），也不做范围失控的删除。
		if DirAccess.dir_exists_absolute(to):
			push_warning("[Settings] 落盘失败：%s 是个目录，不敢删 —— 本次不保存（原文件未动）"
				% SETTINGS_PATH)
			return false
		push_warning("[Settings] rename 不覆盖已存在目标 → 退化为「先删后 rename」（非原子窗口）")
		DirAccess.remove_absolute(to)
		err = DirAccess.rename_absolute(from, to)
	if err != OK:
		push_warning("[Settings] rename 落盘失败 %s → %s (err=%d)"
			% [TMP_PATH, SETTINGS_PATH, err])
		return false
	return true
