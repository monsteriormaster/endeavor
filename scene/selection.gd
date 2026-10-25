extends Node2D
## 角色创建（selection）—— 三栏彩铅登记表（2026-10-06 实装）。
##
## ▍版面：左 = 姓名 + 属性｜中 = 天赋清单（两列 7 行）｜右 = 说明纸片
##   底图 art/ui/sel_form_bg.png 只含「装帧」（桌 / 纸 / 铜框 / 饰线 / 点数签空框）；
##   **所有文字都是运行时 Label**（全局主题字体是幼圆，烤进图里会与实机不一致）。
##
## ▍本文件在 2026-10-06 做的一批交互修复（起因：可用性审计，全部有代码依据）：
##   ① 天赋卡整片可点 —— 卡片本体是 Button，勾选框降级成 TextureRect 指示灯。
##      旧实现把点击只挂在 20x20 的 CheckBox 上，点名字、点空白都没反应。
##   ② 三态（未选 / 已选 / 买不起）统一刷 —— 旧实现只有「勾上 / 没勾」两态，
##      买不起只靠引擎默认的 disabled 长相，在纸上根本看不出来。
##   ③ 「天赋后」预览 —— 「平凡可贵」的 clamp_attrs 过去只在 before_trans() 生效，
##      勾选期间左栏数字一动不动，进游戏才静默变。现在预览与结算**共用同一处取值**。
##   ④ 离开确认拆掉 && —— 旧条件 `gift_att >= 最便宜 & player_att > 0` 把两套
##      互相独立的资源绑死：属性点一花光就再也不弹确认，天赋点剩着也静默丢掉。
##   ⑤ 说明区 hover 预览 + 点击钉住 —— 旧实现 mouse_exited 无条件清空，没法对照取舍。
##   ⑥ 天赋列表按价格排序 —— 旧实现是 JSON 键序，价格乱跳（10,5,20,10,...）。
##   ⑦ 价格写成 −N；名字留空有明确兜底（Player.player_display_name()）。
##
## ▍2026-10-06 第二批（用户验收后追加）：
##   ⑧ 天赋清单套 ScrollContainer（`gift_container/passby/gift_scroll`）——
##     14 条正好 7 行铺满，将来加条目要能滚；**取节点路径已跟着往下一层**，
##     别用旧路径 `.../passby/selection_area`（那种写法取到 null，add_child 直接炸）。
##   ⑨ 说明区 `scroll_active = true` + 挂 VScrollBar 主题（内容长时可滚，不再静默截断）。
##      ⚠️ 这是**全工程唯一**给 ScrollContainer 换皮的地方（另外 5 处 —— card_area / action_panel /
##      achievement_list / dialogue_ui 的 content_scroll 与 HistoryScroll —— 都吃引擎默认滚动条）。
##      现在的皮是 `StyleBoxFlat` 圆角铜块（`SB_vs_grabber`）：**与「纸 / 铅笔同源」的材质规矩不同源**，
##      属于「最小可见成本」的权宜 —— 因为 `vertical_scroll_mode = AUTO` 且当前 14 条正好 7 行，
##      滚动条根本不会露头（探针实测 vbar.visible = false）。哪天条目超过 7 行、滚动条真要露了，
##      再改手绘细线（一条竖细铜线 + 纸色轨道）。
##   ⑩ 删掉 `name_hint`（「留空将以「主角」称呼你」）与属性列 4 条 `leader_*` 点线：
##     前者因为默认名已改为「维克多」（见 Player.NAME_FALLBACK）而文案过时，
##     后者用户反馈「不明所以」。两者都已从 .tscn 移除，本文件不再引用。

const CONFIRM_DIALOG_PATH = "res://components/confirmdialog.tscn"
const GIFT = "res://resoures/gifts_begin.json"
## 开局成就：**第一次**点「新的开始」走完角色创建、真正进入游戏界面时解锁。
## 幂等由 AchievementManager 保证；新游戏时 SaveLoader.reset_to_new_game() 已清空
## `achievements_unlocked`，所以每个新档会（且只会）弹一次。
const ACH_WELCOME := "感谢你的游玩"

## 天赋卡几何（与 selection_area 对齐：2 列 x 247 + 8 间隔 = 502；7 行 x 48 + 6 x 10 = 396）
const CHIP_SIZE := Vector2(247, 48)
const BOX_AT := Vector2(18, 14)
const BOX_SIDE := 20.0
const NAME_X := 56.0
const NAME_W := 108.0
const PRICE_X := 141.0
const PRICE_W := 92.0

const TEX_BOX: Texture2D = preload("res://art/ui/sel_box.png")
const TEX_BOX_ON: Texture2D = preload("res://art/ui/sel_box_on.png")
const TEX_CHIP_ON: Texture2D = preload("res://art/ui/sel_chip_on.png")

const INK := Color(0.262745, 0.215686, 0.164706)
const INK_SEL := Color(0.180392, 0.141176, 0.094118)
const INK_DIM := Color(0.552941, 0.501961, 0.447059)
const COPPER := Color(0.45098, 0.333333, 0.14902)
const COPPER_DIM := Color(0.639216, 0.596078, 0.545098)
## 与 ButtonSkin.TINT_DISABLED 同值 —— 贴图被乘成灰纸，勾选框与文字要跟着一起灰
const GRAY_TINT := Color(0.82, 0.81, 0.78)

const ATTRS: Array[String] = ["int", "app", "str", "bod"]
## 品质权重（同价排序用）。"SRR" 是 gifts_begin.json 里「谁主沉浮」的笔误（应为 SSR），
## 一并按 SSR 处理，免得它因为字符串序被甩到最后。**数据侧的笔误未擅自改。**
const Q_RANK := {"R": 0, "SR": 1, "SSR": 2, "SRR": 2}

const DESC_PLACEHOLDER := "[color=#8C7C66]把鼠标移到右侧天赋上查看说明[/color]"

var gifts = {}
## 展示顺序（按价格升序）。界面不再依赖 JSON 的键序。
var gift_order: Array[String] = []
## 天赋键 → {"button","box","overlay","name","price","price_val"}
var chip_nodes := {}
var origin_gift_att = Player.gift_att
var origin_player_att = Player.player_att
## 天赋键 → bool（选了没有）
var choose_condition := {}
## 说明区当前「钉住」的天赋键（点击时钉，鼠标移开仍保留）
var _pinned_key := ""


func _ready():
	get_data()
	update_all_att_label()
	setup_buttons()
	setup_gift_selection()
	update_button_states()
	update_gift_label()
	_update_gift_states()
	_update_preview()
	_show_desc("")


func _process(_delta):
	pass


func _on_line_edit_text_changed(new_text):
	Player.player_name = new_text


# ================================================================ 属性
func reduce_attribute(attribute_name: String):
	var attribute_value = Player.get("player_" + attribute_name)
	if attribute_value > 0 and Player.player_att <= 25:
		Player.set("player_" + attribute_name, attribute_value - 1)
		Player.change_att(1)
		update_att_label(attribute_name, attribute_value - 1)
		_refresh_pool_label()
		update_button_states()
		_update_preview()


func increase_attribute(attribute_name: String):
	var attribute_value = Player.get("player_" + attribute_name)
	if attribute_value < 10 and Player.player_att >= 1:
		Player.set("player_" + attribute_name, attribute_value + 1)
		Player.change_att(-1)
		update_att_label(attribute_name, attribute_value + 1)
		_refresh_pool_label()
		update_button_states()
		_update_preview()


func _refresh_pool_label() -> void:
	$attribute/Label.text = "可分配属性点 %d" % int(Player.player_att)


func update_button_states():
	for attr in ATTRS:
		var add_button = get_node_or_null("attribute/addbox/%s" % attr)
		var minus_button = get_node_or_null("attribute/minusbox/%s" % attr)
		var value = Player.get("player_" + attr)

		add_button.disabled = Player.player_att == 0 or value == 10
		minus_button.disabled = value == 0 or Player.player_att == 25
		# 加减钮走「自绘」路线（.tscn 里 normal 槽是 StyleBoxEmpty → 全局 ButtonSkin 跳过，
		# 因为 42x42 会让大档九宫格 caps 40+40=80 超过控件宽度）。
		# 既然没有 StyleBox 帮忙，禁用态得自己把纸钮和文字一起灰掉。
		_step_disabled_look(add_button)
		_step_disabled_look(minus_button)


func _step_disabled_look(btn: Button) -> void:
	var frame := btn.get_node_or_null("frame") as TextureRect
	if frame != null:
		frame.modulate = GRAY_TINT if btn.disabled else Color.WHITE


func update_att_label(attribute_name: String, value: int):
	match attribute_name:
		"int":
			$attribute/value/int.text = str(value)
		"app":
			$attribute/value/app.text = str(value)
		"str":
			$attribute/value/str.text = str(value)
		"bod":
			$attribute/value/bod.text = str(value)


func update_all_att_label() -> void:
	update_att_label('int', Player.player_int)
	update_att_label('app', Player.player_app)
	update_att_label('str', Player.player_str)
	update_att_label('bod', Player.player_bod)
	_refresh_pool_label()


func disable_button(attribute_name: String, is_add: bool):
	var box = "addbox" if is_add else "minusbox"
	var button = get_node_or_null("attribute/%s/%s" % [box, attribute_name])
	if button:
		button.disabled = true
		_step_disabled_look(button)


func connect_button(button: Button, attribute: String, operation: String) -> void:
	button.connect("pressed", self._on_attribute_button_pressed.bind(attribute, operation))


func setup_buttons():
	connect_button($attribute/minusbox/int, "int", "minus")
	connect_button($attribute/minusbox/app, "app", "minus")
	connect_button($attribute/minusbox/str, "str", "minus")
	connect_button($attribute/minusbox/bod, "bod", "minus")
	connect_button($attribute/addbox/int, "int", "add")
	connect_button($attribute/addbox/app, "app", "add")
	connect_button($attribute/addbox/str, "str", "add")
	connect_button($attribute/addbox/bod, "bod", "add")


func _on_attribute_button_pressed(attribute: String, operation: String):
	match operation:
		"add":
			increase_attribute(attribute)
		"minus":
			reduce_attribute(attribute)


## 已选天赋的 clamp_attrs 取最严约束：min 取最大、max 取最小。返回 [lo, hi, has]。
## ⚠️ 与 _apply_clamp_attrs() **共用本函数** —— 预览和结算要是两套算法，
##    迟早出现「显示 10→7、进游戏变 8」这种最难查的偏差。
func _clamp_bounds() -> Array:
	var lo := -9999
	var hi := 9999
	var has := false
	for gift_key in choose_condition:
		if not bool(choose_condition[gift_key]):
			continue
		var eff: Dictionary = gifts[gift_key].get("effect", {})
		if eff.has("clamp_attrs"):
			has = true
			var c: Dictionary = eff["clamp_attrs"]
			lo = maxi(lo, int(c.get("min", -9999)))
			hi = mini(hi, int(c.get("max", 9999)))
	return [lo, hi, has]


## 已选天赋对某一属性的**裸加减和**（EffectProcessor.apply 的 attrs 分支就是直接落 Player）。
## ⚠️ 预览**必须**把它算进去：结算顺序是「玩家分配值 + 天赋 attrs 增减 → 最后 clamp」。
##    只看当前值会漏掉这类偏差：str=5、又选了「力量+3」、clamp 上限 7 →
##    预览说"没变化"，进游戏却变成 7。修复③只共用了「夹值范围」，这里把「加成」也共用。
func _attr_delta(attr: String) -> int:
	var d := 0
	for gift_key in choose_condition:
		if not bool(choose_condition[gift_key]):
			continue
		var eff: Dictionary = gifts[gift_key].get("effect", {})
		var av: Variant = eff.get("attrs", null)
		if av is Dictionary:
			d += int((av as Dictionary).get(attr, 0))
	return d


## 「天赋后」预览：把**天赋加成 + 上下限夹值**后的结果显示在每行右侧，只在与当前值不同时出现。
## 取值口径与 before_trans() → _apply_clamp_attrs() 完全一致：clamp(当前 + Σ天赋attrs)。
func _update_preview() -> void:
	var b := _clamp_bounds()
	var lo: int = b[0]
	var hi: int = b[1]
	var has: bool = b[2]
	var any := false
	for attr in ATTRS:
		var lb := get_node_or_null("attribute/preview/%s" % attr) as Label
		if lb == null:
			continue
		var cur := int(Player.get("player_" + attr))
		var after: int = cur + _attr_delta(attr)
		if has:
			after = clampi(after, lo, hi)
		if after != cur:
			lb.text = "→ %d" % after
			lb.visible = true
			any = true
		else:
			lb.visible = false
	$attribute/clamp_hint.visible = any


# ================================================================ 天赋
## 读表 + 定展示顺序（价格升序 → 品质 → 名字，保证每次进界面顺序一致）
func get_data():
	var file = FileAccess.open(GIFT, FileAccess.READ)
	gifts = JSON.parse_string(file.get_as_text())
	file.close()
	gift_order.clear()
	for k in gifts.keys():
		# show == 0 → 暂时下架（默认 1，缺省视为显示）：不进展示顺序，
		# 卡片不生成、点不到、不参与「最便宜未选」与结算 —— 等于这个天赋不存在。
		# 下游全走 gift_order/choose_condition，所以只需在这里过滤这一处。
		if int(gifts[k].get("show", 1)) == 0:
			continue
		gift_order.append(str(k))
	gift_order.sort_custom(_gift_less)


func _gift_less(a: String, b: String) -> bool:
	var ga: Dictionary = gifts[a]
	var gb: Dictionary = gifts[b]
	var pa := int(ga.get("price", 0))
	var pb := int(gb.get("price", 0))
	if pa != pb:
		return pa < pb
	var qa := int(Q_RANK.get(str(ga.get("quality", "")), 9))
	var qb := int(Q_RANK.get(str(gb.get("quality", "")), 9))
	if qa != qb:
		return qa < qb
	return a < b


func setup_gift_selection():
	var selection_area := $gift_container/passby/gift_scroll/selection_area
	var description_area := $description_area as RichTextLabel
	description_area.bbcode_enabled = true
	description_area.text = ""
	chip_nodes.clear()
	choose_condition.clear()

	for gift_key in gift_order:
		var gift_data: Dictionary = gifts[gift_key]
		var price := int(gift_data.get("price", 0))
		choose_condition[gift_key] = false

		# 卡片本体 = Button（吃全局 ButtonSkin 的纸片九宫格 + 四态调色）→ 整片可点。
		# ⚠️ **不能**开 toggle_mode：ButtonSkin 把 pressed 槽调成压暗色，
		#    toggle 的「按下保持」会让已选卡片一直发暗，看起来像坏了。
		#    选中态自己管（choose_condition + overlay + 勾选框贴图）。
		var btn := Button.new()
		btn.name = "chip_%s" % gift_key
		btn.custom_minimum_size = CHIP_SIZE
		btn.text = ""

		var overlay := TextureRect.new()
		overlay.name = "overlay"
		overlay.texture = TEX_CHIP_ON
		overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		overlay.stretch_mode = TextureRect.STRETCH_SCALE
		overlay.position = Vector2.ZERO
		overlay.size = CHIP_SIZE
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.visible = false
		btn.add_child(overlay)

		var box := TextureRect.new()
		box.name = "box"
		box.texture = TEX_BOX
		box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		box.stretch_mode = TextureRect.STRETCH_SCALE
		box.position = BOX_AT
		box.size = Vector2(BOX_SIDE, BOX_SIDE)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(box)

		var name_label := Label.new()
		name_label.name = "gift_name"
		name_label.text = str(gift_data.get("name", gift_key))
		name_label.position = Vector2(NAME_X, 0.0)
		name_label.size = Vector2(NAME_W, CHIP_SIZE.y)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", INK)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(name_label)

		# 价格带负号：裸数字读不出「这是要花掉的点数」。
		var price_label := Label.new()
		price_label.name = "gift_price"
		price_label.text = "−%d" % price
		price_label.position = Vector2(PRICE_X, 0.0)
		price_label.size = Vector2(PRICE_W, CHIP_SIZE.y)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_label.add_theme_font_size_override("font_size", 16)
		price_label.add_theme_color_override("font_color", COPPER)
		price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(price_label)

		# 点击 = 切换选择；hover = 预览说明（两者都挂**整片**，不再只有那个小方块）
		btn.pressed.connect(_on_check_toggle.bind(btn, price, gift_key))
		btn.mouse_entered.connect(_on_gift_hover.bind(gift_key))
		btn.mouse_exited.connect(_on_gift_leave)

		selection_area.add_child(btn)
		chip_nodes[gift_key] = {
			"button": btn, "box": box, "overlay": overlay,
			"name": name_label, "price": price_label, "price_val": price,
		}


func _on_check_toggle(_btn: Button, price: int, gift_key: String):
	var now_on: bool = not bool(choose_condition.get(gift_key, false))
	choose_condition[gift_key] = now_on
	if now_on:
		Player.gift_att -= price
	else:
		Player.gift_att += price
	update_gift_label()
	_update_gift_states()
	_update_preview()
	# 点击顺手把说明**钉住**：解决「hover-only」——鼠标移开也还能继续读，
	# 也顺手让「我正在看哪一个」有个落点。
	_pinned_key = gift_key
	_show_desc(_pinned_key)


## 三态刷新：未选 / 已选 / 买不起（买不起 = 余额不够且尚未选中）
func _update_gift_states() -> void:
	for gift_key in chip_nodes:
		var c: Dictionary = chip_nodes[gift_key]
		var btn: Button = c.button
		var price: int = c.price_val
		var picked := bool(choose_condition.get(gift_key, false))
		# ⚠️ 已选中的卡片**永远不能禁用** —— 否则余额花光后再也点不掉，点数就锁死了。
		var broke: bool = int(Player.gift_att) < price and not picked

		btn.disabled = broke
		c.overlay.visible = picked
		c.box.texture = TEX_BOX_ON if picked else TEX_BOX
		c.box.modulate = GRAY_TINT if broke else Color.WHITE
		c.name.add_theme_color_override("font_color",
				INK_DIM if broke else (INK_SEL if picked else INK))
		c.price.add_theme_color_override("font_color", COPPER_DIM if broke else COPPER)


func update_gift_label():
	$gift_container/Label.text = "剩余天赋点 %d" % int(Player.gift_att)


# ================================================================ 说明区
func _on_gift_hover(gift_key: String):
	_show_desc(gift_key)


func _on_gift_leave():
	_show_desc(_pinned_key)


## key 为空 → 占位提示（而不是一片空白：界面得告诉玩家「怎么才能看到内容」）
func _show_desc(gift_key: String) -> void:
	var area := $description_area as RichTextLabel
	if gift_key == "" or not gifts.has(gift_key):
		area.text = DESC_PLACEHOLDER
		return
	area.text = _desc_bbcode(gift_key)


## 说明区正文：每个段落之间空一行（名称 / 品质 / 描述 / 效果 / 标签 各自成段，标签逐条成段）。
## 段与段之间用 "\n\n" join —— 单 \n 只换行不留空行，读起来会挤成一坨。
func _desc_bbcode(gift_key: String) -> String:
	var g: Dictionary = gifts[gift_key]
	var blocks: Array[String] = []
	blocks.append("[b]名称[/b]：" + str(g.get("name", gift_key)))
	blocks.append("[b]品质[/b]：" + str(g.get("quality", "")))
	blocks.append("[b]描述[/b]：" + str(g.get("description", "")))
	blocks.append("[b]效果[/b]：" + _format_effect(g.get("effect", {})))
	var cor := str(g.get("cor_label", ""))
	if cor != "":
		blocks.append("[b]标签[/b]：")
		for lb in cor.split(" "):
			if lb == "":
				continue
			var tg = TagRegistry.get_tag(lb)
			var tg_desc := ""
			if tg is Dictionary:
				tg_desc = str(tg.get("description", ""))
			blocks.append(lb + "\n" + tg_desc)
	return "\n\n".join(blocks)


# ================================================================ 离开
func _on_next_pressed():
	var warns: Array[String] = []

	# ① 名字：留空会给 Player.NAME_FALLBACK 兜底（现为「维克多」）。以前是**静默**改名，玩家全程不知道。
	#    ⚠️ 兜底名不写死在这里 —— 与 Player 共用同一个常量，改名时只改一处。
	#    显式 `var ... : String` 是必须的：通过 Autoload 取常量拿到的是弱类型 Variant，
	#    直接内联进 % 会让解析器推不出类型（同 C-04 那条 `var n := hero.strip_edges()` 的坑）。
	if not Player.has_valid_name():
		var fallback: String = Player.NAME_FALLBACK
		warns.append("还没有给主角起名，将以「%s」称呼。" % fallback)

	# ② 天赋点：只问「余额还够不够买最便宜的那个」，和属性点**毫无关系**。
	#    旧写法 `gift_att >= minn && player_att > 0` 把这俩绑在一起 ——
	#    属性点一花光（最常见的玩法）守卫就静默失效，天赋点剩多少都白扔。
	var minn := _cheapest_unselected_price()
	if minn < 10000000 and int(Player.gift_att) >= minn:
		warns.append("天赋点还剩 %d 点，还能再选一个（最低 %d 点）。" % [int(Player.gift_att), minn])

	# ③ 属性点：独立判断，独立文案。
	if int(Player.player_att) > 0:
		warns.append("属性点还剩 %d 点没有分配。" % int(Player.player_att))

	if warns.is_empty():
		before_trans()
		return
	_confirm("确认离开", "\n".join(warns), "确认", "返回", before_trans)


func _cheapest_unselected_price() -> int:
	var minn := 10000000
	for gift_key in choose_condition:
		if not bool(choose_condition[gift_key]):
			minn = mini(minn, int(gifts[gift_key].get("price", 0)))
	return minn


func _confirm(title: String, message: String, ok_text: String, cancel_text: String,
		on_ok: Callable) -> void:
	var confirm_dialog = load(CONFIRM_DIALOG_PATH).instantiate()
	confirm_dialog.setup(title, message, ok_text, cancel_text)
	confirm_dialog.confirmed.connect(on_ok)
	OverlayRoot.push_overlay(confirm_dialog, {
		"modal": true,
		"esc_closes": true,
		"close_method": "close_dialog",
	})


func _on_pre_pressed():
	if Player.gift_att < origin_gift_att || Player.player_att < origin_player_att:
		_confirm("确认离开", "该页面不会保存，确定要离开吗？", "确认", "返回",
				func (): get_tree().change_scene_to_file('res://scene/loading.tscn'))
	else:
		get_tree().change_scene_to_file('res://scene/loading.tscn')


func before_trans():
	# 1. 初始化主角卡 Hero（属性先占位 0，effect+clamp 后再同步最终值）。
	#    先建 Hero 卡再 apply effect：避免 Player.npc = {Hero} 覆盖掉 effect 加进来的 npc（如"死生契阔"的法拉叶）。
	Player.npc = {
		"Hero":{
			"name" :"",
			"tags" :[],
			"int" :0,
			"str" :0,
			"bod" :0,
			"app" :0,
			"equipment":{},
			"description": "曾热爱艺术，家庭发生变故后，不得已继承家业放弃梦想。不过野心依旧。",
		}
	}
	# 2. 对所有已选天赋应用 effect（天赋无 flow_tags，tags/attrs/npc 等直接落 Player）。
	#    天赋名不再作为 tag 加入——天赋的效应完全由 effect 字典决定。
	for gift_key in choose_condition:
		if bool(choose_condition[gift_key]):
			var eff: Dictionary = gifts[gift_key].get("effect", {})
			if not eff.is_empty():
				EffectProcessor.apply(eff)
	# 3. 平凡可贵 clamp_attrs（最后生效，仅此界面；进入游戏后玩家可通过其他 effect 超出范围）
	_apply_clamp_attrs()
	# 4. 同步主角卡属性（含 effect 增减与 clamp 后的最终值）
	#    ⚠️ 名字走 player_display_name()：空名 / 停在占位串时统一兜底成 Player.NAME_FALLBACK（「维克多」），
	#       不再把「请输入你的名字」写进 Hero 卡跟着玩家走一整局。
	Player.npc["Hero"]["name"] = Player.player_display_name()
	Player.npc["Hero"]["int"] =  Player.player_int
	Player.npc["Hero"]["str"] =  Player.player_str
	Player.npc["Hero"]["bod"] =  Player.player_bod
	Player.npc["Hero"]["app"] =  Player.player_app
	# 角色创建完成后自动进入新手引导；若教学已完成（读档/二周目）则直接进主城。
	# 先确定目标场景并写入存档路径，再存档、切场景（避免存档里 path 为空导致回档跳关）。
	if TutorialManager.is_completed("opening"):
		Player.path = "res://scene/main.tscn"
	else:
		Player.path = "res://scene/tutorial_1.tscn"
		# 仅通过 selection 进入新手教程时打上「进行新手教程」门控 tag；
		# 教程内所有门控（返回锁定、管家卡恢复、下一天拦截等）都认这一个 tag，
		# 教程完成/跳过后由 TutorialManager 摘除，彻底解耦具体剧情 beat。
		# 「进行新手教程」的授予点唯一就是这里（教程入口唯一），
		# 因此非教程路径（读档进主城 / 地图传送）永远不会误入门控状态。
		if not Player.player_has_tags(["进行新手教程"]):
			Player.grant_tag("进行新手教程")
	SaveLoader.save_game()
	get_tree().change_scene_to_file(Player.path)
	# 开局成就「感谢你的游玩」：**换完场景**才解锁 / 弹窗（不是压在角色创建表上）。
	# 这里是全工程唯一的新游戏入口（标题页「新的开始」→ selection），
	# 所以无需额外的「第一次」门控 —— 幂等 + 新档清空两者叠加即为「每档第一次」。
	# ⚠️ 等待放在 AchievementManager 里：本节点换场景后立刻被 free，
	#    协程若挂在这里会连解锁一起消失。
	AchievementManager.unlock_after_leaving("res://scene/selection.tscn", ACH_WELCOME)


## 平凡可贵：属性夹值（最后生效，仅 selection 界面）。
## 取值与 _update_preview() 共用 _clamp_bounds()，保证「看到的」就是「落地的」。
func _apply_clamp_attrs() -> void:
	var b := _clamp_bounds()
	if not bool(b[2]):
		return
	var lo: int = b[0]
	var hi: int = b[1]
	Player.player_int = clampi(Player.player_int, lo, hi)
	Player.player_app = clampi(Player.player_app, lo, hi)
	Player.player_str = clampi(Player.player_str, lo, hi)
	Player.player_bod = clampi(Player.player_bod, lo, hi)
	Player.notify_stats_changed()


## 把 effect 字典格式化为可读文本（用于描述区显示，替代旧的字符串 effect）。
func _format_effect(eff: Dictionary) -> String:
	if not (eff is Dictionary) or eff.is_empty():
		return "无"
	var parts: Array = []
	if eff.has("attrs"):
		var attrs: Dictionary = eff["attrs"]
		var names := {"int": "智力", "app": "魅力", "str": "力量", "bod": "体魄"}
		for k in attrs:
			var n: String = names.get(String(k), String(k))
			parts.append("%s%+d" % [n, int(attrs[k])])
	if eff.has("tags"):
		parts.append("获得标签：" + " ".join(eff["tags"]))
	if eff.has("num_tags"):
		var nt: Dictionary = eff["num_tags"]
		var segs: Array = []
		for k in nt:
			segs.append("%s=%d" % [k, int(nt[k])])
		parts.append("可堆叠词条：" + " ".join(segs))
	if eff.has("stuff"):
		parts.append("获得物品：" + " ".join(eff["stuff"]))
	if eff.has("money"):
		parts.append("金钱%+d" % int(eff["money"]))
	if eff.has("npc"):
		var npcs: Array = []
		for nk in eff["npc"]:
			npcs.append(String(nk))
		parts.append("获得同伴：" + " ".join(npcs))
	if eff.has("equipment"):
		parts.append("获得装备")
	if eff.has("remove_tags"):
		parts.append("移除标签：" + " ".join(eff["remove_tags"]))
	if eff.has("remove_num_tags"):
		parts.append("移除可堆叠词条")
	if eff.has("goto_scene"):
		parts.append("前往新场景")
	if eff.has("child"):
		parts.append("获得孩子")
	if eff.has("name_child"):
		parts.append("为孩子取名")
	if eff.has("clamp_attrs"):
		var c: Dictionary = eff["clamp_attrs"]
		parts.append("属性限定在[%d,%d]" % [int(c.get("min", 0)), int(c.get("max", 0))])
	if parts.is_empty():
		return "无"
	return "，".join(parts)
