extends Node2D

const CHARACTER_PANNEL_PATH = "res://components/character_panel.tscn"
const CHARACTER = "res://resoures/characters.json"

@export var is_next_day_locked = false:
	set(value):
		is_next_day_locked = value  # 更新变量值
		locked_next_day()  # 立即更新按钮状态

var hero := "Hero"

func _ready() -> void:
	assist_func()


func _process(delta: float) -> void:
	data_upgrade()
	pass


func _on_avater_pressed() -> void:
	var hero_pannnel = load(CHARACTER_PANNEL_PATH).instantiate()
	hero_pannnel.setup(hero)
	add_child(hero_pannnel)


func assist_func():
	var file = FileAccess.open(CHARACTER, FileAccess.READ)
	var info = JSON.parse_string(file.get_as_text())
	file.close()	
	Player.npc[hero] = info["Hero"]
	

func data_upgrade():
	$MarginContainer/top_container/information/money.text = "金钱：" + str(Player.player_money) + "万"
	$MarginContainer/top_container/information/noble.text = "贵族等级：" + Player.player_bac
	$MarginContainer/top_container/information/time.text = "时间：第" + str(Player.time) + "天"


func _on_next_day_pressed():
	Player.time += 1
	SaveLoader.save_game()
	SaveLoader.load_game()


func locked_next_day():
	if is_next_day_locked:
		$next_day.disabled = true
	else:
		$next_day.disabled = false
	
	
		
