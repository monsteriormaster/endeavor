"""
剧情管理器 - 负责加载JSON对话数据并控制对话流程
使用方法：
调用 add_plot(file_path:String, plot_name:String) 加载特定剧情 
依赖：
DialogueGroup 和 Dialogue 资源类
dialogue_ui.tscn 场景文件
"""
extends Node

const UI = 'res://components/dialogue_ui.tscn'

func add_plot(file_path:String, plot_name:String):
	if Player.is_dialogue_exist:
		return
	Player.is_dialogue_exist = true	
	var plot =find_plot(load_json(file_path),plot_name)
	execute_dialogue(plot)
	

func load_json(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	var reply = JSON.parse_string(file.get_as_text())
	file.close()
	return reply


func find_plot(all_plot, plot_name:String):
	return all_plot.get(plot_name, {})
	
	
func execute_dialogue(plot):
	var dialogue_scene = load(UI)
	var dialogue_ui = dialogue_scene.instantiate()
	
	get_tree().root.add_child(dialogue_ui)
	
	var dialogue_group = DialogueGroup.new()
	
	for i in range(1000):  
		var key = str(i) + "th"
		if plot.has(key):
			var dialogue_data = plot[key]
			
			var dialogue = Dialogue.new()
			dialogue.character_name = dialogue_data.get("name", "")
			dialogue.content = dialogue_data.get("text", "")
			dialogue.is_option = dialogue_data.get("is_option",false)
			dialogue.next =dialogue_data.get("next",-1)
			dialogue.effect = dialogue_data.get("effect","")
			dialogue.options = []
			if dialogue_data.has("options"):
				for option_data in dialogue_data["options"]:
					var option = {
						"text": option_data.get("text", ""),
						"next": option_data.get("next", -1),
						"effect": option_data.get("effect", ""),
						"condition": option_data.get("condition", "")
					}
					option['is_ava'] = deal_condition(option["condition"])
					dialogue.options.append(option)
						
			dialogue_group.dialogue_list.append(dialogue)
		else:
			break  	
	dialogue_ui.show_dialogue_group(dialogue_group)
	

func deal_condition(condition:String)-> bool:
	if condition == "": 
		return true
	else:
		if sentence_condition(condition):
			return true	
	return false	
		

func sentence_condition(condition:String)-> bool:

	var condition_groups = condition.split("；")

	for group in condition_groups:
		group = group.strip_edges()
		if group == "":
			continue
		
		if group.begins_with("tags: "):
			var tag_list = group.get_slice("tags: ", 1)
			var required_tags = tag_list.split("，")
			for tag in required_tags:
				if tag not in Player.player_tags:
					return false
					
		elif group.contains(" tag "):
			var parts = group.split(" tag ")	
			var character = parts[0].strip_edges()
			var tags = parts[1].strip_edges()
			var required_tags = tags.split("，")
			for tag in required_tags:
				if tag not in Player.npc[character][tags]:
					return false

		elif group.begins_with("money "):
			var parts = group.split(" ")
			var pd = parts[1].strip_edges()
			var value = int(parts[2].strip_edges())
			
			if pd == ">" || pd == ">=":
				if Player.player_money < value:
					return false

			if pd == "<" || pd == "<=":
				if Player.player_money > value:
					return false
	return true
