extends Control

@export_group("UI")
@export var character_name_text : Label
@export var text_box : Label
@export var option_box : VBoxContainer

var main_dialogue : DialogueGroup

var dialogue_index := 0
var typing_tween : Tween

func show_dialogue_group(dialogue_group: DialogueGroup) -> void:
	main_dialogue = dialogue_group
	dialogue_index = 0
	visible = true
	display_next_dialogue()


func display_next_dialogue():
	print(dialogue_index)
	if dialogue_index == -1:
		visible = false
		return
	
	clear_options()
	
	var dialogue := main_dialogue.dialogue_list[dialogue_index]
	print(dialogue.content)
	print(dialogue.next)
	print(dialogue.content)
	
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
		
	if dialogue.is_option:
		show_option(dialogue.options)
	
	print("next is",dialogue.next)
		

func append_character(character : String):
	text_box.text += character


func show_option(options):
	for option in options:
		var option_label = Button.new()
		option_label.text = option.text
		option_label.pressed.connect(on_option_entered.bind(option.next))
		option_box.add_child(option_label)
		

func _ready():
	visible = false


func _on_click(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:\
		display_next_dialogue()
		
		
func on_option_entered(next:int):
	dialogue_index = next	
	display_next_dialogue()
	

func clear_options():
	for child in option_box.get_children():
		child.queue_free()
		
