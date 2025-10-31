"""
游戏内实时数据
所有人物都会以字典的形式存在npc里，为便于调试主角的数据单独列出来了
注意 在该文件添加修改的变量必须在 res://script/save_loader.gd 中做对应修改，确保存档系统正常

以下是一些辅助函数
player_attr_meet(att: String, compare: String, value: int)，用于比较pc的数值
npc_has_tags(npc: String, tags: Array, method := 1),用于判断npc是否满足标签，method1为all，0为any
player_has_tag(tags: Array, method := 1),用于判断pc是否满足标签，method1为all，0为any
"""


extends Node

@export_group("curtain_scence")
@export var path = ''#当前路径
@export var plot = ''#当前正在经历的事件
@export var exact_situation = {}#该回合已经进行的操作 

@export_group("player")
@export var player_age :=16.0 
@export var time := 1
#用于定义时间相关的事件
@export var player_money =100
@export var player_app_fact =""
@export var player_name ="请输入你的名字"

@export var player_app:int =0 #魅力
@export var player_int:int =0 #智力
@export var player_edu:int =1 #教育，暂时只和学校的剧情相关
@export var player_bod:int =0 #体魄
@export var player_str:int =0 #力量
@export var player_bac:String ="男爵" #背景，暂时忽略
@export var player_att:int =20 #属性点
#属性，用于鉴定,edu 和 bac暂时保留
@export var player_equipment = []#装备
@export var player_tags = []#词条
@export var player_num_tags := {}#可堆叠的词条
@export var gift_att = 60#天赋点数
@export var  player_stuff :=[]#物品

@export_group("others")
@export var development = {}#剧情发展情况
@export var npc = {}#其他角色，包括伙伴，伙伴仅仅多一个追随的标签

@export_group("kid")
@export var child_name : String
@export var child = {}#孩子的情况

#@export var character_label = {
	#"神速":{"description":"当你追上了风，当声音被甩在身后，会是怎样光景？"},
	#
	#"灵感":{"description":"世界的真相在你眼前浮现。"},
#
	#"灾厄":{"description":"灾厄是一把可怕的钥匙，它会开启什么呢？"},	
	#
	#"学习":{"description":"苟日新，日日新。"},
#}

@export var is_dialogue_exist := false

#属性改变函数
func change_int(value:int):
	player_int += value


func change_app(value:int):
	player_app += value	

	
func change_bod(value:int):
	player_bod += value

	
func change_str(value:int):
	player_str += value	

	
func change_att(value:int):
	player_att += value	
	

func get_npc_data(npc_name: String) -> Dictionary:
	return npc.get(npc_name, {})


func npc_has_tags(npc: String, tags: Array, method := 1) -> bool:
	var npc_data = get_npc_data(npc)
	var npc_tags = npc_data.get("tags", [])
	if method == 1 :
		return tags.all(func(tag): return tag in npc_tags)
	else:
		return tags.any(func(tag): return tag in npc_tags)
	
	
func player_attr_meet(att: String, compare: String, value: int) -> bool:
	var player_attr  
	match att:
		"app":
			player_attr = player_app
		"int":
			player_attr = player_int
		"bod":
			player_attr = player_bod
		"str":
			player_attr = player_str
		"edu":
			player_attr = player_edu
		_:
			return false  


	match compare:
		"=":
			return player_attr == value
		">":
			return player_attr >= value
		"<":
			return player_attr <= value
		_:
			return false  
		

func player_has_tags(tags: Array, method := 1) -> bool:
	if method == 1 :
		return tags.all(func(tag): return tag in player_tags)
	else:
		return tags.any(func(tag): return tag in player_tags)		
		
		
func player_meet_num_tag(tag: String,left: int,right: int) -> bool:		
	if tag in player_num_tags:
		if player_num_tags[tag] >= left && player_num_tags[tag] <= right:
			return true
	return false
	
	
func npc_meet_num_tag(tag: String,npcname: String,left: int,right: int) -> bool:	
	if npcname in npc:
		if "num_tags" in npc[npcname]:	
			if tag in npc[npcname].num_tags:
				if npc[npcname].num_tags[tag] >= left && npc[npcname].num_tags[tag] <= right:
					return true
	return false


func hero_merge():
	npc.hero["name"] = player_name
	npc.hero["int"] = player_int
	npc.hero["app"] = player_app
	npc.hero["str"] = player_str
	npc.hero["bod"] = player_bod
	npc.hero["equipment"] = player_equipment
	npc.hero["tags"] = player_tags
