extends Node2D



func _on_button_pressed():
	PlotImporter.add_plot("res://resoures/plot/rite/prison.json","50万后再次与狱卒交谈")


func _on_button_2_pressed():
	print(Player.player_tags)


func _on_button_3_pressed():
	PlotImporter.add_plot("res://resoures/plot/rite/prison.json","与法拉叶的第一次交流")
