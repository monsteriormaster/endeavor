extends Node2D

const CHARACTER_PANNEL_PATH = "res://components/character_panel.tscn"

var hero := "Hero"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass





func _on_avater_pressed() -> void:
	print('pressd \n')
	var hero_pannnel = load(CHARACTER_PANNEL_PATH).instantiate()
	hero_pannnel.setup(hero)
	add_child(hero_pannnel)
