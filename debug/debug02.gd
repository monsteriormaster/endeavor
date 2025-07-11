extends Node2D

const CONFIRM_DIALOG_PATH = "res://components/confirmdialog.tscn"






func _on_button_pressed():
	var confirm_dialog = load(CONFIRM_DIALOG_PATH).instantiate()
	confirm_dialog.setup(
		"确认离开",
		"有资质没有用完，确定要离开吗？",
		"确认",
		"返回"
		)
	confirm_dialog.confirmed.connect(func (): get_tree().change_scene_to_file('res://scnene/main.tscn'))
	remove_child(confirm_dialog)
	add_child(confirm_dialog)
