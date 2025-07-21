extends Node2D

const CONFIRM_DIALOG_PATH = "res://components/confirmdialog.tscn"






func _on_button_pressed():
	SaveLoader.load_game()
	print(Player.player_name)


func _on_button_2_pressed():
	SaveLoader.save_game()


func _on_button_3_pressed():
	Player.path = "res://scene/main.tscn"
	Player.player_name = "zz"
