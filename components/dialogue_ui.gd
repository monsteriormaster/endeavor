extends Control

@export_group("UI")
@export var character_name_text : Label
@export var text_box : Label
@export var option_box : VBoxContainer


var main_dialogue : DialogueGroup

var dialogue_index := 0
var typing_tween : Tween

var hero = Player.player_name

func show_dialogue_group(dialogue_group: DialogueGroup) -> void:
	main_dialogue = dialogue_group
	dialogue_index = 0
	visible = true
	EventSignal.emit_signal('dialogue_finished')
	display_next_dialogue()


func display_next_dialogue():
	if dialogue_index == -1:
		Player.is_dialogue_exist = false
		visible = false
		emit_signal("dialogue_finished") 
		return
	
	clear_options()

	var dialogue := main_dialogue.dialogue_list[dialogue_index]
	
	if typing_tween and typing_tween.is_running():
		typing_tween.kill()
		text_box.text = dialogue.content
		if dialogue.is_option == false:	
			dialogue_index = dialogue.next
		
	else:
		character_name_text.text = dialogue.character_name
		
		typing_tween = get_tree().create_tween()
		text_box.text = ""
		for character in dialogue.content:
			typing_tween.tween_callback(append_character.bind(character)).set_delay(0.05)
		if dialogue.is_option == false:	
			typing_tween.tween_callback(func(): dialogue_index = dialogue.next)


	if dialogue.effect != '' && !dialogue.is_effect_excute:
		dialogue.is_effect_excute = true
		deal_effect(dialogue.effect)

	if dialogue.is_option:
		show_option(dialogue.options)


func append_character(character : String):
	text_box.text += character


func show_option(options):
	for option in options:
		if option["is_ava"]:
			var option_label = Button.new()
			option_label.text = option.text
			option_label.pressed.connect(on_option_entered.bind(option.effect,option.next))
			option_box.add_child(option_label)
		else:
			var option_label = Button.new()
			option_label.text = option.condition + "时解锁该选项"
			option_label.disabled = true
			option_box.add_child(option_label)


func _ready():
	visible = false


func _on_click(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:\
		display_next_dialogue()


func on_option_entered(effect,next:int):
	if effect != "":
		deal_effect(effect)
	dialogue_index = next	
	display_next_dialogue()
	

func clear_options():
	for child in option_box.get_children():
		child.queue_free()


func deal_effect(dialogue_effects):
	var effects = dialogue_effects.split(";")

	for effect in effects:

		effect = effect.strip_edges()
		if effect == "":
			continue

		if effect.begins_with("获得 tag"):
			var tag = effect.get_slice("tag ", 1)
			if tag not in Player.player_tags:
				Player.player_tags.append(tag)
			

		elif effect.contains(" 获得 tag"):
			var parts = effect.split(" 获得 tag")	
			var character = parts[0].strip_edges()
			var tags_union = parts[1].strip_edges()
			if character not in Player.npc:
				Player.npc[character]={}
			if 'tags' not in Player.npc[character]:
				Player.npc[character]['tags']=[]
			var tags_union_clean = tags_union.replace("，", ",").strip_edges()
			var tags = tags_union_clean.split(",")
			for tag in tags:
				if tag not in Player.npc[character]["tags"]:
					Player.npc[character]["tags"].append(tag)

		elif effect.begins_with("money "):			
			var getting = effect.get_slice("money ", 1)
			var parts = getting.split(" ")
			var pd = parts[0].strip_edges()
			var value = int(parts[1].strip_edges())
			if pd == '-':
				value *= -1
			Player.player_money += value 


func translate_condition(condition: String) -> String:
	 
	var translated_parts = []
	var condition_groups = condition.split("；")
	
	for group in condition_groups:
		group = group.strip_edges()
		if group == "":
			continue
			
		# 处理角色tag条件
		if group.contains(" tag "):
			var parts = group.split(" tag ")
			if parts.size() == 2:
				var character = parts[0].strip_edges()
				var required_tag = parts[1].strip_edges()
				translated_parts.append(character + "必须被" + required_tag)
		
		# 处理玩家tag条件
		elif group.begins_with("tag "):
			var tag_list = group.get_slice("tag ", 1)
			var required_tags = tag_list.split("，")
			var saying := "你必须"
			var i := 1
   
			for tag in tag_list:
				saying = saying + tag 
				if i == tag_list.length():
					break
				saying = saying + ' '
				i = i + 1 	 
				

		# 处理money条件
		elif group.begins_with("money "):
			var parts = group.split(" ")
			var op_text = ""
			var operator = parts[1].strip_edges()
			var value = parts[2].strip_edges()

			if operator == ">" or operator == ">=":
				op_text = "必须超过"
			   
			elif operator == "<=" or operator == "<":
				op_text = "不能多于"
				
			translated_parts.append("金钱" + op_text + value + "元")
	
	# 将所有翻译后的条件用"并且"连接
	var final_text = ""
	for i in range(translated_parts.size()):
		if i > 0:
			final_text += "并且"
		final_text += translated_parts[i]

	return final_text
