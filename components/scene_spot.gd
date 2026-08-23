"""
场景点 - 地图中用于跳转地图的区块
使用方法：
在检查器中设定spot_name,按需求设定max_size,min_size,ordinary

本版（v0.2 范围，D-S1/D-S3/D-S4/D-S6）一次性落地：
- D-S1：spots.json 缺 icon/path 或加载失败 → 降级隐藏 + push_warning，不崩溃。
- D-S3：press 先写 Player.path（回档锚点），对齐 selection/main_ui 既有约定。
- D-S4：切场景后发 EventSignal.scene_entered（自由探索也广播进入事件）。
- D-S6：visible_if / visible_if_method / locked / locked_description 门控，
        由 Player.player_tags 派生，随剧情解锁/锁定。
"""

extends Button

const SPOTS = "res://resoures/spots.json" 

var info := {}
var icon_texture: Texture2D

@export var spot_name: String
@export var max_size: Vector2 = Vector2(100, 100)  # 最大宽高
@export var min_size: Vector2 = Vector2(50, 50)    # 最小宽高
@export var ordinary := Vector2(120, 120)

@onready var sprite = $Sprite2D
@onready var container = $PanelContainer
@onready var label = $PanelContainer/Label

## 门控结果缓存，供调试/测试读取（D-S6）
var is_locked: bool = false
var is_hidden_by_gate: bool = false

## 测试用 seam：为 true 时 _go_to_scene 只写 path + 发 scene_entered，
## 不真正切场景（便于 headless/编辑器内安全验证 D-S3/D-S4，默认 false 零影响）。
var _test_no_swap: bool = false


func _ready():
	setup()


func setup():
	# 每次重进地图都要从当前 Player 状态重新结算，先复位门控态
	visible = true
	disabled = false
	is_locked = false
	is_hidden_by_gate = false

	var file := FileAccess.open(SPOTS, FileAccess.READ)
	if file == null:
		push_warning("SceneSpot[%s]: 无法打开 %s，隐藏该点" % [spot_name, SPOTS])
		visible = false
		return
	var all_info: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (all_info is Dictionary) or not all_info.has(spot_name):
		push_warning("SceneSpot[%s]: %s 中无此 spot，隐藏" % [spot_name, SPOTS])
		visible = false
		return
	_apply_spot(all_info.get(spot_name, {}))


## 把单个 spot 配置落地为可视状态（D-S1 / D-S6 全在此）。
## 抽出为独立方法，便于测试用合成 dict 直接驱动（绕过 spots.json 读取）。
## 注意：本方法自含门控态复位，单独调用也能得到正确视觉（不依赖 setup 的复位）。
func _apply_spot(spot: Dictionary) -> void:
	# 每次重结算先复位门控态（setup 也会复位，这里自含以保证独立可测）
	visible = true
	disabled = false
	is_locked = false
	is_hidden_by_gate = false
	info = spot

	# D-S1：缺 icon / path → 降级隐藏 + 告警，不崩溃
	if not _is_valid_spot(info):
		push_warning("SceneSpot[%s]: 缺 icon 或 path 字段，隐藏该点（D-S1）" % spot_name)
		visible = false
		return

	# D-S1：图标加载失败也降级，不崩
	var tex: Variant = load(info["icon"])
	if tex == null:
		push_warning("SceneSpot[%s]: icon 加载失败 (%s)，隐藏该点（D-S1）" % [spot_name, String(info["icon"])])
		visible = false
		return
	sprite.texture = tex

	# D-S6：visible_if 门控（随剧情解锁/隐藏）
	var gate: String = _eval_gate(info)
	if gate == "hidden":
		is_hidden_by_gate = true
		visible = false
		return
	if gate == "locked":
		is_locked = true
		disabled = true
		container.visible = false
		label.text = String(info.get("locked_description", ""))
		return

	fit_icon_to_constraints()
	container.visible = false
	label.text = String(info.get("description", ""))


func _on_pressed():
	if info.is_empty() or String(info.get("path", "")).is_empty():
		push_warning("SceneSpot[%s]: 缺 path，忽略点击（D-S1）" % spot_name)
		return
	_go_to_scene(String(info["path"]))


## 导航到目标场景。契约（GDD §5 press / D-S3 / D-S4）：
##   先写 Player.path（回档锚点）→ 切场景 → 发 scene_entered。
## scene_entered 必须在 change_scene_to_file 之后发（新场景 _ready 在下一帧）。
func _go_to_scene(target_path: String) -> void:
	# D-S3：回档锚点先写，保证后面任何路径（读档/过天）都落对场景
	Player.path = target_path

	if _test_no_swap:
		# 测试 seam：跳过真实切场景，只验证 path + 信号契约
		if ResourceLoader.exists(target_path):
			EventSignal.scene_entered.emit(target_path)
		return

	# 切场景（S-C：同城导航零成本即时，这里不扣任何资源）
	var err := get_tree().change_scene_to_file(target_path)
	if err != OK:
		push_error("SceneSpot[%s]: 切场景失败 %s（err=%d），停留原地" % [spot_name, target_path, err])
		return
	# D-S4：广播进入事件，教学/表现层可监听
	EventSignal.scene_entered.emit(target_path)


# ============================================================
#  D-S1 / D-S6 纯逻辑（可单测，无需依赖真实 spots.json）
# ============================================================

## 校验 spot 基础字段是否齐全（D-S1）。icon 与 path 任一为空即视为非法。
func _is_valid_spot(spot: Dictionary) -> bool:
	return String(spot.get("icon", "")).is_empty() == false \
		and String(spot.get("path", "")).is_empty() == false


## 结算门控（D-S6），返回 "ok" / "hidden" / "locked"。
##   visible_if 不满足                      → "hidden"
##   locked=true（无论 visible_if 是否满足）→ "locked"（锁定优先级更高）
## 由 Player.player_tags 派生，method：1=all 0=any。
func _eval_gate(spot: Dictionary) -> String:
	var visible_if: Variant = spot.get("visible_if", null)
	if visible_if is Array and visible_if.size() > 0:
		var method: int = int(spot.get("visible_if_method", 1))
		if not _player_has_tags(visible_if, method):
			return "hidden"
	if bool(spot.get("locked", false)):
		return "locked"
	return "ok"


func _player_has_tags(tags: Array, method: int) -> bool:
	if tags.is_empty():
		return true
	if method == 0:  # any
		for t in tags:
			if Player.player_has_tags([String(t)]):
				return true
		return false
	# all（默认）
	for t in tags:
		if not Player.player_has_tags([String(t)]):
			return false
	return true


func _on_mouse_entered():
	if visible and not is_locked:
		container.visible = true


func _on_mouse_exited():
	container.visible = false


func fit_icon_to_constraints():

	# 获取原始图片尺寸
	var original_size = sprite.texture.get_size()
	# 计算缩放比例（确保不超过最大尺寸，不小于最小尺寸）
	var scale_x = max_size.x / original_size.x
	var scale_y = max_size.y / original_size.y
	var scale_ratio = min(scale_x, scale_y)  # 取较小的比例，避免超出最大尺寸

	# 确保缩放后不小于最小尺寸
	var min_scale_x = min_size.x / original_size.x
	var min_scale_y = min_size.y / original_size.y
	var min_scale_ratio = max(min_scale_x, min_scale_y)
	scale_ratio = max(scale_ratio, min_scale_ratio)  # 不小于最小比例

	# 应用缩放（保持宽高比）
	sprite.scale = Vector2(scale_ratio, scale_ratio)
	var scaled_size = original_size * scale_ratio
	self.size = scaled_size

	self.position = ordinary
	sprite.position = self.size/2
