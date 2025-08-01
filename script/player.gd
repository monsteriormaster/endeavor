extends Node

@export_group("curtain_scence")
@export var path = ''#当前路径
@export var plot = ''#当前正在经历的事件
@export var exact_situation = {}#该回合已经进行的操作 

@export_group("player")
@export var player_age =16.0 
#用于定义时间相关的事件
@export var player_money =100
@export var player_app_fact =""
@export var player_name ="请输入你的名字"

@export var player_app:int =0 #魅力
@export var player_int:int =0 #智力
@export var player_edu:int =1 #教育，暂时只和学校的剧情相关
@export var player_bod:int =0 #体魄
@export var player_str:int =0 #力量
@export var player_bac:int =1 #背景，暂时忽略
@export var player_att:int =20 #属性点
#属性，用于鉴定,edu 和 bac暂时保留
@export var player_equipment = []#装备
@export var player_tags = []#词条
@export var gift_att = 60
@export var  player_staff :=[]

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
	
