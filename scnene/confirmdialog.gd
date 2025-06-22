extends PopupPanel

var my_title: String = ''
var message:String = ''
var confirm_text:String = '确认'
var cancel_text:String = '取消'

signal confirmed()
signal canceled()

@onready var title_ele: Label = $dialogbox/title
@onready var message_ele: Label = $dialogbox/message
@onready var cancel_button_ele: Button = $dialogbox/buttonbox/cancelbutton
@onready var confirm_button_ele: Button = $dialogbox/buttonbox/confirmbutton



func _ready():
	pass
	
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

 
func update_ui():
		print("已经update_ui了\n")
		$dialogbox/title.text = my_title
		$dialogbox/message.text = message
		$dialogbox/buttonbox/cancelbutton.text = cancel_text
		$dialogbox/buttonbox/confirmbutton.text = confirm_text
		$dialogbox/buttonbox/cancelbutton.pressed.connect(_on_cancel_pressed.bind())
		$dialogbox/buttonbox/confirmbutton.pressed.connect(_on_confirm_pressed.bind())
	
func setup(cur_title:String, cur_message:String,
			cur_confirm_text:String ='确认', cur_cancel_text:String = '取消'):
	print("已经setup了\n")
	my_title = cur_title
	message = cur_message
	confirm_text = cur_confirm_text
	cancel_text = cur_cancel_text
	update_ui()

	 
func _on_confirm_pressed():
	emit_signal("confirmed")
	close_dialog()
	
	
func _on_cancel_pressed():
	emit_signal("canceled")
	close_dialog()
	

func close_dialog():
	queue_free()	
