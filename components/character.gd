"""
人物点 - 地图中用于人物显示
使用方法：
在检查器中设定spot_name,按需求设定max_size,min_size,ordinary;添加YAFSM管理剧情
"""

extends Button

const CHARACTERS = "res://resoures/characters.json"

@export var charcter_name:String
@export var config_path: String

@export var max_size: Vector2 = Vector2(200, 400)  # 最大宽高
@export var min_size: Vector2 = Vector2(100, 200)   # 最小宽高
@export var ordinary := Vector2(120,120)

@onready var sprite = $Sprite2D

var info :={}
var map :={}

func _ready():
	setup()


func setup():
	var file = FileAccess.open(CHARACTERS, FileAccess.READ)
	var all_info = JSON.parse_string(file.get_as_text())
	file.close()	
	info = all_info.get(charcter_name,{})
	sprite.texture = load(info["image"])
	fit_icon_to_constraints()
	
	var config_file = FileAccess.open(config_path, FileAccess.READ)
	map = JSON.parse_string(config_file.get_as_text())
	config_file.close()
	
	
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


func _on_pressed():
	var target_dialog = get_dialog()
	if target_dialog == null:
		return
	PlotImporter.add_plot(target_dialog["path"], target_dialog["name"])
	
	
func get_dialog():
	# 获取对话字典（而非数组）
	var dialogs = map.get("dialogs", {})
	
	# 遍历对话字典的值（而非键）
	for dialog_name in dialogs:
		var dialog = dialogs[dialog_name]
		var conditions = dialog.get("conditions", {})
		var limits = dialog.get("limits", {})
		var method = 1
		var flag := false
		
		# 处理玩家标签条件
		if "method" in conditions:
			method = conditions.method
		if "tags" in conditions:
			if not Player.player_has_tags(conditions.tags, method):
				continue
		if "num_tags" in conditions:
			var num_tags = conditions["num_tags"]
			for num_tag_name in num_tags:
				if not Player.player_meet_num_tag(num_tags[num_tag_name].name,num_tags[num_tag_name].left,num_tags[num_tag_name].right):
					flag = true
					break	
		# 处理NPC条件
		if "npc" in conditions:
			var npc_conditions = conditions.npc
			# 遍历NPC条件字典
			for npc_name in npc_conditions:
				var npc = npc_conditions[npc_name]
				var npc_method = 1
				if "method" in npc:
					npc_method = npc.method 	
				if "tags" in npc:
					if not Player.npc_has_tags(npc_name, npc.tags, npc_method):
						flag = true
						break
				if "num_tags" in npc:
					var num_tags = npc["num_tags"]
					for num_tag_name in num_tags:
						if not Player.npc_meet_num_tag(num_tags[num_tag_name].name,npc_name,num_tags[num_tag_name].left,num_tags[num_tag_name].right):
							flag = true
							break
					if flag:
						break		
				
		if flag:
			continue
			
		# 处理限制条件
		if "method" in limits:
			method = limits.method
		if "tags" in limits:
			if Player.player_has_tags(limits.tags, method):
				continue
		if "num_tags" in conditions:
			for num_tag in conditions["num_tags"]:
				if Player.player_meet_num_tags(num_tag,num_tag.left,num_tag.right):
					flag = true
					break	
				
		# 处理NPC限制条件
		if "npc" in limits:
			var npc_limits = limits.npc
			# 遍历NPC限制字典
			for npc_name in npc_limits:
				var npc = npc_limits[npc_name]
				var npc_method = 1
				if "method" in npc:
					npc_method = npc.method 	
				if "tags" in npc:
					if Player.npc_has_tags(npc_name, npc.tags, npc_method):
						flag = true
						break
				if "num_tags" in npc:
					var num_tags = npc["num_tags"]
					for num_tag_name in npc["num_tags"]:
						if Player.npc_meet_num_tag(num_tags[num_tag_name].name,npc_name,num_tags[num_tag_name].left,num_tags[num_tag_name].right):
							flag = true
							break
					if flag:
						break
						
		if flag:
			continue
		
		return dialog
		
