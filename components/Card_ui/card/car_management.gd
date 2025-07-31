extends Node

@export var card_group: Array[NodePath]  # 在编辑器中指定所有卡牌节点
var cards := []

func _ready() -> void:
	# 收集所有卡牌引用
	for path in card_group:
		var card = get_node(path)
		if card:
			cards.append(card)
	
	# 初始全部折叠
	fold_all_cards()

# 外部调用的展开/折叠函数
func expand_all_cards() -> void:
	for card in cards:
		card.expand()

func fold_all_cards() -> void:
	for card in cards:
		card.fold()

# 示例：绑定到UI按钮
func _on_expand_button_pressed() -> void:
	expand_all_cards()

func _on_collapse_button_pressed() -> void:
	fold_all_cards()
