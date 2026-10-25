extends PanelContainer

## QuickBug —— 调试用快捷面板。
##
## 功能：
##   ① 自由添加卡片：任选人物卡 / 道具卡 / 书籍卡加入主 UI 手牌区（CardArea）。
##      道具卡覆盖 items/ 下 equipment/goods/others（含秘氛/困惑/博学），书籍卡覆盖 items/books.json。
##   ② 为任意角色（主角 Hero / 任意 NPC，含未入队角色）增删 tags（词条）。
##   ③ 修改任意角色的数值（attrs：int/app/str/bod），支持「设为」/「增加」。
##   ④ 修改任意角色的 num_tags（可堆叠词条），支持「设为」/「增加」。
##
## 实现：直接操作 Player 运行时数据（调试自由，不受奖励封顶 / 门控约束），
## 修改后同步 Hero 镜像（hero_merge）并广播 stats_changed 刷新 HUD。
## 角色落点：Hero → Player.player_*；NPC → Player.npc[key] 条目
## （条目不存在时从 characters.json 加载完整预设，见 _ensure_entry）。
##
## 用法：
##   QuickBug.open()                                              # 一行呼出（挂 OverlayRoot）
##   OverlayRoot.push_overlay(inst, {"modal": false, "close_method": "close_panel"})
class_name QuickBug

const TAGS_PATH := "res://resoures/tags.json"
const BOOKS_PATH := "res://resoures/items/books.json"
const ATTRS := ["int", "app", "str", "bod"]
const ATTR_CN := {"int": "智力", "app": "魅力", "str": "力量", "bod": "体魄"}

signal closed

## 目标下拉 -> Player.npc 键（索引对齐）；首项恒为 "Hero"。
var _target_keys: Array[String] = []
## 卡片下拉 -> CardData（索引对齐）。
var _cards: Array[CardData] = []

var _card_selector: OptionButton
var _target_selector: OptionButton
var _tag_preset: OptionButton
var _tag_name: LineEdit
var _num_tag_name: LineEdit
var _num_tag_value: SpinBox
var _num_tag_mode: OptionButton
var _attr_selector: OptionButton
var _attr_value: SpinBox
var _attr_mode: OptionButton
var _state_label: Label
var _log_label: Label


## 一行呼出：实例化并挂到 OverlayRoot（非模态，Esc 可关）。
static func open() -> QuickBug:
	var scene: PackedScene = load("res://components/quick_bug.tscn")
	var node: QuickBug = scene.instantiate() as QuickBug
	OverlayRoot.push_overlay(node, {"modal": false, "esc_closes": true, "close_method": "close_panel"})
	return node


func _ready() -> void:
	position = Vector2(40, 96)
	_build_ui()
	_refresh_cards()
	_refresh_targets()
	_refresh_tag_preset()
	_refresh_state()


# ============================================================
#  UI 构建
# ============================================================

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# 标题 + 关闭
	var title_row := HBoxContainer.new()
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = "QuickBug 调试面板"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.pressed.connect(close_panel)
	title_row.add_child(close_btn)

	# ⓪ 存档
	vbox.add_child(_make_section_label("⓪ 存档"))
	var save_row := HBoxContainer.new()
	vbox.add_child(save_row)
	var load_save_btn := Button.new()
	load_save_btn.text = "读取初始存档"
	load_save_btn.pressed.connect(_load_initial_save)
	save_row.add_child(load_save_btn)
	var set_save_btn := Button.new()
	set_save_btn.text = "设置初始存档"
	set_save_btn.pressed.connect(_save_initial_save)
	save_row.add_child(set_save_btn)

	# ① 添加卡片
	vbox.add_child(_make_section_label("① 添加卡片到手牌"))
	var card_row := HBoxContainer.new()
	vbox.add_child(card_row)
	_card_selector = OptionButton.new()
	_card_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.add_child(_card_selector)
	var add_card_btn := Button.new()
	add_card_btn.text = "添加到手牌"
	add_card_btn.pressed.connect(_add_card_to_hand)
	card_row.add_child(add_card_btn)

	# ② 目标角色
	vbox.add_child(_make_section_label("② 选择目标角色"))
	var target_row := HBoxContainer.new()
	vbox.add_child(target_row)
	_target_selector = OptionButton.new()
	_target_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_selector.item_selected.connect(func(_i: int) -> void: _refresh_state())
	target_row.add_child(_target_selector)
	var refresh_btn := Button.new()
	refresh_btn.text = "刷新"
	refresh_btn.pressed.connect(_refresh_targets)
	target_row.add_child(refresh_btn)

	# 目标状态显示
	_state_label = Label.new()
	_state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_state_label)

	# ③ tags
	vbox.add_child(_make_section_label("③ tags（词条）"))
	var tag_preset_row := HBoxContainer.new()
	vbox.add_child(tag_preset_row)
	_tag_preset = OptionButton.new()
	_tag_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_preset.item_selected.connect(_on_tag_preset_selected)
	tag_preset_row.add_child(_tag_preset)
	var tag_row := HBoxContainer.new()
	vbox.add_child(tag_row)
	_tag_name = LineEdit.new()
	_tag_name.placeholder_text = "tag 名（可自由输入）"
	_tag_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_row.add_child(_tag_name)
	var add_tag_btn := Button.new()
	add_tag_btn.text = "添加"
	add_tag_btn.pressed.connect(_add_tag)
	tag_row.add_child(add_tag_btn)
	var remove_tag_btn := Button.new()
	remove_tag_btn.text = "移除"
	remove_tag_btn.pressed.connect(_remove_tag)
	tag_row.add_child(remove_tag_btn)

	# ④ num_tags
	vbox.add_child(_make_section_label("④ num_tags（可堆叠词条）"))
	var num_row := HBoxContainer.new()
	vbox.add_child(num_row)
	_num_tag_name = LineEdit.new()
	_num_tag_name.placeholder_text = "num_tag 名"
	_num_tag_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	num_row.add_child(_num_tag_name)
	_num_tag_value = _make_spin(-999, 999)
	num_row.add_child(_num_tag_value)
	_num_tag_mode = _make_mode_selector()
	num_row.add_child(_num_tag_mode)
	var num_btn := Button.new()
	num_btn.text = "应用"
	num_btn.pressed.connect(_apply_num_tag)
	num_row.add_child(num_btn)

	# ⑤ attrs
	vbox.add_child(_make_section_label("⑤ 数值（attrs）"))
	var attr_row := HBoxContainer.new()
	vbox.add_child(attr_row)
	_attr_selector = OptionButton.new()
	for a in ATTRS:
		_attr_selector.add_item(ATTR_CN[a])
	attr_row.add_child(_attr_selector)
	_attr_value = _make_spin(-99, 99)
	attr_row.add_child(_attr_value)
	_attr_mode = _make_mode_selector()
	attr_row.add_child(_attr_mode)
	var attr_btn := Button.new()
	attr_btn.text = "应用"
	attr_btn.pressed.connect(_apply_attr)
	attr_row.add_child(attr_btn)

	# 日志
	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.modulate = Color(0.7, 0.9, 0.7)
	vbox.add_child(_log_label)


func _make_section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	return l


func _make_spin(min_v: float, max_v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 1
	s.value = 0
	s.custom_minimum_size.x = 80
	return s


func _make_mode_selector() -> OptionButton:
	var o := OptionButton.new()
	o.add_item("设为")
	o.add_item("增加")
	return o


# ============================================================
#  关闭
# ============================================================

func close_panel() -> void:
	closed.emit()
	if not OverlayRoot.close_overlay(self):
		queue_free()


# ============================================================
#  ⓪ 存档
# ============================================================

## 读取初始存档：把 user://endeavoursavegame.json 灌进 Player（不切场景，保留面板）。
func _load_initial_save() -> void:
	var data := SaveLoader.read_save_file()
	if data.is_empty():
		_log("读取初始存档失败：%s" % SaveLoader.last_error)
		return
	SaveLoader.apply_save_data(data)
	_refresh_targets()
	_refresh_state()
	_log("已读取初始存档（第%d天）" % int(data.get("time", 1)))


## 设置初始存档：把 resoures/characters.json 的所有角色导入 Player.npc（各自应在的位置），
## 主角属性取 Hero 预设，重置其余字段回白名单默认、写 path 并保存为初始存档。
func _save_initial_save() -> void:
	var chars := _load_characters_json()
	if chars.is_empty():
		_log("characters.json 为空或无法读取")
		return
	# 重置 Player 到白名单默认（清空 tags/npc/money/time 等回初始）
	SaveLoader.reset_to_new_game()
	# 导入所有角色到 npc（角色预设 → Player.npc 各条目）
	Player.npc = {}
	for key in chars:
		var entry: Variant = chars[key]
		if entry is Dictionary:
			Player.npc[String(key)] = (entry as Dictionary).duplicate(true)
	# 主角属性取 Hero 预设
	var hero: Variant = Player.npc.get("Hero", null)
	if hero is Dictionary:
		Player.player_name = String(hero.get("name", "主角"))
		Player.player_int = int(hero.get("int", 0))
		Player.player_app = int(hero.get("app", 0))
		Player.player_str = int(hero.get("str", 0))
		Player.player_bod = int(hero.get("bod", 0))
	Player.path = "res://scene/main.tscn"
	SaveLoader.save_game()
	_refresh_targets()
	_refresh_state()
	_log("已设置初始存档（导入 %d 个角色）" % Player.npc.size())


## 读 resoures/characters.json 为字典（角色预设）。
func _load_characters_json() -> Dictionary:
	var f := FileAccess.open("res://resoures/characters.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


# ============================================================
#  ① 添加卡片
# ============================================================

func _refresh_cards() -> void:
	_cards.clear()
	_card_selector.clear()
	# 人物卡 + 已注册道具卡（equipment/goods/others，含秘氛/困惑/博学等）
	for card in CardRegistry.list_all():
		_cards.append(card)
		var type_cn := "人物" if card.card_type == "character" else "道具"
		_card_selector.add_item("[%s] %s（%s）" % [type_cn, card.display_name, card.id])
	# 书籍卡（books.json 不入注册表，走 from_book；用于读书/书店系统）
	for book in _load_books_cards():
		_cards.append(book)
		_card_selector.add_item("[书] %s（%s）" % [book.display_name, book.id])


## 读 items/books.json 为书籍卡（CardData.from_book），不入 CardRegistry 注册表。
func _load_books_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	var f := FileAccess.open(BOOKS_PATH, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for book_id in parsed:
			var data: Variant = parsed[book_id]
			if data is Dictionary:
				out.append(CardData.from_book(String(book_id), data))
	return out


func _add_card_to_hand() -> void:
	if _cards.is_empty():
		_log("注册表无卡")
		return
	var idx := _card_selector.selected
	if idx < 0 or idx >= _cards.size():
		_log("未选中卡片")
		return
	var card: CardData = _cards[idx]
	var ca: CardArea = TriggerManager.get_card_area()
	if ca == null:
		_log("未注册手牌区（CardArea 不存在）")
		return
	if ca.add_card(card):
		_log("已加卡：%s" % card.display_name)
	else:
		_log("加卡失败：%s（已存在且不可堆叠）" % card.display_name)


# ============================================================
#  ② 目标角色
# ============================================================

func _refresh_targets() -> void:
	var prev := _current_key()
	_target_keys.clear()
	_target_keys.append("Hero")
	for key in Player.npc:
		if String(key) != "Hero":
			_target_keys.append(String(key))
	for card in CardRegistry.list_by_type("character"):
		if not _target_keys.has(card.id):
			_target_keys.append(card.id)
	_target_selector.clear()
	for key in _target_keys:
		_target_selector.add_item(_target_label(key))
	var idx := _target_keys.find(prev)
	if idx >= 0:
		_target_selector.select(idx)
	_refresh_state()


func _target_label(key: String) -> String:
	if key == "Hero":
		return "主角（Hero）"
	var entry: Variant = Player.npc.get(key, null)
	if entry is Dictionary and String(entry.get("name", "")) != "":
		return "%s（%s）" % [String(entry["name"]), key]
	return key


func _current_key() -> String:
	if _target_selector == null or _target_keys.is_empty():
		return "Hero"
	var idx := _target_selector.selected
	if idx < 0 or idx >= _target_keys.size():
		return "Hero"
	return _target_keys[idx]


## 确保 NPC 条目存在（不存在则从 characters.json 加载预设，保证 name/image/attrs 完整），
## 并补齐 tags / num_tags 字段。Hero 不走这里（Hero 数据在 Player.player_*）。
func _ensure_entry(key: String) -> Dictionary:
	if not Player.npc.has(key):
		Player.npc[key] = EffectProcessor._load_preset_npc(key)
	var entry: Dictionary = Player.npc[key]
	if not entry.has("tags"):
		entry["tags"] = []
	if not entry.has("num_tags"):
		entry["num_tags"] = {}
	return entry


func _refresh_state() -> void:
	if _state_label == null:
		return
	var key := _current_key()
	var tags: Array = []
	var num_tags: Dictionary = {}
	var attrs := {"int": 0, "app": 0, "str": 0, "bod": 0}
	if key == "Hero":
		tags = Player.player_tags
		num_tags = Player.player_num_tags
		attrs = {
			"int": Player.player_int, "app": Player.player_app,
			"str": Player.player_str, "bod": Player.player_bod,
		}
	else:
		var entry: Variant = Player.npc.get(key, {})
		if entry is Dictionary:
			tags = entry.get("tags", [])
			num_tags = entry.get("num_tags", {})
			attrs = {
				"int": int(entry.get("int", 0)), "app": int(entry.get("app", 0)),
				"str": int(entry.get("str", 0)), "bod": int(entry.get("bod", 0)),
			}
	var attr_parts: Array = []
	for a in ATTRS:
		attr_parts.append("%s%d" % [ATTR_CN[a], int(attrs[a])])
	var num_parts: Array = []
	for k in num_tags:
		num_parts.append("%s=%s" % [String(k), str(num_tags[k])])
	var state := "目标：%s\n" % _target_label(key)
	state += "数值：%s\n" % " ".join(attr_parts)
	state += "tags：%s\n" % (" ".join(tags) if tags.size() > 0 else "（无）")
	state += "num_tags：%s" % (", ".join(num_parts) if num_parts.size() > 0 else "（无）")
	_state_label.text = state


# ============================================================
#  ③ tags
# ============================================================

func _refresh_tag_preset() -> void:
	_tag_preset.clear()
	_tag_preset.add_item("— 常用 tag —")
	_tag_preset.set_item_disabled(0, true)
	for tag in _load_known_tags():
		_tag_preset.add_item(tag)


func _on_tag_preset_selected(idx: int) -> void:
	_tag_name.text = _tag_preset.get_item_text(idx)


func _add_tag() -> void:
	var tag := _tag_name.text.strip_edges()
	if tag == "":
		_log("tag 名为空")
		return
	var key := _current_key()
	if key == "Hero":
		Player.grant_tag(tag)
	else:
		EffectProcessor._grant_npc_tag(_ensure_entry(key), tag)
	Player.notify_stats_changed()
	_log("已给 %s 加 tag：%s" % [key, tag])
	_refresh_state()


func _remove_tag() -> void:
	var tag := _tag_name.text.strip_edges()
	if tag == "":
		_log("tag 名为空")
		return
	var key := _current_key()
	if key == "Hero":
		Player.remove_tag(tag)
	else:
		var entry := _ensure_entry(key)
		(entry["tags"] as Array).erase(tag)
		if entry.has("tag_turns") and (entry["tag_turns"] as Dictionary).has(tag):
			(entry["tag_turns"] as Dictionary).erase(tag)
	Player.notify_stats_changed()
	_log("已从 %s 移除 tag：%s" % [key, tag])
	_refresh_state()


# ============================================================
#  ④ num_tags
# ============================================================

func _apply_num_tag() -> void:
	var tag := _num_tag_name.text.strip_edges()
	if tag == "":
		_log("num_tag 名为空")
		return
	var val := int(_num_tag_value.value)
	var is_add := _num_tag_mode.selected == 1
	var key := _current_key()
	var final_val := val
	if key == "Hero":
		var cur := int(Player.player_num_tags.get(tag, 0))
		final_val = cur + val if is_add else val
		Player.player_num_tags[tag] = final_val
	else:
		var entry := _ensure_entry(key)
		var cur := int(entry["num_tags"].get(tag, 0))
		final_val = cur + val if is_add else val
		entry["num_tags"][tag] = final_val
	Player.hero_merge()
	Player.notify_stats_changed()
	_log("%s 的 num_tag %s = %d" % [key, tag, final_val])
	_refresh_state()


# ============================================================
#  ⑤ attrs
# ============================================================

func _apply_attr() -> void:
	var attr: String = ATTRS[_attr_selector.selected]
	var val := int(_attr_value.value)
	var is_add := _attr_mode.selected == 1
	var key := _current_key()
	if key == "Hero":
		_set_hero_attr(attr, val, is_add)
	else:
		var entry := _ensure_entry(key)
		var cur := int(entry.get(attr, 0))
		entry[attr] = cur + val if is_add else val
	Player.hero_merge()
	Player.notify_stats_changed()
	_log("%s 的 %s 已更新" % [key, ATTR_CN[attr]])
	_refresh_state()


func _set_hero_attr(attr: String, val: int, is_add: bool) -> void:
	if is_add:
		match attr:
			"int": Player.player_int += val
			"app": Player.player_app += val
			"str": Player.player_str += val
			"bod": Player.player_bod += val
	else:
		match attr:
			"int": Player.player_int = val
			"app": Player.player_app = val
			"str": Player.player_str = val
			"bod": Player.player_bod = val


# ============================================================
#  工具
# ============================================================

## 读取 tags.json 的所有 tag 名，作为 tag 下拉候选（调试工具直读数据文件）。
func _load_known_tags() -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(TAGS_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			for k in (parsed as Dictionary).keys():
				out.append(String(k))
	return out


func _log(msg: String) -> void:
	if _log_label == null:
		return
	var lines: Array = _log_label.text.split("\n", false)
	lines.push_front(msg)
	while lines.size() > 8:
		lines.pop_back()
	_log_label.text = "\n".join(lines)
