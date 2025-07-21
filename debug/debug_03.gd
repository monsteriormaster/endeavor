extends Node2D

var dat

# Called when the node enters the scene tree for the first time.
func _ready():
	getdat()
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func _on_button_pressed():
	print(dat)
	DataOn.change_att("int",1)
	getdat()
	print(dat)


func getdat():
	var file = FileAccess.open('res://resoures/curtain.json', FileAccess.READ)
	var dat = JSON.parse_string(file.get_as_text())
