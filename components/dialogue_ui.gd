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


	if dialogue.effect != {} && !dialogue.is_effect_excute:
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
			option_label.text = option["condition"].description
			option_label.disabled = true
			option_box.add_child(option_label)


func _ready():
	visible = false


func _on_click(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:\
		display_next_dialogue()


func on_option_entered(effect,next:int):
	if effect != {}:
		deal_effect(effect)
	dialogue_index = next	
	display_next_dialogue()
	

func clear_options():
	for child in option_box.get_children():
		child.queue_free()


func deal_effect(dialogue_effects):
	for effect_name in dialogue_effects:
		var effect = dialogue_effects[effect_name]
		
		if effect_name == "money":
			Player.player_money += effect.value * effect.operate
		
		if effect_name == "tags":
			for tag in effect:
				Player.player_tags.append(tag)
				
		if effect_name == "num_tags":
			for num_tag in effect:
				Player.player_num_tags[num_tag] = effect[num_tag]
		
				
		if effect_name == "npc":
			for npc_name in effect:
				var npc = effect[npc_name]			
				if npc_name not in Player.npc:
					Player.npc[npc_name] = {
						"tags" = [],
						"num_tags" = {}
					}
				for cur_effect_name in npc:
					
					if cur_effect_name == "tags":
						for tag in npc[cur_effect_name]:
							Player.npc[npc_name]["tags"].append(tag)
						
					if 	cur_effect_name == "num_tags":
						for num_tag in npc[cur_effect_name]:
							Player.npc[npc_name]['num_tags'][num_tag] = npc[cur_effect_name][num_tag]
	

func translate_condition(condition) -> String:
	return condition.description
