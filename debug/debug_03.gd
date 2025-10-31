extends Node2D

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func _on_button_pressed():
	PlotImporter.add_plot("res://resoures/plot/misson/beginning.json","游戏开始")
