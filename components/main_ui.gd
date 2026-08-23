extends Node2D

## 常驻主 UI：顶栏（头像 / 金钱 / 时间 / 贵族等级 / 设置）+ 右下「下一天」。
##
## 本文件关闭的缺陷（详见《主UI交互策划案》§8）：
##   D-UI1  _process 每帧刷新 HUD → 改为订阅 Player.stats_changed 事件驱动
##   D-UI2  is_next_day_locked setter 健壮化（显式类型 + 节点就绪守卫）
##   D-UI3  每次进主 UI 覆写 Player.npc["Hero"] → 改为"缺字段才补"的合并
##   D-UI4  设置按钮无响应 → 接入设置菜单（存档 / 读档 / 返回标题）
##   D-UI5  头像按钮写死"头像" → 显示主角名
##   D-UI7  过天 save+load 整场景重载 → 只推进数据，仅在预约了新场景时才切场景

const CHARACTER_PANNEL_PATH := "res://components/character_panel.tscn"
const SETTINGS_MENU_PATH := "res://components/settings_menu.tscn"
const CHARACTER := "res://resoures/characters.json"

## 「下一天」按钮锁定开关。教学期由 TutorialManager._set_next_day_locked() 写入。
##
## D-UI2 说明：原先怀疑"setter 里给属性自身赋值会无限递归"。已实测（debug 探针）
## Godot 4.7 中自赋值直接写后备字段、不会重入 setter，setter 只会被调用一次，
## 因此这里保留"赋值 + 立即刷新按钮"的写法。真正的隐患是别的：
##   1) 类型未标注，教学侧传进来任何值都不报错 → 补 `: bool`
##   2) 属性可能在 _ready 之前被写（autoload 抢跑），此时 $next_day 还不存在 → 加就绪守卫
@export var is_next_day_locked: bool = false:
	set(value):
		is_next_day_locked = value
		_refresh_next_day_button()

## 主角在 Player.npc 中的键名
var hero: String = "Hero"

@onready var _money_label: Label = $MarginContainer/top_container/information/money
@onready var _time_label: Label = $MarginContainer/top_container/information/time
@onready var _noble_label: Label = $MarginContainer/top_container/information/noble
@onready var _avatar_button: Button = $MarginContainer/top_container/avater
@onready var _next_day_button: Button = $next_day
@onready var _card_area: CardArea = $CardArea


## 暴露主 UI 卡牌区，供购书/触发器等把结算得到的卡（book_acquired / cards_returned）塞进来。
func get_card_area() -> CardArea:
	return _card_area


func _ready() -> void:
	ensure_hero_card()
	# D-UI1：事件驱动替代 _process 轮询
	if not Player.stats_changed.is_connected(_on_stats_changed):
		Player.stats_changed.connect(_on_stats_changed)
	data_upgrade()
	_refresh_next_day_button()
	# 把卡牌区交给触发器子系统，使其结算后能经 cards_returned / book_acquired 归还卡牌。
	TriggerManager.register_card_area(_card_area)


func _on_stats_changed() -> void:
	data_upgrade()


# ============================================================
#  顶栏数据
# ============================================================

## 刷新顶栏所有文本。可被外部安全地重复调用。
func data_upgrade() -> void:
	if not is_node_ready():
		return
	_money_label.text = "金钱：" + str(Player.player_money) + "万"
	_noble_label.text = "贵族等级：" + Player.player_nobility_title() + "（" + str(Player.nobility) + "）"
	_time_label.text = "时间：第" + str(Player.time) + "天"
	# D-UI5：头像按钮显示主角名，而不是写死的"头像"
	_avatar_button.text = _hero_display_name()


func _hero_display_name() -> String:
	var card: Variant = Player.npc.get(hero, null)
	if card is Dictionary:
		var card_name: String = str(card.get("name", ""))
		if card_name != "":
			return card_name
	var player_name: String = str(Player.player_name)
	return player_name if player_name != "" else "主角"


# ============================================================
#  主角卡（D-UI3）
# ============================================================

## 确保 Player.npc["Hero"] 存在且字段完整。
##
## 旧实现每次进主 UI 都执行 `Player.npc[hero] = info["Hero"]`，
## 用 characters.json 里的出厂数据整体覆盖存档中的主角卡，
## 玩家累积的属性 / 词条 / 装备全部被打回原形。
## 现在改为：不存在才用模板建卡；已存在则只补模板里有、存档里缺的字段。
func ensure_hero_card() -> void:
	var template: Dictionary = _load_hero_template()
	var existing: Variant = Player.npc.get(hero, null)

	if existing is Dictionary:
		var card: Dictionary = existing
		for key in template.keys():
			if not card.has(key):
				card[key] = _dup(template[key])
	else:
		Player.npc[hero] = template.duplicate(true)

	# 主角的成长数值以 Player 上的实时属性为准，同步进卡面
	Player.hero_merge(hero)


func _load_hero_template() -> Dictionary:
	if not FileAccess.file_exists(CHARACTER):
		push_error("Main_ui: 找不到角色表 %s" % CHARACTER)
		return {}
	var file: FileAccess = FileAccess.open(CHARACTER, FileAccess.READ)
	if file == null:
		push_error("Main_ui: 无法读取角色表 %s" % CHARACTER)
		return {}
	# JSON.parse_string 返回 Variant，严格模式下不能用 `:=`
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("Main_ui: 角色表解析失败 %s" % CHARACTER)
		return {}
	var all_characters: Dictionary = parsed
	var template: Variant = all_characters.get("Hero", {})
	return template if template is Dictionary else {}


## 深拷贝容器类字段，避免主角卡与模板共享同一个 Array / Dictionary 引用
func _dup(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


# ============================================================
#  按钮
# ============================================================

## 头像按钮 → 人物面板（统一走 OverlayRoot，D-UI6）
func _on_avater_pressed() -> void:
	var scene: PackedScene = load(CHARACTER_PANNEL_PATH)
	if scene == null:
		push_error("Main_ui: 找不到人物面板场景 %s" % CHARACTER_PANNEL_PATH)
		return
	var panel: Node = scene.instantiate()
	OverlayRoot.push_overlay(panel, {
		"modal": true,
		"esc_closes": true,
		"close_method": "close_panel",
	})
	panel.setup(hero)


## 设置按钮 → 设置菜单（D-UI4）
func _on_setting_pressed() -> void:
	var scene: PackedScene = load(SETTINGS_MENU_PATH)
	if scene == null:
		push_error("Main_ui: 找不到设置菜单场景 %s" % SETTINGS_MENU_PATH)
		return
	var menu: Node = scene.instantiate()
	OverlayRoot.push_overlay(menu, {
		"modal": true,
		"esc_closes": true,
		"close_method": "close_menu",
	})


## 「下一天」：推进回合。
##
## D-UI7：过天不再 save_game() + load_game() 整场景重载。
## 整场景重载会让所有场景内状态（已显隐的角色、已打开的面板、已消耗的触发点）回滚，
## 而且每天多做一次磁盘读 + 场景重建。现在只推进数据、存档并广播；
## 唯一保留的场景切换是"本回合预约了新场景"（剧情 / 教学通过 Player.path 指定目标）。
func _on_next_day_pressed() -> void:
	# D-UI2 配套：教学锁定期间即使按钮 disabled 被外部改动，逻辑层也不放行
	if is_next_day_locked:
		return

	Player.time += 1
	SaveLoader.save_game()
	EventSignal.day_changed.emit(Player.time)
	_goto_scheduled_scene_if_needed()


## 若 Player.path 指向的不是当前场景，说明本回合要换幕（如教学最后一步"回家"）。
## 此时按预约切场景并补发 scene_entered，保持教学 / 剧情既有语义。
func _goto_scheduled_scene_if_needed() -> void:
	var target: String = str(Player.path)
	if target == "":
		return
	var tree: SceneTree = get_tree()
	var current: Node = tree.current_scene
	if current != null and current.scene_file_path == target:
		return
	OverlayRoot.clear_all()
	tree.change_scene_to_file(target)
	EventSignal.scene_entered.emit(target)


func _refresh_next_day_button() -> void:
	# setter 可能早于 _ready 被写，此时 @onready 变量还是 null
	if not is_node_ready():
		return
	if _next_day_button == null:
		return
	_next_day_button.disabled = is_next_day_locked


## 兼容旧调用名
func locked_next_day() -> void:
	_refresh_next_day_button()
