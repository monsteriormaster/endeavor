extends Node2D

const PATH = "res://components/character_panel.tscn"






func _on_button_pressed():
	var Cpanel = load(PATH).instantiate()
	Cpanel.setup("Falayee")
	add_child(Cpanel)
