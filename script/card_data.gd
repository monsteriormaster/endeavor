## 卡牌数据（只读 Resource）—— 统一人物卡 / 道具卡的数据模型。
## 人物卡来源：resoures/characters.json；道具卡来源：resoures/items/ 下 equipment.json + goods.json + others.json。
## 由 CardRegistry autoload 在启动时构建并缓存，业务代码不直接 new。
class_name CardData
extends Resource

@export var id: String = ""                  # JSON 顶层键，如 "Falayee" / "多功能军刀"
@export var card_type: String = ""           # "character" | "item"
@export var display_name: String = ""        # 中文显示名
@export var attrs: Dictionary = {}           # {int,app,str,bod}（人物卡）
@export var bonus: Dictionary = {}           # {attr:+n}（道具卡）
@export var check_bonus: int = 0             # 鉴定结果加成（任意鉴定+1，如"精心磨制的小刀"）
@export var tags: Array[String] = []
@export var price: int = 0                 # 商品售价（金钱；goods.json 商品卡用，0=非卖品）
@export var consumable: bool = false         # 道具卡是否分配时消耗
@export var card_class: Array[String] = ["未知"]  # 物品类别（可多值），如 ["book"] / ["book","equipment"]；缺省["未知"]
@export var level: String = ""              # 品质档位：SSR / SR / S / R（无则 ""）；排序「有等级的按从高到低」用
## 手牌「可重复持有」标签。**全工程唯一来源**（D-HAND1，2026-10-14）—— CardArea 的
## 唯一性判定与 Player.hand 账本的去重都走 `is_stackable()`，别在别处再写一遍字面量。
const STACKABLE_TAG := "可堆叠"

@export var icon_path: String = ""           # 贴图 res:// 路径
@export var description: String = ""


# ============================================================
#  工厂
# ============================================================

## 从 characters.json 的一项构建人物卡。
static func from_character(card_id: String, data: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.card_type = "character"
	card.display_name = String(data.get("name", card_id))
	card.attrs = {
		"int": int(data.get("int", 0)),
		"app": int(data.get("app", 0)),
		"str": int(data.get("str", 0)),
		"bod": int(data.get("bod", 0)),
	}
	card.tags = _to_string_array(data.get("tags", []))
	card.icon_path = String(data.get("image", ""))
	card.description = String(data.get("description", ""))
	return card


## 从 items/equipment.json 或 items/goods.json 的一项构建道具卡（需已清理为结构化 bonus + tags）。
static func from_item(card_id: String, data: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.card_type = "item"
	card.display_name = String(data.get("name", card_id))
	card.level = String(data.get("level", ""))
	card.bonus = _to_int_dict(data.get("bonus", {}))
	card.check_bonus = int(data.get("check_bonus", 0))
	card.tags = _to_string_array(data.get("tags", []))
	card.card_class = _to_class_array(data.get("class", []))
	card.price = int(data.get("price", 0))
	card.consumable = bool(data.get("consumable", false))
	card.icon_path = String(data.get("icon", ""))
	card.description = String(data.get("description", ""))
	return card


# ============================================================
#  查询
## 从 items/books.json 的一项构建书籍卡（道具类，card_class 默认为 ["book"]）。
## 购书后入卡牌区展示用，不入 CardRegistry 注册表。
## ⚠️ 2026-10-08 补 `level` / `icon_path`：原先漏读这两项 ⇒ books.json 写了 `icon` 也不显示
##    （card_chip 的图像区直接吃 `icon_path`）、`level_rank()` 恒为 0（整理排序里书永远排最后）。
static func from_book(book_id: String, data: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = book_id
	card.card_type = "item"
	card.display_name = String(data.get("name", book_id))
	card.level = String(data.get("level", ""))
	card.card_class = _to_class_array(data.get("class", ["book"]))
	card.tags = _to_string_array(data.get("tags", []))
	card.icon_path = String(data.get("icon", ""))
	card.description = String(data.get("description", ""))
	return card


# ============================================================

## 该卡是否带全部指定 tag（method=1 全部满足，0 任一满足）。
func has_tags(want: Array, method := 1) -> bool:
	if method == 1:
		return want.all(func(t): return String(t) in tags)
	return want.any(func(t): return String(t) in tags)


## 消耗品判定（2026-09-08）：JSON 字段 consumable=true **或** 带 tag「消耗」都算消耗品。
## 单一来源，避免「消耗」tag 与 consumable 字段两套口径分叉。
## 语义边界：消耗 = 用于触发器后**不归还**（_return_cards / _consume_placed_consumables /
## ActionQueue._land 的返还过滤以此为据）。与「可堆叠」（手牌可否重复持有）是**正交维度**，
## 本方法不参与 CardArea 唯一性判定；不可堆叠的消耗品一样用后即没。
func is_consumable() -> bool:
	return consumable or ("消耗" in tags)


## 手牌能否重复持有多张（CardArea 唯一性规则的唯一例外）。
## 与「消耗」正交：消耗 = 使用后不归还；可堆叠 = 手牌里能攒多张。二者互不可推导。
func is_stackable() -> bool:
	return has_tags([STACKABLE_TAG], 1)


# ============================================================
#  持久化快照（D-HAND1 手牌账本）
# ============================================================

## 序列化为纯 JSON 字典（可直接进 SaveLoader 白名单字段）。
##
## 用途：手牌必须跨场景/跨读档存活，而**书卡不入 CardRegistry**、部分卡又是运行时构造的
## （npc 实时条目 / 打听物品），光记 id 换不回来 —— 所以账本存的是整张卡的数据快照。
## ⚠️ 快照只作**兜底**：兑现时（EffectProcessor.resolve_hand_entry）优先走实时数据源
##    （主角 → Player.get_hero_card / npc 条目 / CardRegistry），取不到才落到快照，
##    否则 npc 被改名、孩子属性成长、道具被改数值后手牌会显示旧数据。
func to_data() -> Dictionary:
	return {
		"id": id,
		"card_type": card_type,
		"display_name": display_name,
		"attrs": attrs.duplicate(true),
		"bonus": bonus.duplicate(true),
		"check_bonus": check_bonus,
		"tags": _to_string_array(tags),
		"price": price,
		"consumable": consumable,
		"card_class": _to_string_array(card_class),
		"level": level,
		"icon_path": icon_path,
		"description": description,
	}


## 由 to_data() 的字典还原一张卡（存档回读用）。缺键一律回落默认值，不崩。
static func from_data(d: Dictionary) -> CardData:
	var c := CardData.new()
	c.id = String(d.get("id", ""))
	c.card_type = String(d.get("card_type", ""))
	c.display_name = String(d.get("display_name", c.id))
	var raw_attrs: Variant = d.get("attrs", {})
	c.attrs = (raw_attrs as Dictionary).duplicate(true) if raw_attrs is Dictionary else {}
	var raw_bonus: Variant = d.get("bonus", {})
	c.bonus = (raw_bonus as Dictionary).duplicate(true) if raw_bonus is Dictionary else {}
	c.check_bonus = int(d.get("check_bonus", 0))
	c.tags = _to_string_array(d.get("tags", []) as Array)
	c.price = int(d.get("price", 0))
	c.consumable = bool(d.get("consumable", false))
	c.card_class = _to_class_array(d.get("card_class", ["未知"]))
	c.level = String(d.get("level", ""))
	c.icon_path = String(d.get("icon_path", ""))
	c.description = String(d.get("description", ""))
	return c


## 道具卡对某属性的加成（人物卡返回 0）。
func get_bonus(attr_name: String) -> int:
	if card_type != "item":
		return 0
	return int(bonus.get(attr_name, 0))


# ============================================================
#  排序辅助（手牌区「整理 / 提示态」共用，单一来源）
# ============================================================

## 道具卡子类在「分类排序」里的次级序号：武器=1 / 防具=2 / 饰品=3 / 书=4 / 其他=5。
## 依据 card_class 命中（多 class 取首个命中）；人物卡不走此方法（大类已在比较器里区分）。
func category_minor() -> int:
	if card_type != "item":
		return 0
	if "weapon" in card_class:
		return 1
	if "armor" in card_class:
		return 2
	if "jewelry" in card_class:
		return 3
	if "book" in card_class:
		return 4
	return 5


## 品质档位排序值：SSR=4 / SR=3 / S=2 / R=1 / 空或其他=0（从「从高到低」）。
func level_rank() -> int:
	match String(level).to_upper():
		"SSR":
			return 4
		"SR":
			return 3
		"S":
			return 2
		"R":
			return 1
		_:
			return 0


## 数值区间档（稳定排序用）：1-3→1 / 4-6→2 / 7-9→3 / 10→4 / 0或越界→0。
## 与游戏数值标度一致（5=正常人，10=人类极限）；同档视为相等，保持原始相对顺序。
static func attr_tier(value: int) -> int:
	if value <= 0:
		return 0
	if value <= 3:
		return 1
	if value <= 6:
		return 2
	if value <= 9:
		return 3
	return 4


# ============================================================
#  鉴定辅助（与 CheckProcessor 加权平均一致，单一来源）
# ============================================================

## 加权平均骰面 x = (Σ attr×weight)/(Σ weight)，向下取整，至少 1。
## attrs 可来自人物卡 .attrs，也可来自 Player 属性字典；weights 来自 check.attrs。
static func weighted_x(attrs: Dictionary, weights: Dictionary) -> int:
	var weighted_sum := 0
	var weight_total := 0
	for attr_name in weights:
		if not attrs.has(attr_name):
			continue
		var weight := int(weights[attr_name])
		weighted_sum += int(attrs[attr_name]) * weight
		weight_total += weight
	if weight_total == 0:
		return 1
	return max(1, int(float(weighted_sum) / float(weight_total)))


# ============================================================
#  内部
# ============================================================

static func _to_string_array(raw: Array) -> Array[String]:
	var out: Array[String] = []
	for v in raw:
		out.append(String(v))
	return out


## 物品类别：支持字符串或数组，缺省/空 → ["未知"]。
## 应对可能的多类别特殊物品（如既是书、又可作为装备的书）。
static func _to_class_array(raw) -> Array[String]:
	var out: Array[String] = []
	if typeof(raw) == TYPE_STRING:
		if raw != "":
			out.append(String(raw))
		return out
	if typeof(raw) == TYPE_ARRAY:
		for v in raw:
			var s := String(v)
			if s != "":
				out.append(s)
	if out.is_empty():
		out.append("未知")
	return out


static func _to_int_dict(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in raw:
		out[k] = int(raw[k])
	return out
