extends Node2D

func _ready():
	$Button3.disabled = true
	$Button4.disabled = true
	EventSignal.dialogue_finished.connect(unlock_button)


func _process(_delta):	
	$money.text = str(Player.player_money) + "万元"



func _on_button_pressed():
	if "进入监狱许可" in Player.player_tags:
		if "狱卒" in  Player.npc:
			if '贿赂' in Player.npc["狱卒"]["tags"]:
				PlotImporter.add_plot("res://resoures/plot/rite/prison.json","50万后再次与狱卒交谈")
				return
		else:
			PlotImporter.add_plot("res://resoures/plot/rite/prison.json","10万后再次与狱卒交谈")
			return
		
	
	PlotImporter.add_plot("res://resoures/plot/rite/prison.json","与狱卒第一次交流")	
		

func _on_button_2_pressed():
	print("检查状态")
	print(Player.player_tags)
	print(Player.npc)
	print(Player.player_money)
	print('\n')

func _on_button_3_pressed():
	if "法拉叶" in  Player.npc:
		if '惩戒与伤痕' in Player.npc["法拉叶"]["tags"]:
			PlotImporter.add_plot("res://resoures/plot/rite/prison.json","伤痕后与法拉叶的交流")
			return
		else:
			if '惬意' in Player.npc["法拉叶"]["tags"]:
				PlotImporter.add_plot("res://resoures/plot/rite/prison.json","惬意后与法拉叶的交流")
	PlotImporter.add_plot("res://resoures/plot/rite/prison.json","与法拉叶的第一次交流")
		

func unlock_button():
		if "进入监狱许可" in Player.player_tags:
			$Button3.disabled = false
			$Button4.disabled = false


func _on_button_4_pressed():
	if "衫斯" in  Player.npc:
		if '惩戒与伤痕' in Player.npc["衫斯"]["tags"]:
			PlotImporter.add_plot("res://resoures/plot/rite/prison.json","伤痕后与衫斯的交流")
			return
		else:
			if '惬意' in Player.npc["衫斯"]["tags"]:
				PlotImporter.add_plot("res://resoures/plot/rite/prison.json","惬意后与衫斯的交流")
	PlotImporter.add_plot("res://resoures/plot/rite/prison.json","与衫斯的第一次交流")
