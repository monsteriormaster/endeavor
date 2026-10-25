## 结算弹窗 —— 异步行动倒计时归零后，由 UI 打开，展示效果文本，
## 右下角一个「确定」按钮；点确定回调落地（扣钱/入书卡/归还人物卡/触发剧情），
## 然后自行销毁。设计为无全屏遮罩（mouse_filter=IGNORE 根节点），
## 弹窗外的空白点击穿透，便于与卡牌区同屏。
class_name ResultPopup
extends Control

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/TitleBar/Title
@onready var text_label: Label = $Panel/Margin/VBox/Content/TextLabel
@onready var confirm_btn: Button = $Panel/BottomBar/ConfirmButton

var _result: Dictionary = {}
var _on_confirm: Callable = Callable()


func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm_pressed)
	_center_panel()


func _center_panel() -> void:
	var vp := get_viewport_rect().size
	panel.position = (vp - panel.size) / 2.0


## result: 统一结算字典 {text, effect, plot, ...}（仅用 text 展示；effect 由 on_confirm 落地）。
## on_confirm: 点「确定」时回调，签名为 func(result: Dictionary)。
func setup(result: Dictionary, on_confirm: Callable, title := "结算") -> void:
	_result = result
	_on_confirm = on_confirm
	title_label.text = title
	text_label.text = String(result.get("text", ""))


func _on_confirm_pressed() -> void:
	if _on_confirm.is_valid():
		_on_confirm.call(_result)
	if is_instance_valid(self):
		queue_free()
