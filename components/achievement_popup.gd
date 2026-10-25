extends Control

## 成就解锁弹窗。顶部正中跳出，2s 自动关闭。
## 由 AchievementManager 呼出（modal=false, esc_closes=false, persist=true）。
##
## 视觉：手绘题签底板（theme/ach_tag_plate.tres 九宫格）+ 铜细线画框 + 图/名/描述，
## 与成就画卷（achievement_list）同材质（纸 / 铜 / 墨）。
## ⚠️ 旧稿的「path 缺省 → 纯黑 ColorRect」已废弃（违反工程「不用纯黑」冻结规矩），
##    改为显示小七的铅笔草稿占位（与小画卷里未配图条目一致）。
##
## 尺寸：**520×63**（2026-10-01 用户「提示窗太大了，高度缩小为1/3」，原 520×188）。
##   高度只剩 63 → 文字不能竖着堆三层，改为横条版式：
##     [图 48×48] [成就达成(11px) / 成就名(19px)] │ [描述(13px，2 行内，垂直居中)]
##   图位 128→42，画框 144→48。⚠️ 这两张按 **1x 另烘**（`popup_frame.png`/`popup_sketch.png`），
##   不能把 144px 的画框缩到 48 —— 工程 default_texture_filter=0(NEAREST)，细线会被点采样吃掉。
##   真正的成就图（128×128）缩到 42 才需要 LINEAR，故 TextureRect 显式 texture_filter=2。
##
## 自带 Timer 2s，到期走 OverlayRoot.close_overlay 出栈（不直接 queue_free 绕过 OverlayRoot）。
## 多成就同时解锁时，AchievementManager 用队列串行呼出本弹窗，避免重叠丢失。

const POPUP_DURATION := 2.0
const SKETCH := preload("res://art/ui/achievement/popup_sketch.png")
const COL_PENCIL := Color(0.541176, 0.494118, 0.431373)   # #8A7E6E

@onready var _texture: TextureRect = $Panel/ImageBox/TextureRect
@onready var _title: Label = $Panel/TitleLabel
@onready var _desc: Label = $Panel/DescLabel


func _ready() -> void:
	# 2s 后自动关闭（走 OverlayRoot 出栈，不直接 queue_free）
	var timer := Timer.new()
	timer.wait_time = POPUP_DURATION
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_timeout)
	timer.start()


## 设置图/名/描述。由 AchievementManager 在 push_overlay 后调用（@onready 已就绪）。
func setup(cfg: Dictionary) -> void:
	_title.text = String(cfg.get("name", ""))
	_desc.text = String(cfg.get("description", ""))
	var path: String = String(cfg.get("path", ""))
	if path != "" and ResourceLoader.exists(path):
		_texture.texture = load(path)
		_texture.modulate = Color(1, 1, 1, 1)
	else:
		# 未配图 → 铅笔草稿占位（弹窗天生是「已解锁」，所以给已画好的草稿而不是空框）
		# alpha 0.82：弹窗图位只有 42px，草稿笔画按比例变细，0.62 在实测里几乎看不见（最暗仅 207）。
		_texture.texture = SKETCH
		_texture.modulate = Color(COL_PENCIL.r, COL_PENCIL.g, COL_PENCIL.b, 0.82)


func _on_timeout() -> void:
	if not OverlayRoot.close_overlay(self):
		queue_free()
