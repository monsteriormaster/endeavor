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
	print("已经add_plot了\n")
	var plot =find_plot(load_json(file_path),plot_name)
	print(plot)
	print('\n')
	execute_dialogue(plot)
	

func load_json(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) 


func find_plot(all_plot, plot_name:String):
	return all_plot.get(plot_name, {})
	
	
func execute_dialogue(plot):
	var dialogue_scene = load(UI)
	var dialogue_ui = dialogue_scene.instantiate()
	
	get_tree().root.add_child(dialogue_ui)
	
	var dialogue_group = DialogueGroup.new()
	
	for i in range(1000):  # 假设最多100条对话，可根据需要调整
		var key = str(i) + "th"
		if plot.has(key):
			var dialogue_data = plot[key]
			
			var dialogue = Dialogue.new()
			dialogue.character_name = dialogue_data.get("name", "")
			dialogue.content = dialogue_data.get("text", "")
			
			# 添加到对话组
			dialogue_group.dialogue_list.append(dialogue)
		else:
			break  # 遇到不存在的序号时停止遍历
	print("show了\n")
	dialogue_ui.show_dialogue_group(dialogue_group)
	
	
