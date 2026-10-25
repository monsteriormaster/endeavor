## 卡牌注册表（Autoload 单例）。
## 启动时加载 resoures/characters.json + resoures/items/ 下 equipment.json + goods.json + others.json，
## 构建 CardData 缓存，提供 按 id / 类型 / tag 查询。生命周期 = 整个应用，无清理需求。
extends Node

const CHARACTERS_PATH := "res://resoures/characters.json"
const EQUIPMENT_PATH := "res://resoures/items/equipment.json"
const GOODS_PATH := "res://resoures/items/goods.json"
const OTHERS_PATH := "res://resoures/items/others.json"

var _cards: Dictionary = {}              # id -> CardData
var _characters: Array[CardData] = []
var _items: Array[CardData] = []


func _ready() -> void:
	_load_characters()
	_load_items()
	print("[CardRegistry] 已加载 %d 张卡（人物 %d，道具 %d）" % [_cards.size(), _characters.size(), _items.size()])


# ============================================================
#  加载
# ============================================================

func _load_characters() -> void:
	var data := _load_json(CHARACTERS_PATH)
	for card_id in data:
		_register(CardData.from_character(String(card_id), data[card_id]))


func _load_items() -> void:
	# 道具卡分散在 items/ 下：equipment.json（装备）+ goods.json（商品）+ others.json（打听/剧情杂项：秘氛/困惑/博学等）。
	_load_item_file(EQUIPMENT_PATH)
	_load_item_file(GOODS_PATH)
	_load_item_file(OTHERS_PATH)


func _load_item_file(path: String) -> void:
	var data := _load_json(path)
	for card_id in data:
		_register(CardData.from_item(String(card_id), data[card_id]))


func _register(card: CardData) -> void:
	if card.id == "":
		push_error("[CardRegistry] 跳过空 id 的卡")
		return
	if _cards.has(card.id):
		push_warning("[CardRegistry] 重复卡 id 覆盖：%s" % card.id)
	_cards[card.id] = card
	match card.card_type:
		"character":
			_characters.append(card)
		"item":
			_items.append(card)
		_:
			push_warning("[CardRegistry] 未知 card_type '%s'（卡 %s）" % [card.card_type, card.id])


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[CardRegistry] 无法打开 %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[CardRegistry] %s 解析失败或非对象" % path)
		return {}
	return parsed


# ============================================================
#  公共 API
# ============================================================

## 按 id 取卡，找不到返回 null。
func get_card(card_id: String) -> CardData:
	return _cards.get(card_id, null)


## 按类型列出卡的副本（副本可安全修改，不影响注册表内部）。
func list_by_type(type_name: String) -> Array[CardData]:
	match type_name:
		"character":
			return _characters.duplicate()
		"item":
			return _items.duplicate()
		_:
			return [] as Array[CardData]


## 按 tag 筛卡（method=1 全部满足，0 任一满足）。
func list_by_tag(want: Array, method := 1) -> Array[CardData]:
	var out: Array[CardData] = []
	for card in _characters + _items:
		if card.has_tags(want, method):
			out.append(card)
	return out


## 全部卡的副本（人物 + 道具）。
func list_all() -> Array[CardData]:
	var out: Array[CardData] = []
	out.append_array(_characters)
	out.append_array(_items)
	return out


## D-DOC17（2026-08-26）：计算一组道具名（玩家装备/持有物）的鉴定结果加成总和。
## 「精心磨制的小刀」check_bonus=1 → 任意鉴定结果 +1。
func total_check_bonus(names: Array) -> int:
	var total := 0
	for n in names:
		var card: CardData = _cards.get(String(n), null)
		if card != null:
			total += int(card.check_bonus)
	return total
