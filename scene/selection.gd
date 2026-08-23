extends Node2D

const CONFIRM_DIALOG_PATH = "res://components/confirmdialog.tscn"
const GIFT = "res://resoures/gifts_begin.json"
const TAGS = "res://resoures/tags.json"

var gifts 
var tags
var check_boxes = []
var origin_gift_att = Player.gift_att
var origin_player_att = Player.player_att
var choose_condition = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	get_data()
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
	
	for gift_name in gifts:
		var gift_data = gifts[gift_name]
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
	var desc = "[b]名称[/b]：" + gift_data.name + "\n"
	desc += "[b]品质[/b]：" + gift_data.quality + "\n"
	desc += "[b]描述[/b]：" + gift_data.description + "\n"
	desc += "[b]效果[/b]：" + _format_effect(gift_data.effect) + "\n\n"
	if gift_data.cor_label != '':
		desc += "[b]标签[/b]：" + '\n'
		var cor_labels = gift_data.cor_label.split(' ')
		for add_description in cor_labels:
			desc += add_description + '\n' +\
					tags[add_description].description + "\n"

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
		confirm_dialog.confirmed.connect(before_trans)
		add_child(confirm_dialog)
		
	else:
		before_trans()
	
func _on_pre_pressed():
	if Player.gift_att < origin_gift_att || Player.player_att < origin_player_att:
		var confirm_dialog = load(CONFIRM_DIALOG_PATH).instantiate()
		confirm_dialog.setup(
			"确认离开",
			"该页面不会保存，确定要离开吗？",
			"确认",
			"返回"
			)
		confirm_dialog.confirmed.connect(func (): get_tree().change_scene_to_file('res://scene/loading.tscn'))
		add_child(confirm_dialog)
		
	else:
		get_tree().change_scene_to_file('res://scene/loading.tscn')	
		
func get_data():
	var file = FileAccess.open(GIFT,FileAccess.READ)
	gifts = JSON.parse_string(file.get_as_text())	
	file.close()
	file = FileAccess.open(TAGS,FileAccess.READ)
	tags = JSON.parse_string(file.get_as_text())	
	file.close()	
	

func before_trans():
	# 1. 初始化主角卡 Hero（属性先占位 0，effect+clamp 后再同步最终值）。
	#    先建 Hero 卡再 apply effect：避免 Player.npc = {Hero} 覆盖掉 effect 加进来的 npc（如"死生契阔"的法拉叶）。
	Player.npc = {
		"Hero":{
			"name" :"",
			"tags" :[],
			"int" :0,
			"str" :0,
			"bod" :0,
			"app" :0,
			"equipment":{},
			"description": "曾热爱艺术，家庭发生变故后，不得已继承家业放弃梦想。不过野心依旧。",
		}
	}
	# 2. 对所有已选天赋应用 effect（天赋无 flow_tags，tags/attrs/npc 等直接落 Player）。
	#    天赋名不再作为 tag 加入——天赋的效应完全由 effect 字典决定。
	for data in choose_condition:
		if choose_condition[data] == true:
			var eff: Dictionary = gifts[data].get("effect", {})
			if not eff.is_empty():
				EffectProcessor.apply(eff)
	# 3. 平凡可贵 clamp_attrs（最后生效，仅此界面；进入游戏后玩家可通过其他 effect 超出范围）
	_apply_clamp_attrs()
	# 4. 同步主角卡属性（含 effect 增减与 clamp 后的最终值）
	Player.npc["Hero"]["name"] =  Player.player_name
	Player.npc["Hero"]["int"] =  Player.player_int
	Player.npc["Hero"]["str"] =  Player.player_str
	Player.npc["Hero"]["bod"] =  Player.player_bod
	Player.npc["Hero"]["app"] =  Player.player_app
	# 角色创建完成后自动进入新手引导；若教学已完成（读档/二周目）则直接进主城。
	# 先确定目标场景并写入存档路径，再存档、切场景（避免存档里 path 为空导致回档跳关）。
	if TutorialManager.is_completed("opening"):
		Player.path = "res://scene/main.tscn"
	else:
		Player.path = "res://scene/guide.tscn"
	SaveLoader.save_game()
	get_tree().change_scene_to_file(Player.path)


## 平凡可贵：属性夹值（最后生效，仅 selection 界面）。
## 扫描已选天赋的 clamp_attrs，取最严约束（min 取最大、max 取最小），
## 对 int/app/str/bod 执行一次性夹值。仅在该界面生效一次，非持续 modifier。
func _apply_clamp_attrs() -> void:
	var clamp_min := -9999
	var clamp_max := 9999
	var has_clamp := false
	for data in choose_condition:
		if choose_condition[data] == true:
			var eff: Dictionary = gifts[data].get("effect", {})
			if eff.has("clamp_attrs"):
				has_clamp = true
				var c: Dictionary = eff["clamp_attrs"]
				clamp_min = max(clamp_min, int(c.get("min", -9999)))
				clamp_max = min(clamp_max, int(c.get("max", 9999)))
	if not has_clamp:
		return
	Player.player_int = clampi(Player.player_int, clamp_min, clamp_max)
	Player.player_app = clampi(Player.player_app, clamp_min, clamp_max)
	Player.player_str = clampi(Player.player_str, clamp_min, clamp_max)
	Player.player_bod = clampi(Player.player_bod, clamp_min, clamp_max)
	Player.notify_stats_changed()


## 把 effect 字典格式化为可读文本（用于描述区显示，替代旧的字符串 effect）。
func _format_effect(eff: Dictionary) -> String:
	if not (eff is Dictionary) or eff.is_empty():
		return "无"
	var parts: Array = []
	if eff.has("attrs"):
		var attrs: Dictionary = eff["attrs"]
		var names := {"int": "智力", "app": "魅力", "str": "力量", "bod": "体魄"}
		for k in attrs:
			var n: String = names.get(String(k), String(k))
			parts.append("%s%+d" % [n, int(attrs[k])])
	if eff.has("tags"):
		parts.append("获得标签：" + " ".join(eff["tags"]))
	if eff.has("num_tags"):
		var nt: Dictionary = eff["num_tags"]
		var segs: Array = []
		for k in nt:
			segs.append("%s=%d" % [k, int(nt[k])])
		parts.append("可堆叠词条：" + " ".join(segs))
	if eff.has("stuff"):
		parts.append("获得物品：" + " ".join(eff["stuff"]))
	if eff.has("money"):
		parts.append("金钱%+d" % int(eff["money"]))
	if eff.has("npc"):
		var npcs: Array = []
		for nk in eff["npc"]:
			npcs.append(String(nk))
		parts.append("获得同伴：" + " ".join(npcs))
	if eff.has("equipment"):
		parts.append("获得装备")
	if eff.has("remove_tags"):
		parts.append("移除标签：" + " ".join(eff["remove_tags"]))
	if eff.has("remove_num_tags"):
		parts.append("移除可堆叠词条")
	if eff.has("goto_scene"):
		parts.append("前往新场景")
	if eff.has("child"):
		parts.append("获得孩子")
	if eff.has("name_child"):
		parts.append("为孩子取名")
	if eff.has("clamp_attrs"):
		var c: Dictionary = eff["clamp_attrs"]
		parts.append("属性夹至[%d,%d]" % [int(c.get("min", 0)), int(c.get("max", 0))])
	if parts.is_empty():
		return "无"
	return "，".join(parts)
