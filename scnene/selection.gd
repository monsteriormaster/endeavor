extends Node2D

const CONFIRM_DIALOG_PATH = "res://scnene/confirmdialog.tscn"

var gifts = Player.gifts
var check_boxes = []
var origin_gift_att = Player.gift_att
var origin_player_att = Player.player_att
var choose_condition = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	update_all_att_label()
	setup_buttons()
	update_button_states()
	setup_gift_selection()
	update_gift_label()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass


func _on_line_edit_text_changed(new_text):
	Player.player_name = new_text
	print("player name is " + Player.player_name)


func reduce_attribute(attribute_name: String):
	var attribute_value = Player.get("player_" + attribute_name)
	if attribute_value > 0 and Player.player_att <= 25:
		Player.set("player_" + attribute_name, attribute_value - 1)
		Player.change_att(1)
		update_att_label(attribute_name, attribute_value - 1)
		$attribute/Label.text ="可分配属性点" + str(Player.player_att)
		update_button_states()


func increase_attribute(attribute_name: String):
	var attribute_value =Player.get("player_" + attribute_name)
	if attribute_value < 10 and Player.player_att >= 1:
		Player.set("player_" + attribute_name, attribute_value + 1)
		Player.change_att(-1)
		update_att_label(attribute_name, attribute_value + 1)
		$attribute/Label.text ="可分配属性点" + str(Player.player_att)
		update_button_states()


func update_button_states():
	for attr in ["int", "app", "str", "bod"]:
		var add_button = get_node_or_null("attribute/addbox/%s" % attr)
		var minus_button = get_node_or_null("attribute/minusbox/%s" % attr)
		var value = Player.get("player_" + attr)
		
		add_button.disabled = Player.player_att == 0 or value == 10
		minus_button.disabled = value == 0 or Player.player_att == 25


func update_att_label(attribute_name: String, value: int):
	match attribute_name:
		"int":
			$attribute/value/int.text = str(value)
		"app":
			$attribute/value/app.text = str(value)
		"str":
			$attribute/value/str.text = str(value)
		"bod":
			$attribute/value/bod.text = str(value)	


func update_all_att_label()->void:
	update_att_label('int',Player.player_int)
	update_att_label('app',Player.player_app)
	update_att_label('str',Player.player_str)
	update_att_label('bod',Player.player_bod)


func disable_button(attribute_name: String, is_add: bool):
	var box = "addbox" if is_add else "minusbox"
	var button = get_node_or_null("attribute/%s/%s" % [box, attribute_name])
	if button:
		button.disabled = true	


func connect_button(button: Button, attribute: String, operation: String) -> void:
	button.connect("pressed", self._on_attribute_button_pressed.bind(attribute, operation))


func setup_buttons():
	connect_button($attribute/minusbox/int, "int", "minus")
	connect_button($attribute/minusbox/app, "app", "minus")
	connect_button($attribute/minusbox/str, "str", "minus")
	connect_button($attribute/minusbox/bod, "bod", "minus")
	connect_button($attribute/addbox/int, "int", "add")
	connect_button($attribute/addbox/app, "app", "add")
	connect_button($attribute/addbox/str, "str", "add")
	connect_button($attribute/addbox/bod, "bod", "add")  


func _on_attribute_button_pressed(attribute: String, operation: String):
	match operation:
		"add":
			increase_attribute(attribute)
		"minus":
			reduce_attribute(attribute)


func setup_gift_selection():
	var selection_area = $gift_container/passby/selection_area
	var description_area = $description_area
	
	print("desciption\n")
	description_area.bbcode_enabled = true
	description_area.text = ""
	
	for gift_name in Player.gifts:
		var gift_data = Player.gifts[gift_name]
		var hbox = HBoxContainer.new()
		var checkbox = CheckBox.new()
		var name_label = Label.new()
		name_label.text = gift_data.name + " " + gift_data.price
		
		choose_condition[gift_data.name] = false 
		
		checkbox.toggle_mode = true
		checkbox.disabled = Player.gift_att < int(gift_data.price)
		check_boxes.append({'checkbox': checkbox, 'price':int(gift_data.price),})
		checkbox.pressed.connect(_on_check_toggle.bind(checkbox,int(gift_data.price),str(gift_data.name)))
		
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		name_label.mouse_entered.connect(_on_gift_hover.bind(gift_data, description_area))
		name_label.mouse_exited.connect(_on_gift_leave.bind(description_area))
		
		hbox.add_child(checkbox)
		hbox.add_child(name_label)
		selection_area.add_child(hbox)


func _on_gift_hover(gift_data, description_area):
	print("悬停触发，礼物名称：", gift_data.name)
	var desc = "[b]名称[/b]：" + gift_data.name + "\n"
	desc += "[b]品质[/b]：" + gift_data.quality + "\n"
	desc += "[b]描述[/b]：" + gift_data.description + "\n"
	desc += "[b]效果[/b]：" + gift_data.effect + "\n\n"
	if gift_data.cor_label != '':
		desc += "[b]标签[/b]：" + '\n'
		var cor_labels = gift_data.cor_label.split(' ')
		for add_description in cor_labels:
			desc += add_description + '\n' +\
					Player.character_label[add_description].description + "\n"  
	
	description_area.text = desc


func _on_gift_leave(description_area):
	description_area.text = ""
	

func _on_check_toggle(curent_checkbox:CheckBox,price:int,name:String):
	if !curent_checkbox.button_pressed:
		Player.gift_att += price
		choose_condition[name] = false
		update_gift_label()
		update_checkbox_states()
	else:
		Player.gift_att -= int(price)
		choose_condition[name] = true
		update_gift_label()
		update_checkbox_states()	 		


func update_checkbox_states():
	for data in check_boxes:
		var cbox = data.checkbox
		var price = data.price
		cbox.disabled = Player.gift_att < price and !cbox.button_pressed
	
	
func update_gift_label():
	$gift_container/Label.text = "剩余天赋点：" + str(Player.gift_att)	


func _on_next_pressed():
	var minn = 10000000 #即天赋选完了的情况

	for data in choose_condition:
		if choose_condition[data] == false:
			minn = min(minn,int(gifts[data].price))
			
	if Player.gift_att >= minn && Player.player_att > 0:
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
		confirm_dialog.show_dialog()
		
	else:
		get_tree().change_scene_to_file('res://scnene/main.tscn')
	
func _on_pre_pressed():
	if Player.gift_att < origin_gift_att || Player.player_att < origin_player_att:
		var confirm_dialog = load(CONFIRM_DIALOG_PATH).instantiate()
		confirm_dialog.setup(
			"确认离开",
			"该页面不会保存，确定要离开吗？",
			"确认",
			"返回"
			)
		confirm_dialog.confirmed.connect(func (): get_tree().change_scene_to_file('res://scnene/loading.tscn'))
		remove_child(confirm_dialog)
		add_child(confirm_dialog)
		confirm_dialog.show_dialog()
	else:
		get_tree().change_scene_to_file('res://scnene/loading.tscn')	
