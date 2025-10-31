extends Node2D

@onready var sicourge = $sicourge
@onready var hero = $hero
@onready var main_ui =$Main_ui

var guide_condition = []

func _ready():
	sicourge.hide()
	EventSignal.dialogue_finished.connect(change)
	EventSignal.next_day_press.connect(next_day)
	main_ui.is_next_day_locked = true
	day0()

	
func change():
	if Player.player_has_tags(["第二天剧情"]) and Player.time == 2:
		sicourge.show()
		hero.hide()	
		Player.path = 'res://scene/main.tscn'
	
	if Player.player_has_tags(["游戏开始"]) and Player.time == 1:
		main_ui.is_next_day_locked = false
		
	if Player.player_has_tags(['斯库奇引导2']):
		main_ui.is_next_day_locked = false	
	
	
func day0():
	Player.path = 'res://scene/guide.tscn'
		
	
func next_day():
	main_ui.is_next_day_locked = true
