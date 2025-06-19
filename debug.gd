extends Node2D

const CONFIRM_DIALOG_PATH = "res://scnene/confirmdialog.tscn"

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func debuging():
	var confirm_dialog = load(CONFIRM_DIALOG_PATH).instantiate()
	confirm_dialog.setup(
		"确认离开",
		"该页面不会保存，确定要离开吗？",
		"确认",
		"返回"
		)
	confirm_dialog.confirmed.connect(func (): get_tree().change_scene_to_file('res://scnene/loading.tscn'))
	remove_child(confirm_dialog)
	add_child(confirm_dialog)
	confirm_dialog.show_dialog()
	



func _on_button_pressed():
	print('pressed')
	debuging()
