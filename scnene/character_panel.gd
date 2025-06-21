extends PopupPanel

var info
var tagtip = Label.new()

func _ready():
	tagtip.name = 'tagtip'
	tagtip.autowrap_mode = true
	
	tagtip.hide()
	$margin.add_child(tagtip)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_closebutton_pressed():
	hide()


func setup(character_name:String):
	info = Characters.get(character_name)
	$margin/att.text =  "智力" + " " + str(info['int']) + '\n' + \
						"魅力" + " " + str(info['app']) + '\n' + \
						"力量" + " " + str(info['str']) + '\n' + \
						"体魄" + " " + str(info['bod']) + '\n'
	$margin/description.text = 	info['description']		
	$margin/nickname.text = info['name']
	tagsdeal()
	equipmentdeal()
	
func tagsdeal():
	var i = 0
	for data in info['tags']:
		var name_label = Label.new()
		name_label.text = data
		print('i = ' + str(i) + data)
		i = i + 1
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.mouse_entered.connect(_on_tags_hover.bind(data))
		name_label.mouse_exited.connect(_on_tags_leave.bind(data))
		
		$margin/tags.add_child(name_label)
		
func _on_tags_hover(data):
	var tag_info = Characters.labels_for_others.get(data)
	tagtip.text = tag_info['description']
	print("我的print去哪里了")
	tagtip.size = Vector2(200,300)
	var mouse_pos = get_viewport().get_mouse_position()
	tagtip.position =  mouse_pos + Vector2(20,6)
	print(tagtip.position)
	tagtip.show()				


func _on_tags_leave(data):
	tagtip.hide()


func equipmentdeal():
	var i = 0
	for key in Equipment.equip:
		var name_label = Label.new()
		var data = Equipment.equip[key]
		name_label.text = data['name']
		i = i + 1
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.mouse_entered.connect(_on_equipment_hover.bind(data))
		name_label.mouse_exited.connect(_on_equipment_leave.bind(data))
		
		$margin/equipment.add_child(name_label)
		
func _on_equipment_hover(data):
	var equipment_info = Characters.labels_for_others.get(data)
	tagtip.text = data['description']
	tagtip.size = Vector2(400,100)
	var mouse_pos = get_viewport().get_mouse_position()
	tagtip.position =  mouse_pos + Vector2(3,15)
	print(tagtip.position)
	tagtip.show()				


func _on_equipment_leave(data):
	tagtip.hide()		
