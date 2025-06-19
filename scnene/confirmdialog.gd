extends Popup

@export var my_title: String = ''
@export var message:String = ''
@export var confirm_text:String = '确认'
@export var cancel_text:String = '取消'

signal confirmed()
signal canceled()

@onready var title_ele: Label = $dialogbox/title
@onready var message_ele: Label = $dialogbox/message
@onready var cancel_button_ele: Button = $dialogbox/buttonbox/cancelbutton
@onready var confirm_button_ele: Button = $dialogbox/buttonbox/confirmbutton



func _ready():
	update_ui()
	if cancel_button_ele:
		cancel_button_ele.pressed.connect(_on_cancel_pressed.bind())
		confirm_button_ele.pressed.connect(_on_confirm_pressed.bind())
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

 
func update_ui():
	print("title_ele 存在：", title_ele != null)
	print("message_ele 存在：", message_ele != null)
	print("cancel_button_ele 存在：", cancel_button_ele != null)
	print("confirm_button_ele 存在：", confirm_button_ele != null)
	if title_ele:	
		print("已经update_ui了\n")
		title_ele.text = my_title
		message_ele.text = message
		cancel_button_ele.text = cancel_text
		confirm_button_ele.text = confirm_text

	
func setup(cur_title:String, cur_message:String,
			cur_confirm_text:String ='确认', cur_cancel_text:String = '取消'):
	print("已经setup了\n")
	my_title = cur_title
	message = cur_message
	confirm_text = cur_confirm_text
	cancel_text = cur_cancel_text
	update_ui()


func show_dialog(pause_game: bool = true):
	print("已经show了\n")
	popup_centered()
	if pause_game:
		get_tree().paused = true

	 
func _on_confirm_pressed():
	emit_signal("confirmed")
	close_dialog()
	
	
func _on_cancel_pressed():
	emit_signal("canceled")
	close_dialog()
	

func close_dialog():
	if get_tree().paused:
		get_tree().paused = false  
	queue_free()	
