#变量声明和常量定义
extends PopupPanel#弹出面板

var tagtip = Label.new()

var info
var taginfo
var einfo
#资源文件路径
const TAGS = "res://resoures/tags.json"
#需要补充文件内容
const CHARACTERS = "res://resoures/characters.json"#角色
const EQUIPMENT = "res://resoures/equipment.json"#装备

func _ready():
	tagtip.name = 'tagtip'
	tagtip.autowrap_mode = true
	tagtip.hide()
	$margin.add_child(tagtip)
	

func _process(_delta):
	pass


func _on_closebutton_pressed():
	hide()
#关闭键

func setup(character_name:String):
	get_info()
	info = Player.npc[character_name]
	print(info)
	
	$margin/att.text =  "智力" + " " + str(info['int']) + '\n' + \
						"魅力" + " " + str(info['app']) + '\n' + \
						"力量" + " " + str(info['str']) + '\n' + \
						"体魄" + " " + str(info['bod']) + '\n'
	$margin/description.text = 	info['description']		
	$margin/nickname.text = info['name']
	tagsdeal()
	equipmentdeal(info["equipment"])
	
func tagsdeal():

	for data in info['tags']:
		var name_label = Label.new()
		name_label.text = data

		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.mouse_entered.connect(_on_tags_hover.bind(taginfo[data]))
		name_label.mouse_exited.connect(_on_tags_leave.bind(taginfo[data]))
		
		$margin/tags.add_child(name_label)
		
func _on_tags_hover(data):
	tagtip.text = data['description']
	tagtip.size = Vector2(200,300)
	var mouse_pos = get_viewport().get_mouse_position()
	tagtip.position =  mouse_pos + Vector2(20,6)
	print(tagtip.position)
	tagtip.show()				


func _on_tags_leave(data):
	tagtip.hide()


func equipmentdeal(data):
	for key in data:
		var name_label = Label.new()
		var concret_equip = data[key]
		name_label.text = data[key]
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.mouse_entered.connect(_on_equipment_hover.bind(einfo[concret_equip]))
		name_label.mouse_exited.connect(_on_equipment_leave.bind(einfo[concret_equip]))
		
		$margin/equipment.add_child(name_label)
		
func _on_equipment_hover(data):
	tagtip.text = data['description']
	tagtip.size = Vector2(400,100)
	var mouse_pos = get_viewport().get_mouse_position()
	tagtip.position =  mouse_pos + Vector2(3,15)
	print(tagtip.position)
	tagtip.show()				


func _on_equipment_leave(data):
	tagtip.hide()		
	
func get_info():
	var file = FileAccess.open(TAGS, FileAccess.READ)
	taginfo = JSON.parse_string(file.get_as_text())
	file.close()	
	file = FileAccess.open(EQUIPMENT, FileAccess.READ)
	einfo = JSON.parse_string(file.get_as_text())
