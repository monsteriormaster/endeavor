# TagRegistry —— tags.json / items/(equipment.json+goods.json) 的进程级缓存与属性派生
#
# 设计：派生属性（生效值 = 裸值 + Σ 已持有 tag 的 bonus），读取时现算，
# 不回写 Player 基础属性。Hero 镜像仍存裸值，零存档迁移。
# 对齐 EffectProcessor 模式：class_name 静态工具类，不加第 13 个 Autoload。
#
# 新增本文件后需重建类缓存： godot --headless --path . --import
#
# 消费方：
#   - script/player.gd               生效属性统一入口（effective_attrs_of / effective_self_attrs / effective_npc_attrs）
#   - components/character_panel.gd  属性卡显示 + tag 悬浮提示
#   - script/check_processor.gd     鉴定骰面（生效值）
#   - components/trigger_popup.gd   触发器 compare 判定 x / 副骰 sides_attr / multi 骰面 sum（生效值，2026-08-25）
#   - scene/selection.gd            天赋界面 tag 描述悬浮

class_name TagRegistry
extends RefCounted

const TAGS_PATH := "res://resoures/tags.json"
const EQUIPMENT_PATH := "res://resoures/items/equipment.json"
const GOODS_PATH := "res://resoures/items/goods.json"
const VALID_ATTRS := ["int", "app", "str", "bod"]

## 进程级缓存（首次访问读盘一次，之后内存命中）
static var _tag_cache: Dictionary = {}
static var _tag_loaded: bool = false
static var _equip_cache: Dictionary = {}
static var _equip_loaded: bool = false


# ============================================================
#  缓存（懒加载）
# ============================================================

static func _ensure_tags() -> Dictionary:
	if not _tag_loaded:
		var file := FileAccess.open(TAGS_PATH, FileAccess.READ)
		if file != null:
			var txt := file.get_as_text()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary:
				_tag_cache = parsed
			else:
				push_error("TagRegistry: tags.json 解析结果非 Dictionary")
			file.close()
		else:
			push_error("TagRegistry: 无法打开 %s" % TAGS_PATH)
		_tag_loaded = true
	return _tag_cache


static func _ensure_equipment() -> Dictionary:
	if not _equip_loaded:
		_equip_cache = {}
		# 装备 bonus 分散在 items/ 下：equipment.json（装备）+ goods.json（商品）。
		_load_equipment_file(EQUIPMENT_PATH)
		_load_equipment_file(GOODS_PATH)
		_equip_loaded = true
	return _equip_cache


static func _load_equipment_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var txt := file.get_as_text()
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			for key in parsed:
				_equip_cache[key] = parsed[key]
		else:
			push_error("TagRegistry: %s 解析结果非 Dictionary" % path)
		file.close()
	else:
		push_error("TagRegistry: 无法打开 %s" % path)


# ============================================================
#  查询 API
# ============================================================

static func has_tag(name: String) -> bool:
	return _ensure_tags().has(name)


## 返回完整 tag 字典 {name, description, bonus?}；未知 tag 返回 {}
static func get_tag(name: String) -> Dictionary:
	return _ensure_tags().get(name, {})


## 返回 tag 的 bonus 字典 {int/app/str/bod:int}。
## 无 bonus → {}；只认四属性键，未知键忽略 + push_warning（对齐「未识别报警」惯例）。
static func get_bonus(name: String) -> Dictionary:
	var tag: Dictionary = get_tag(name)
	var bonus: Variant = tag.get("bonus", null)
	if not (bonus is Dictionary):
		return {}
	var out: Dictionary = {}
	for k in bonus:
		var key := String(k)
		if key in VALID_ATTRS:
			out[key] = int(bonus[k])
		else:
			push_warning("TagRegistry: tag '%s' 的 bonus 含未知键 '%s'，已忽略" % [name, key])
	return out


## 返回 tag 的回合持续数（turn）。无 turn → 0（表示无计时/永久）。
## 「疲惫」等带 turn 的 tag 在获得时登记剩余回合，每「下一天」递减，归零移除。
## 未来物品（items/*.json）加 turn 时复用同一套到期机制，此处只管读取。
static func get_turn(name: String) -> int:
	var tag: Dictionary = get_tag(name)
	var tv: Variant = tag.get("turn", null)
	if tv is int or tv is float:
		return int(tv)
	return 0


## 装备描述查询（顺带消除 selection / character_panel 的重复读盘）
static func get_equipment(name: String) -> Dictionary:
	return _ensure_equipment().get(name, {})


## 装备属性 bonus（items/equipment.json + items/goods.json 的 bonus 字段，如多功能军刀 str+1）。
## 无 bonus → {}；只认四属性键，未知键忽略 + push_warning。
static func get_equipment_bonus(name: String) -> Dictionary:
	var eq: Dictionary = get_equipment(name)
	var bonus: Variant = eq.get("bonus", null)
	if not (bonus is Dictionary):
		return {}
	var out: Dictionary = {}
	for k in bonus:
		var key := String(k)
		if key in VALID_ATTRS:
			out[key] = int(bonus[k])
		else:
			push_warning("TagRegistry: 装备 '%s' 的 bonus 含未知键 '%s'，已忽略" % [name, key])
	return out


# ============================================================
#  显示与派生
# ============================================================

## 反转遍历方向：按注册表声明顺序返回「玩家可见」的 tag。
## 有界（注册表规模 ≈11），与玩家 tag 数无关；流程 tag（不在注册表）自动过滤。
static func display_tags(tags: Array) -> Array:
	var result: Array = []
	for tag_name in _ensure_tags().keys():
		if tag_name in tags:
			result.append(tag_name)
	return result


## 派生属性：生效值 = 裸值 + Σ(已持有 tag 的 bonus) + Σ(装备的 bonus)。不修改入参。
## attrs: 含 int/app/str/bod 的裸值字典（Player 或 NPC 通用）
## tags:  已持有 tag 数组
## equipments: 装备（Array=[装备名...] 或 Dictionary={槽位:装备名}），可空
static func effective_attrs(attrs: Dictionary, tags: Array, equipments: Variant = null) -> Dictionary:
	var out := {
		"int": int(attrs.get("int", 0)),
		"app": int(attrs.get("app", 0)),
		"str": int(attrs.get("str", 0)),
		"bod": int(attrs.get("bod", 0)),
	}
	for tag_name in tags:
		var bonus: Dictionary = get_bonus(String(tag_name))
		for k in bonus:
			out[String(k)] += int(bonus[k])
	for eq_name in _equipment_names(equipments):
		var eb: Dictionary = get_equipment_bonus(String(eq_name))
		for k in eb:
			out[String(k)] += int(eb[k])
	return out


## 从 equipment 字段提取装备名列表，兼容两种形态：
##   - Array（如主角 Player.player_equipment = ["多功能军刀"]）
##   - Dictionary（如 characters.json 预设 {slot: "装备名"} = {"weapon":"多功能军刀"}）
static func _equipment_names(equip: Variant) -> Array:
	var out: Array = []
	if equip is Array:
		for e in equip:
			out.append(String(e))
	elif equip is Dictionary:
		for v in (equip as Dictionary).values():
			out.append(String(v))
	return out
