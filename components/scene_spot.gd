"""
场景点 - 地图中用于跳转地图的区块
使用方法：
在检查器中设定spot_name,按需求设定max_size,min_size,ordinary
"""

extends Button

const SPOTS = "res://resoures/spots.json" 

var info :={}
var icon_texture: Texture2D

@export var spot_name:String
@export var max_size: Vector2 = Vector2(100, 100)  # 最大宽高
@export var min_size: Vector2 = Vector2(50, 50)   # 最小宽高
@export var ordinary := Vector2(120,120)

@onready var sprite = $Sprite2D
@onready var container = $PanelContainer
@onready var label = $PanelContainer/Label

func _ready():
	setup()


func setup():
	var file = FileAccess.open(SPOTS, FileAccess.READ)
	var all_info = JSON.parse_string(file.get_as_text())
	file.close()	
	info = all_info.get(spot_name,{})
	sprite.texture = load(info["icon"])
	fit_icon_to_constraints()
	container.visible = false
	label.text = info["description"]


func _on_pressed():
	get_tree().change_scene_to_file(info["path"])
	

func _on_mouse_entered():
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
	
