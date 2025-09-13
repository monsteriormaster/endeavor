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
			dialogue.effect = dialogue_data.get("effect",{})
			dialogue.options = []
			if dialogue_data.has("options"):
				for option_data in dialogue_data["options"]:
					var option = {
						"text": option_data.get("text", ""),
						"next": option_data.get("next", -1),
						"effect": option_data.get("effect", {}),
						"condition": option_data.get("condition", {})
					}
					option['is_ava'] = deal_condition(option["condition"])
					dialogue.options.append(option)
						
			dialogue_group.dialogue_list.append(dialogue)
		else:
			break  	
	dialogue_ui.show_dialogue_group(dialogue_group)
	

func deal_condition(condition)-> bool:
	if condition == {}: 
		return true
	else:
		if sentence_condition(condition):
			return true	
	return false	
		

func sentence_condition(condition)-> bool:
	
	if "money" in condition:
		var money_condition = condition.money
		var left = money_condition.get("left", 0)
		var right = money_condition.get("right", 9999999)
		
		# 检查玩家金钱是否在[left, right]范围内
		if Player.player_money < left or Player.player_money > right:
			return false
	
	if "tags" in condition:
		var tags = condition.tags
		
		# 检查玩家是否拥有指定标签
		if not Player.player_has_tags(tags, 1):
			return false
	
	if "num_tags" in condition:
		var num_tags = condition.num_tags
		for num_tag in num_tags:
			if not Player.player_meet_num_tag(num_tags[num_tag].name,num_tags[num_tag].left,num_tags[num_tag].right):
				return false
	
	if "npc" in condition:
		var npc_conditions = condition.npc
		
		for npc_name in npc_conditions:
			var npc_condition = npc_conditions[npc_name]
			var tags = npc_condition.get("tags", [])
			var num_tags = npc_condition.get("num_tags", {})
			# 检查NPC是否拥有指定标签
			if not Player.npc_has_tags(npc_name, tags, 1):
				return false
			
			for num_tag_name in num_tags:
				if not Player.npc_meet_num_tags(num_tags[num_tag_name].name,npc_name,num_tags[num_tag_name].left,num_tags[num_tag_name].right):
					return false	
					
	return true
