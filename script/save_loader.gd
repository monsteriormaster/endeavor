"""
存档管理- 负责数据存档过程
使用方法：
调用 save_game()存档；load_game()读档 
"""


extends Node

func save_game():
	var file = FileAccess.open("user://endeavoursavegame.json", FileAccess.WRITE)
	
	var save_data ={}
	save_data = data_get() 
	var json =JSON.stringify(save_data)
	
	file.store_string(json)
	file.close()

	
func load_game():
	var file = FileAccess.open("user://endeavoursavegame.json", FileAccess.READ)
	
	var json = file.get_as_text()
	var save_data = JSON.parse_string(json)	
	file.close()
	
	load_data(save_data)
	if Player.path != "":
		get_tree().change_scene_to_file(Player.path)	
	else:
		get_tree().change_scene_to_file('res://scene/main.tscn')
		
		
func data_get():
	var save_data = {}
	
	save_data["path"] = Player.path
	save_data["plot"] = Player.plot
	save_data["exact_situation"] = Player.exact_situation
	save_data["time"] = Player.time
	#环境信息
	
	save_data["player_app"] = Player.player_app
	save_data["player_int"] = Player.player_int
	save_data["player_str"] = Player.player_str
	save_data["player_bod"] = Player.player_bod
	save_data["player_edu"] = Player.player_edu
	save_data["player_bac"] = Player.player_bac
	save_data["player_app_fact"] = Player.player_app_fact
	save_data["player_money"] = Player.player_money
	save_data["player_name"] = Player.player_name
	save_data["player_equipment"] = Player.player_equipment
	save_data["player_tags"] = Player.player_tags
	save_data["player_num_tags"] = Player.player_num_tags
	save_data["player_stuff"] = Player.player_stuff
	#玩家信息
	
	save_data["child_name"] = Player.child_name
	save_data["child"] = Player.child
	#孩子信息
	
	save_data["development"] = Player.development
	save_data["npc"] = Player.npc
	#其他信息
	
	return save_data 	


func load_data(save_data):
	Player.path = save_data["path"]
	Player.plot = save_data["plot"]
	Player.exact_situation = save_data["exact_situation"]
	Player.time = save_data["time"] 
	#环境信息

	Player.player_app = save_data["player_app"]
	Player.player_int = save_data["player_int"]
	Player.player_str = save_data["player_str"]
	Player.player_bod = save_data["player_bod"]
	Player.player_edu = save_data["player_edu"]
	Player.player_bac = save_data["player_bac"]
	Player.player_app_fact = save_data["player_app_fact"]
	Player.player_money = save_data["player_money"]
	Player.player_name = save_data["player_name"]
	Player.player_equipment = save_data["player_equipment"]
	Player.player_tags = save_data["player_tags"]
	Player.player_num_tags = save_data["player_num_tags"] 
	Player.player_stuff = save_data["player_stuff"]
	#玩家信息

	Player.child_name = save_data["child_name"]
	Player.child = save_data["child"] 
	#孩子信息

	Player.development = save_data["development"]
	Player.npc = save_data["npc"]
	#其他信息
