extends Node2D

signal panel_opened(character_name)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func debuging():
	var character_name = 'Falayee'
		
	var popup = preload("res://scnene/character_panel.tscn").instantiate()
	popup.setup(character_name)
	get_tree().root.add_child(popup)


func _on_bug_begin_pressed():
	debuging()
