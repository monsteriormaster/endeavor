#变量声明和常量定义
extends PopupPanel#弹出面板

## 人物详情面板。由 main_ui 的头像按钮 / 卡牌系统呼出，统一交给 OverlayRoot 托管：
##   OverlayRoot.push_overlay(panel, {"close_method": "close_panel"})
##   panel.setup("Hero")

signal closed

var tagtip = Label.new()

var info
var taginfo
var einfo
var _closing: bool = false
#资源文件路径
const TAGS = "res://resoures/tags.json"
#需要补充文件内容
const CHARACTERS = "res://resoures/characters.json"#角色
const EQUIPMENT = "res://resoures/equipment.json"#装备
const WID = 220
const LEN = 440

func _ready():
	tagtip.name = 'tagtip'
	tagtip.autowrap_mode = true
	tagtip.hide()
	$margin.add_child(tagtip)
	

func _process(_delta):
	pass


#关闭键
func _on_closebutton_pressed():
	close_panel()


## 关闭面板。Esc 与「关闭」按钮共用；重复调用安全。
## 旧实现只 hide()，节点会一直挂在树上，每次点头像都新建一个 → 泄漏且越叠越多。
func close_panel() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	# 未被 OverlayRoot 托管时（例如调试场景里直接 add_child）自行销毁
	if not OverlayRoot.close_overlay(self):
		queue_free()

func setup(character_name:String):
	get_info()
	info = Player.npc[character_name]
	
	var texture = load(info["image"])
	$margin/avatar.texture = texture
	var original_size = texture.get_size()
	var scale_ratio =  min(WID / original_size.x,LEN / original_size.y)
	$margin/avatar.position = Vector2(350, 200)
	$margin/avatar.scale = Vector2(scale_ratio, scale_ratio)
	
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
		if data not in taginfo:
			continue
		
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
	
		
