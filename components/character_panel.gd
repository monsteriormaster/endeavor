extends PopupPanel
## 人物详情面板「卡牌版」（1344×700）。由 main_ui 单击手牌人物卡呼出，统一交给 OverlayRoot 托管。
## 模态弹出（modal=true → OverlayRoot 的 ModalBlocker 拦截地图输入，实现"游戏暂停"）。
##
## 关闭方式（2026-10-23 改口径，与物品详情 `CardDetailPopup` 对齐）：
##   · **点面板外** —— 面板自动收起；若那一下正好点在另一张手牌上，顺手把点击转过去，
##     一次点击就换成那张卡的详情/人物面板。实现在 OverlayRoot（拦截层 → close_with_click_through）。
##     为此本面板必须以 `exclusive: false` 入栈，否则窗口会把窗口外的点击整个吞掉。
##   · **点面板内** —— 什么都不做（旧实现是"点任意位置都关"，导致想读一下标签/装备说明
##     就把面板点没了；面板内本来就有悬浮说明要读）。
##   · **Esc / 右上 ✕** —— 关闭。
##   OverlayRoot.push_overlay(panel, {"modal": true, "exclusive": false,
##       "outside_click_closes": true, "close_method": "close_panel"})
##   panel.setup(npc_key)
##
## 版面（2026-10-13 改版：立绘装进一张放大的卡牌，装备也是三张叠在主卡左后方）
## ---------------------------------------------------------------
## ★ **唯一规格来源 = `design/_tools/make_panel_card.py`**（版面与配色）
##                          + `design/_tools/make_panel_card_bg.py`（把静态层烤成贴图）
##   **改版面请先改那两个脚本、重跑自检，再同步到这里。**
##
## 为什么静态层是一张贴图、而不是在 GDScript 里画
##   ① **纸晕**（右栏那块四边各 64px 渐隐的暖纸）—— `StyleBoxFlat` 只有硬边，画不出来；
##   ② **四枚属性印章** —— 由 `art/icons/UI_attributes/attr_04~07.png` 逐像素改色而来；
##   ③ **关闭钮的铜环 + 手绘 ✕**、**「描述」的铜色短竖线锚** —— 几十个抖动顶点的手绘折线。
##   三样都位置固定、永不变化，属「逻辑分辨率恒定的静态构件」→ 整张烤死最省事
##   （口径见 skill `godot-paper-panel-reskin`）。贴图 = `art/ui/character_panel_card_bg.png`。
##
## 留在 Godot 里画的（随角色变）：立绘 / 名字 / 四组属性文字 / 描述 / 标签胶囊 / 装备图标。
##
## 🔴 为什么 `bg` 那层要挂 `BLEND_MODE_PREMULT_ALPHA` 材质（.tscn 里的 `CIM_premult`）
## ---------------------------------------------------------------------------
## 本面板是 `PopupPanel`（`Window` 派生），`script/overlay_root.gd:264` 又把 `popup_window`
## 清成 false 并挂到 `/root` ⇒ 它必然走「子窗口渲染目标 → 再合成」这条路。而在这条路上
## Godot 对半透明**乘了两次 alpha**：
##     进目标：MIX  →  RGB_t = C·a          （dst 是透明黑 0）
##     出目标：MIX  →  out   = RGB_t·a + dst·(1−a) = C·a² + dst·(1−a)
## 实测吻合到 1 个色阶：纸晕 core=0.94 ⇒ 实际 a = 0.94² = 0.8824，
##     压 (45,42,39) 底本该出 208，实机出 **185**（= 230×0.7785 + 45×0.1176）；
##     a = 0.7686 处本该出 187，实机出 **146**。两点全中。
## a = 1 的不透明区**不受影响**（`C·1² + dst·0 = C`），所以主卡、装备卡一直是准的 ——
## 只有纸晕那一整片 88% 的晕会整体暗一档，而且边缘 ramp 还会被推成一个「暗环」。
##
## 给这一层换成 PREMULT_ALPHA 混合，进目标时写入的就是**未预乘**的 C，出目标时正好还原成
## 教科书写法的直混合 `C·a + dst·(1−a)`，core 与边缘 ramp 全对，且**与底色无关**。
## 证据：`debug/_bloom_probe.tscn` —— D（普通）= 185/146 精确复现实机；
##       E（premult）= 非窗口直画参考值，4/4 采样点（含 ramp）一致。
##
## ⚠️ 这条修法**依赖「面板始终是嵌入窗口」**。若哪天面板不再走 Window（例如改成 Control
##    交给 OverlayRoot 自己的 CanvasLayer 托管），必须**同时摘掉这个材质**，否则纸晕会整片发白
##    （那时没有子窗口那一层放大，premult 就成了「多加了一次 C」）。
## ⚠️ 同一个坑对工程里所有半透明弹窗都成立，只是别家的软边只有十几像素、暗环看不出来；
##    本面板右栏是**整片 88% 的晕**，才会显形。
##
## 留在 Godot 里画的（随角色变）：立绘 / 名字 / 四组属性文字 / 描述 / 标签胶囊 / 装备图标。
##
## ⚠️ 属性印章**烤在贴图里**，所以 `ATTR_COL_X` 是硬编码的 —— 它必须与贴图逐像素对齐。
##    运行时再算一遍（用字体量宽）反而会差 1~2px 与贴图错开。改 attr 区宽 = 重烤贴图 + 改这组数。

signal closed

# ============================================================
#  规格表（1x，单位 = 面板像素）
# ============================================================
const PANEL_W := 1344
const PANEL_H := 700

# ── 右栏：**左缘钉死、右缘随面板总宽走**
#    左缘 648 锚在主卡右缘（230+376=606）加 42 空隙上，跟面板总宽没关系 ——
#    真正决定「面板有多宽」的是右栏有多宽，收窄面板就是收右栏。
const INFO_X := 648.0
const INFO_R := 1274.0                  # = PANEL_W − 70
## 🔴 70 不能收：贴图里纸晕的淡出 ramp 是 64 **绝对像素**，核区右界 = 面板右缘 − 64。
##    留白 70 ⇒ 内容右缘落在核区内侧 6px。留白一收，右栏的字就掉进淡出带
##    （那天同一个坑踩过两次：属性图标一次、第 4 格数值一次，都是「位置落错带」不是「颜色选错」）。
const COL_W := 626.0                    # = INFO_R − INFO_X

const CLOSE_C := Vector2(1262.0, 84.0)  # 圆心；右缘 = INFO_R + 6 = 面板右缘 − 64 = 核区边界
const CLOSE_HIT := 22.0                 # 点击热区半径（视觉的 ✕ 烤在贴图里）

# ── 主卡 / 装备卡（卡面 `art/card.png`，360×636 ⇒ 高宽比 1.7667）
const CARD_HW := 636.0 / 360.0
const BIG_X := 230.0
const BIG_Y := 26.0
const BIG_W := 376.0
const BIG_H := 664.0                    # = BIG_W × 1.7667
const BIG_ART_PAD := 21.0               # 卡面最里那道描边线到图像区的内缩
const BIG_ART_TOP := 100.0              # 卡顶到图像区顶（留出名字带）
const BIG_NAME_Y := 78.0                # = BIG_Y + 52
const BIG_NAME_FONT := 34

const EQ_W := 116.0
const EQ_H := 205.0
## 由**后**到**前**（每张向右下让 62/42），压在主卡左后方
const EQ_XY := [Vector2(30, 26), Vector2(92, 68), Vector2(154, 110)]
const EQ_ART_PAD := 9.0
const EQ_ART_TOP := 20.0
## 空槽类型符号贴图 = 96×96（原生尺寸 1:1 贴，不缩放）
const EQ_GLYPH_BOX := 96.0

# ── 属性 2×2 网格（区域 520 → 每格 252）
const ATTR_GAP := 16.0
const ATTR_TOP := 96.0
const ATTR_W := 520.0
const ATTR_ROW_H := 86.0
const ATTR_ICON := 34.0
const ATTR_NAME_FONT := 17
const ATTR_VAL_FONT := 32
## 每列「内容块」左缘（= 出图脚本 `_attr_x0` 的居中结果；四项名字都是 2 字，故只有两个值）
const ATTR_COL_X := [709.5, 977.5]
const ATTR_NAME_DX := 46.0              # 图标 34 + 间隔 12
const ATTR_VAL_DX := 106.0              # 名宽 34（2×17）+ 间隔 26
const ATTR_CY0 := 116.0                 # = ATTR_TOP + 20
## 两个基线系数（来自出图脚本）：名 y = cy − 17×0.60，值 y = cy − 32×0.68
const ATTR_NAME_K := 0.60
const ATTR_VAL_K := 0.68

const DESC_X := 666.0                   # INFO_X + 18
const DESC_Y := 380.0
const DESC_W := 606.0                   # COL_W − 20
const DESC_FONT := 18
const DESC_LINE_H := 26.0

const TAG_X := 662.0                    # INFO_X + 14
const TAG_Y := 600.0
const TAG_H := 34.0

# ── 配色（与出图脚本逐字一致；改一处必须两边一起改）
const INK_TEXT := Color8(46, 33, 23)
const NAME_INK := Color8(99, 80, 57)
const DESC_INK := Color8(79, 67, 55)
## 数值三档：保留「金 = 高 / 褐 = 中 / 灰 = 低」的色相与温度，只把亮度压到纸上能读的区间
## （原始 `BRASS(170,140,70)` 压在纸晕上只有 2.4，低于大字门槛 3.0 → 现场是「8 比 5 淡」）
const VAL_HI := Color8(146, 100, 34)
const VAL_MID := Color8(104, 74, 44)
const VAL_LOW := Color8(118, 104, 88)
const CHIP_FILL := Color8(228, 215, 183)
const CHIP_EDGE := Color8(170, 140, 70)
## 装备符号两态：空槽灰墨 / 已装备亮铜（贴图是纯白 + alpha，靠 modulate 上色）
const GLYPH_EMPTY := Color8(142, 122, 95)
const GLYPH_FULL := Color8(222, 199, 140)

const ATTR_CN := {"int": "智力", "app": "魅力", "str": "力量", "bod": "体魄"}
const ATTR_ORDER: Array[String] = ["int", "app", "str", "bod"]
## 三类装备槽（用户拍板只保留三类，顺序 = card_data.gd::category_minor()）
const SLOTS3: Array[String] = ["weapon", "armor", "jewelry"]

const CARD_TEX := "res://art/card.png"
const EQ_GLYPH_TEX := {
	"weapon": "res://art/ui/eq_glyph_weapon.png",
	"armor": "res://art/ui/eq_glyph_armor.png",
	"jewelry": "res://art/ui/eq_glyph_jewelry.png",
}

var tagtip = Label.new()

var info
## 本面板展示的是哪个 npc 键（卸装备时要知道装回谁身上）。
var _owner_key: String = ""
var _closing: bool = false
var _card_tex: Texture2D = null


func _ready():
	tagtip.name = 'tagtip'
	tagtip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 悬浮提示可能被后加进来的属性 Label 盖住 → 自身置顶。
	tagtip.z_index = 100
	tagtip.hide()
	$margin.add_child(tagtip)
	_apply_layout()
	_center_panel()


func _process(_delta):
	pass


## 把规格表的数字灌进各节点。**只在这里设位置 / 尺寸**（.tscn 里的 offset 只是占位），
## 这样「版面」只有一个来源，不会出现「改了常量但场景里还写着旧坐标」。
func _apply_layout() -> void:
	var m := $margin as Control
	m.position = Vector2.ZERO
	m.size = Vector2(PANEL_W, PANEL_H)

	for n in ["bg", "equipment"]:
		var c := m.get_node(n) as Control
		c.position = Vector2.ZERO
		c.size = Vector2(PANEL_W, PANEL_H)

	var big := $margin/big as TextureRect
	big.position = Vector2(BIG_X, BIG_Y)
	big.size = Vector2(BIG_W, BIG_H)
	big.texture = _get_card_tex()

	var nm := $margin/charname as Label
	nm.position = Vector2(BIG_X, BIG_NAME_Y)
	nm.size = Vector2(BIG_W, 48.0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	nm.clip_text = true
	nm.add_theme_font_size_override("font_size", BIG_NAME_FONT)
	nm.add_theme_color_override("font_color", INK_TEXT)

	var de := $margin/description as Label
	de.position = Vector2(DESC_X, DESC_Y)
	de.size = Vector2(DESC_W, DESC_LINE_H * 3.0)
	de.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	de.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	de.add_theme_font_size_override("font_size", DESC_FONT)
	de.add_theme_color_override("font_color", DESC_INK)
	# 行距对齐出图脚本的 26px：字体默认行高通常不到 26，缺多少补多少
	# （用 get_height() 量，不写死 —— 换字体 / 换字号都不用回来改这一行）
	var f := de.get_theme_font("font")
	if f != null:
		de.add_theme_constant_override("line_spacing",
			int(round(DESC_LINE_H - float(f.get_height(DESC_FONT)))))

	var tg := $margin/tags as HBoxContainer
	tg.position = Vector2(TAG_X, TAG_Y)
	tg.size = Vector2(COL_W, TAG_H)

	var cb := $margin/closebutton as Control
	cb.position = CLOSE_C - Vector2(CLOSE_HIT, CLOSE_HIT)
	cb.size = Vector2(CLOSE_HIT * 2.0, CLOSE_HIT * 2.0)


## 面板居中到当前视口。尺寸变过好几次（500×432 → 850×700 → 1344×700），
## 所以显式算，不依赖 PopupPanel 的 `initial_position`。
func _center_panel() -> void:
	var vp := get_tree().root.get_visible_rect().size
	size = Vector2i(PANEL_W, PANEL_H)
	position = Vector2i(int((vp.x - PANEL_W) * 0.5), int((vp.y - PANEL_H) * 0.5))


#关闭键
func _on_closebutton_pressed():
	close_panel()


## 关闭面板。Esc / 「点面板外」/ 关闭钮三处共用；重复调用安全。
## 旧实现只 hide()，节点会一直挂在树上，每次点头像都新建一个 → 泄漏且越叠越多。
func close_panel() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	# 延迟 hide：避免在 _input 回调栈内同步 hide 导致 Viewport 输入状态损坏（点击弹窗外卡死）。
	hide.call_deferred()
	# 未被 OverlayRoot 托管时（例如调试场景里直接 add_child）自行销毁
	if not OverlayRoot.close_overlay(self):
		queue_free()


## 面板内的点击**不关闭面板**（2026-10-23 改口径）。
##
## 旧实现挂 `_input`：「点任意位置都关」。窗口是嵌入子窗口，它只收得到**落在自己矩形内**的
## 点击（探针实测量过），所以那条规则实际语义就是「点面板内就关」。面板里本来就有要读的
## 悬浮说明（标签 / 装备）和要拖的装备卡，一点就消失纯属添乱。「点面板外收起」现在交给
## OverlayRoot 的拦截层，这里不再需要 `_input`。


func setup(character_name:String):
	_owner_key = character_name
	info = Player.npc[character_name]
	# 再居中一次：`initial_position` 的定位发生在窗口首次可见时，可能晚于 `_ready`。
	_center_panel()

	$margin/charname.text = String(info.get('name', character_name))
	_portrait_setup()
	descriptiondeal()
	attrsdeal(character_name)
	tagsdeal()
	equipmentdeal(info.get("equipment", {}))


# ============================================================
#  立绘
# ============================================================

## 立绘 = 主卡图像区里的一张**等比 contain**（整张图装进去、上下左右居中）。
##
## ⚠️ 与旧版（850×700 那一版）的三处差别，都是「装进卡牌」带来的：
##   ① **没有左缘渐隐**了 —— 旧版要把抠图「贴」在纸上，现在它在一张实心卡里，不需要融边；
##   ② **没有落影**了 —— 卡面本身就是纸，再叠一层影会在卡内糊出一圈灰；
##   ③ **下缘不裁切** —— 旧版是「底边贴框底 + 下缘出血」，现在卡面图像区是一扇完整的窗，
##      人物全身都在（实测 `sansi.png` alpha 裁完 650×1886，装进 334×543 → 实际 187×543，
##      占框宽 56%，两侧留白是正常现象，不是缩放 bug）。
func _portrait_setup() -> void:
	var spr := $margin/avatar as Sprite2D

	var image_path: String = CharacterImage.resolve_path(info)
	if image_path == "":
		image_path = CharacterImage.DEFAULT_MALE_PATH
	var texture: Texture2D = load(image_path)
	if texture == null:
		spr.texture = null
		return

	var ts := texture.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var box := Rect2(BIG_X + BIG_ART_PAD, BIG_Y + BIG_ART_TOP,
			BIG_W - BIG_ART_PAD * 2.0, BIG_H - BIG_ART_TOP - BIG_ART_PAD)
	var r: float = minf(box.size.x / ts.x, box.size.y / ts.y)
	var drawn := ts * r

	spr.texture = texture
	spr.scale = Vector2(r, r)
	spr.position = box.position + (box.size - drawn) * 0.5 + drawn * 0.5


# ============================================================
#  右栏文字
# ============================================================

func descriptiondeal() -> void:
	$margin/description.text = String(info.get('description', ""))


## 属性：4 格 2×2（印章烤在贴图里，这里只补**文字**）。
## 显示口径沿用现役：**生效值**（裸值 + tag bonus + 装备 bonus）为主；
## 有修正时把**裸值**以小字括注在数字右侧（无修正不显示）。
func attrsdeal(character_name: String) -> void:
	# 幂等：卸装备 / 换装后要就地重刷（见 `_on_equipment_gui_input`），先把上一轮的
	# 4 组 Label 摘掉 —— 只 queue_free 不加 remove_child 的话，同帧重名会被 Godot 改名成
	# `@an0@2`，下一轮就再也找不到它们，越叠越多。
	for i in ATTR_ORDER.size():
		for prefix in ["an", "av", "ab"]:
			var old := $margin.get_node_or_null("%s%d" % [prefix, i])
			if old != null:
				$margin.remove_child(old)
				old.queue_free()
	var base_attrs := {
		"int": int(info['int']), "app": int(info['app']),
		"str": int(info['str']), "bod": int(info['bod']),
	}
	var eff: Dictionary = Player.effective_npc_attrs(character_name)
	var eff_vals: Array = []
	var f: Font = _ui_font()

	for i in ATTR_ORDER.size():
		var k: String = ATTR_ORDER[i]
		var b := int(base_attrs.get(k, 0))
		var e := int(eff.get(k, 0))
		eff_vals.append(e)

		var col_x: float = float(ATTR_COL_X[i % 2])
		var cy: float = ATTR_CY0 + float(i / 2) * ATTR_ROW_H
		var nx: float = col_x + ATTR_NAME_DX
		var vx: float = col_x + ATTR_VAL_DX

		var nl := Label.new()
		nl.name = "an%d" % i
		nl.text = String(ATTR_CN[k])
		nl.position = Vector2(nx, cy - ATTR_NAME_FONT * ATTR_NAME_K)
		nl.size = Vector2(80.0, 24.0)
		nl.add_theme_font_size_override("font_size", ATTR_NAME_FONT)
		nl.add_theme_color_override("font_color", NAME_INK)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$margin.add_child(nl)

		if e != b:
			# 括注跟在数字**右边**（旧版放左边，那是「名 → 值」之间有空档的排法；
			# 现在名与值紧挨着，左边没有位置了）。
			var vw := 20.0
			if f != null:
				vw = f.get_string_size(str(e), HORIZONTAL_ALIGNMENT_LEFT, -1, ATTR_VAL_FONT).x
			var bl := Label.new()
			bl.name = "ab%d" % i
			bl.text = "(%d)" % b
			bl.position = Vector2(vx + vw + 6.0, cy - 4.0)
			bl.size = Vector2(40.0, 20.0)
			bl.add_theme_font_size_override("font_size", 12)
			bl.add_theme_color_override("font_color", NAME_INK)
			bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			$margin.add_child(bl)

		var vl := Label.new()
		vl.name = "av%d" % i
		vl.text = str(e)
		vl.position = Vector2(vx, cy - ATTR_VAL_FONT * ATTR_VAL_K)
		vl.size = Vector2(80.0, 44.0)
		vl.add_theme_font_size_override("font_size", ATTR_VAL_FONT)
		vl.add_theme_color_override("font_color", _val_col(e))
		# 主题只有**一个字重**（`font_cute.tres` 是单个 SystemFont，没有 bold 变体）
		# → 用同色 1px 描边冒充加粗。
		vl.add_theme_constant_override("outline_size", 1)
		vl.add_theme_color_override("font_outline_color", _val_col(e))
		vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$margin.add_child(vl)


## 数值色。阈值与 `make_character_panel_asset.tier_col` 一致（≥7 / ≥4 / 其余），只换具体色值。
static func _val_col(v: int) -> Color:
	if v >= 7:
		return VAL_HI
	if v >= 4:
		return VAL_MID
	return VAL_LOW


# ============================================================
#  标签 / 装备（悬浮提示沿用 tagtip）
# ============================================================

func tagsdeal():
	# 反转遍历：按注册表（tags.json）顺序渲染玩家持有的 tag。
	# 有界（注册表规模），与玩家 tag 数无关；流程 tag（不在注册表）自动过滤。
	for ch in $margin/tags.get_children():
		ch.queue_free()
	for data in TagRegistry.display_tags(info['tags']):
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = CHIP_FILL
		sb.border_color = CHIP_EDGE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(8)
		sb.anti_aliasing = true
		# 内边距对齐出图脚本：字距胶囊左缘 13px、上缘 7px，胶囊高 34
		sb.content_margin_left = 13.0
		sb.content_margin_right = 13.0
		sb.content_margin_top = 7.0
		sb.content_margin_bottom = 9.0
		chip.add_theme_stylebox_override("panel", sb)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.mouse_entered.connect(_on_tags_hover.bind(data))
		chip.mouse_exited.connect(_on_tags_leave)

		var name_label := Label.new()
		name_label.text = data
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", INK_TEXT)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(name_label)

		$margin/tags.add_child(chip)


func _on_tags_hover(tag_name):
	var tag: Dictionary = TagRegistry.get_tag(tag_name)
	var text: String = tag.get("description", "")
	var bonus: Dictionary = TagRegistry.get_bonus(tag_name)
	if not bonus.is_empty():
		var segs: Array = []
		for k in bonus:
			segs.append("%s%+d" % [ATTR_CN.get(String(k), String(k)), int(bonus[k])])
		text += "\n（属性修正：" + " ".join(segs) + "）"
	tagtip.text = text
	tagtip.size = Vector2(220, 320)
	_show_tip(Vector2(20, 6))


func _on_tags_leave():
	tagtip.hide()


## 装备：**三张迷你卡固定都在**（由后到前叠在主卡左后方），空槽画类型符号、已装备贴物品竖图。
##
## ⚠️ 与旧版（850×700 那一版）的行为差别：旧版**空槽不画**，于是「没装备」和「没这一栏」
##    在画面上是同一件事。新版照设计稿固定画三个槽 —— 空槽本身是信息（「这里可以放」）。
func equipmentdeal(data) -> void:
	var box := $margin/equipment as Control
	for ch in box.get_children():
		ch.queue_free()

	for i in SLOTS3.size():
		var cls: String = SLOTS3[i]
		var item: String = ""
		if data is Dictionary and data.has(cls):
			item = String(data[cls])
		var slot := _make_equip_card(cls, item)
		slot.position = EQ_XY[i]
		box.add_child(slot)
		_apply_card_sizes(slot)


## 一张装备迷你卡：卡面 + （已装备 → 物品竖图 / 空槽 → 类型符号）。
## 注意：**所有位置/尺寸在 `_apply_card_sizes` 里统一设**，且必须在 add_child 之后调
## （见该函数的注释）。这里只负责建节点与挂内容。
func _make_equip_card(cls: String, item: String) -> Control:
	var slot := Control.new()
	slot.name = "eq_%s" % cls
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	if item != "":
		slot.mouse_entered.connect(_on_equipment_hover.bind(item))
		slot.mouse_exited.connect(_on_equipment_leave)
		# 已装备的槽要能点（卸下），STOP 才收得到 gui_input；空槽保持 PASS 穿透。
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_equipment_gui_input.bind(cls, item))

	var face := TextureRect.new()
	face.name = "face"
	face.texture = _get_card_tex()
	# ⚠ EXPAND_IGNORE_SIZE 必须显式设：默认 KEEP_SIZE 会把控件最小尺寸顶成贴图原始尺寸（360×636）。
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(face)

	if item != "":
		var art := TextureRect.new()
		art.name = "art"
		art.texture = _item_icon(item)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(art)
	else:
		var gl := TextureRect.new()
		gl.name = "glyph"
		gl.texture = load(String(EQ_GLYPH_TEX[cls]))
		gl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gl.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		# 贴图是**纯白 + alpha**，靠 modulate 上色 → 一张贴图服务「空槽 / 已装备」两态
		gl.modulate = GLYPH_EMPTY
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(gl)

	return slot


## 给迷你卡的每一块摆正位置与尺寸。**必须在 slot 入树之后调用。**
## ⚠ 实测（2026-09-30）：**控件入树前设的 size 会被静默改写**回「贴图原始尺寸 /
## 文字自然宽度」——卡面 60×106 变 360×636、卡名 44 宽变 112 宽；而同一时刻
## `get_combined_minimum_size()` 已经是 0 / 1，所以**不是最小尺寸顶的**。
## 入树后再设一遍就稳定生效（三种控件都验过）。
func _apply_card_sizes(slot: Control) -> void:
	slot.size = Vector2(EQ_W, EQ_H)

	var face := slot.get_node_or_null("face") as Control
	if face != null:
		face.position = Vector2.ZERO
		face.size = Vector2(EQ_W, EQ_H)

	# 图像区 = 卡面内缩（与出图脚本 `_card(art_pad=9, art_top=20)` 一致）
	var bx := EQ_ART_PAD
	var by := EQ_ART_TOP
	var bw := EQ_W - EQ_ART_PAD * 2.0
	var bh := EQ_H - EQ_ART_TOP - EQ_ART_PAD

	var art := slot.get_node_or_null("art") as Control
	if art != null:
		art.position = Vector2(bx, by)
		art.size = Vector2(bw, bh)

	var gl := slot.get_node_or_null("glyph") as Control
	if gl != null:
		# 贴图原生 96×96 —— **按原生尺寸摆**（1:1 贴，缩放会二次采样出糊边）
		gl.position = Vector2(bx + (bw - EQ_GLYPH_BOX) * 0.5, by + (bh - EQ_GLYPH_BOX) * 0.5)
		gl.size = Vector2(EQ_GLYPH_BOX, EQ_GLYPH_BOX)


## 装备图标：走注册表（`resoures/items/equipment.json` 的 icon），拿不到就不画图标。
func _item_icon(item: String) -> Texture2D:
	var d: Dictionary = TagRegistry.get_equipment(item)
	var p: String = String(d.get("icon", ""))
	if p == "" or not ResourceLoader.exists(p, "Texture2D"):
		return null
	return load(p)


func _get_card_tex() -> Texture2D:
	if _card_tex == null and ResourceLoader.exists(CARD_TEX, "Texture2D"):
		_card_tex = load(CARD_TEX)
	return _card_tex


## 量文字用的字体：必须从**已在树上**的控件取（项目主题走 theme chain，
## 还没 add_child 的 Label 拿不到主题 → get_theme_font 返回 null，会把「放不下」误判成「放得下」）。
func _ui_font() -> Font:
	var lb := $margin/charname as Label
	return lb.get_theme_font("font") if lb != null else null


func _on_equipment_hover(equip_name):
	var data: Dictionary = TagRegistry.get_equipment(equip_name)
	tagtip.text = data.get("description", "")
	tagtip.size = Vector2(400, 120)
	_show_tip(Vector2(3, 15))


func _on_equipment_leave():
	tagtip.hide()


## 点已装备的槽 = **卸下**，装备回手牌。
##
## 为什么必须有这条：装上之后没有取回入口的话，唯一的首饰装给 A 就再也拿不回来，
## 换人只能靠「再找一件同类的来替换」—— 玩家会当 bug 报。
## 装备本身不销毁（它只是一条 JSON 数据），所以回手牌时按名字重造一张卡即可。
func _on_equipment_gui_input(event: InputEvent, cls: String, item: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	# ⚠️ 不能写 `accept_event()`：本脚本的根是 PopupPanel（Window），不是 Control，
	#    没有这个方法（会直接 Parse Error，整个面板脚本加载失败）。点击落在 slot 这个
	#    Control 上，事件到这就散了，不会再冒到别处 —— 不需要额外吞。
	tagtip.hide()
	var removed := Player.unequip_slot(_owner_key, cls)
	if removed == "" or removed != item:
		return
	var card: CardData = CardRegistry.get_card(removed)
	if card == null:
		var d: Dictionary = TagRegistry.get_equipment(removed)
		if not d.is_empty():
			card = CardData.from_item(removed, d)
	if card != null:
		var area := TriggerManager.get_card_area()
		if area != null:
			area.add_card(card)
		else:
			Player.add_hand_card(card)
	AudioManager.play_sfx("ui_card_place_ok")
	# 就地重刷：三槽 + 属性（生效值里那件装备的 bonus 已经没了）。
	equipmentdeal(Player.equipment_map_of(_owner_key))
	attrsdeal(_owner_key)


func _show_tip(offset: Vector2) -> void:
	$margin.move_child(tagtip, -1)
	tagtip.position = get_viewport().get_mouse_position() + offset
	tagtip.show()


## 属性文本（括号式）：生效值 主 + 裸值括注；无修正时不加括号。
## 仍保留给外部（如 debug 探针 / 后续 tooltip）复用。
func _attr_text(base: Dictionary, eff: Dictionary) -> String:
	var lines: Array = []
	for k in ATTR_CN:
		var cn: String = ATTR_CN[k]
		var b := int(base.get(k, 0))
		var e := int(eff.get(k, 0))
		if e == b:
			lines.append("%s %d" % [cn, e])
		else:
			lines.append("%s %d (%d)" % [cn, e, b])
	return "\n".join(lines) + "\n"
