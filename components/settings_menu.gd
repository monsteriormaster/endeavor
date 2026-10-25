class_name SettingsMenu
extends Control

## 设置页（整屏一页）—— 由网页稿 `design/settings_panel/index.html` 实装进引擎。
##
## ▍它替换掉了什么
##   旧的 `settings_menu` 是 `art/ui/settings_panel.png` 那张 **480x480** 的小面板，
##   里面是「保存进度 / 读取存档 / 成就 / 返回标题 / 关闭 + 文字大小」。
##   现在统一成用户拍板的那一页：**语言 / 字体大小 / 声音（五路总线）/ 返回 / 返回主菜单 / 退出游戏**。
##   ⚠️ 因此「读取存档」「成就」「手动保存」在本页**没有入口**了 ——
##      成就从标题页进（`loading.tscn`），读档走标题页「继续游戏」，
##      存档本来就是自动的（`main_ui.gd` 过天 / `tutorial_manager.gd`）。**这是用户口径**。
##
## ▍几何：绝对坐标（1920x1080，工程 stretch = canvas_items + keep、逻辑分辨率恒定）
##   所有数字照抄网页稿的 `.sheet / .head / .body / .row / .foot` 实测 rect ——
##   也就是 `design/settings_panel/_probe.txt` 里那一串读数。**一处没改**，
##   所以「网页稿量出来是什么样，实机就是什么样」，而且探针可以拿同一串数字**逐行对差**。
##   ⚠️ 纸页素材 `settings_sheet.png` 四周留了 70px 透明边（放投影）⇒ 贴到 (300,50)。
##
## ▍网页稿 vs 实机：一处**故意**的不同（别当成抄漏）
##   网页稿的 `.sheet`（那张纸）**不参与翻页**，只有 `.pg-main / .pg-set`（纸上的内容层）被
##   `clip-path` 裁切 —— 因为它是个「两页假 UI」的演示稿，纸底下本来就没有别的东西。
##   实机底下是**真的游戏画面**：若只裁内容层，p=0 时会露出「一层空纱 + 一张空白纸」。
##   所以这里把 **外圈纱 + 纸页 + 内容 + 涂鸦** 整体当成一页纸（= 网页稿的 `#stage`）。
##   折线几何、影子、时长、缓动全部不变，变的只是「谁算那一页」。
##
## ▍外圈背景 = **空背景**（2026-10-09 用户拍板「设置外为空背景（也就是和成就页一样）」）
##   这里原本铺一张 `art/ui/settings_desk.png`（1920×1080 深色书桌，由网页稿 `.bg` 那三层
##   渐变烘出来）—— 那是「一盏灯照着的桌面」的写法，纸页靠暗底立起来。
##   现在换成**与成就画卷逐位相同的两层全屏纱**（`achievement_list.tscn` 的 VeilWarm / VeilDark），
##   即「底下是什么就透出什么」：设置页从标题页呼出就透标题页，从游戏内呼出就透游戏画面。
##   ⚠️ 因此 `settings_desk.png` **在本组件里已不再被引用**（素材留档，未删）；
##      `design/_tools/make_settings_page_assets.py` 仍会烘它，重烘不会影响实机。
##
## ▍翻页（用户原话「主界面……也做同样的动画」）
##   翻页本体收在 `script/paper_flip.gd`（`PaperFlip`），本组件只负责「哪棵子树是一页纸、
##   什么时候翻」。折线自**左→右**扫过：折线左侧是设置页、右侧仍是底下那一屏。
##   · 折线是**斜的**（顶边超前 TILT px）——画成竖直线就退化成普通擦除，这是它与擦除唯一的区别。
##   · 影子 = 与折线平行的铅笔排线（见 `script/paper_fold.gd`）。
##   · 缓动 `(1-cos πt)/2`、0.5s、两端速度为 0（起步「纸被顶一下」、落地不飘）。
##     ⚠️ **不要改回 EASE_OUT**：本页正文只到纸页局部 x=686，EASE_OUT 会把 **60.1%** 的时长
##        花在扫「右边那半张空白纸」上；EASE_IN_OUT 压到 **44.5%**（同一把尺子量的，
##        见 `design/settings_panel/_ease.py`）。这个差别**在静止帧里逐像素一样**，只看图发现不了。
##
## ▍为什么生命周期不走 OverlayRoot.close_top
##   `close_top()` 在 `node.call(close_method)` 之后会兜底 `close_overlay(node)` ⇒ **立刻 queue_free**，
##   0.5s 的翻页动画会被砍在第 0 帧。所以：
##   · **调用方**入栈必须用 `esc_closes: false, persist: true`（见 `main_ui.gd / loading.gd`）；
##     `persist` 是为了「返回主菜单」那条路 —— 换场景后本页还要活着把翻页演完。
##   · Esc 由本组件自己接（`_unhandled_key_input`，语义不变，只关自己）。
##   · 关闭时先翻出去，动画跑完再 `OverlayRoot.close_overlay(self)`。
##
## 用法：
##   var menu := load("res://components/settings_menu.tscn").instantiate() as SettingsMenu
##   OverlayRoot.push_overlay(menu, {"modal": true, "esc_closes": false, "persist": true})

signal closed

const SHEET_TEX: Texture2D = preload("res://art/ui/settings_sheet.png")
const DOODLE_TEX: Texture2D = preload("res://art/ui/doodle_idle.png")
const FLOURISH_TEX: Texture2D = preload("res://art/ui/flourish.png")
const KNOB_L: Texture2D = preload("res://art/ui/slider_knob_l.png")
const RULE_SCRIPT: GDScript = preload("res://components/ui_rule.gd")
const CONFIRM_DIALOG_PATH := "res://components/confirmdialog.tscn"
const TITLE_SCENE := "res://scene/loading.tscn"

# ---------------------------------------------------------------- 屏幕几何（照抄 `_probe.txt`）
const SHEET_X := 370.0                    # .sheet rect=370,120,1180,840
const SHEET_Y := 120.0
const SHEET_W := 1180.0
const SHEET_H := 840.0
const SHEET_PAD := 70.0                   # settings_sheet.png 的透明边
const PAD_L := 66.0                       # 纸内左右内边距（.pg padding）
const CX := SHEET_X + PAD_L               # 436  内容左缘
const CW := SHEET_W - PAD_L * 2.0         # 1048 内容宽
const COL_W := 620.0                      # 正文左栏宽（标签列 + 控件列 + 数值列）
const K_W := 156.0                        # 标签列（.row>.k）
const V_W := 54.0                         # 数值列（.row>.v）
const CTRL_X := CX + K_W                  # 592  控件（滑条/牌子）左缘（.row>.c）
const CTRL_GAP := 14.0                    # .row>.c 的 gap
const SLIDER_W := COL_W - K_W - V_W - CTRL_GAP   # 396
const ROW_H := 54.0
const BTN_W := 192.0
const BTN_H := 58.0
const BTN_GAP := 16.0
## 页脚按钮，自左至右。前两颗是**进度**操作（2026-10-13 新增，D-SV10）：
## 原来只有「返回 / 返回主菜单 / 退出游戏」三颗，且本页刻意没有存档入口
## （旧口径「存档本来就自动」）。现在对话界面能呼出本页，玩家需要在对话中存 / 读档。
const FOOT_TEXTS := ["保存进度", "读取存档", "返回", "返回主菜单", "退出游戏"]
## ⚠️ 页脚按钮带是 **右对齐** 的，现在扩到**内容全宽**：
##    网页稿 `.foot{width:620px}` 只够三颗（620 = 3×192 + 2×16），塞不下新增的两颗 ⇒
##    右缘由 1056 放宽到内容右缘 1484。原来那三颗的相对次序与「退出游戏在最右」不变。
##    5 颗 × 192 + 4 × 16 = 1024 ⇒ 起点 = 1484 - 1024 = 460（> 内容左缘 436，仍在纸内）。
const BTN_X := 460.0
const BTN_Y := 812.0                      # .foot 顶 798 + padding-top 14
const DOODLE_X := 1150.0                  # 绝对屏坐标（网页稿 .doodlewrap rect=1150,590）
const DOODLE_Y := 590.0

# 行的 y（全部来自 `_probe.txt` 的 rect 读数）
const Y_TITLE := 174.0                    # .head 顶（= sheet 顶 120 + padding 54）
const TITLE_H := 46.0
const Y_FLOURISH := 226.5                 # 261 - 34.5（.head 底）
const Y_RULE := 275.0                     # .head 底 261 + margin 14
const Y_LANG := 288.0
const Y_FONT := 342.0
const Y_SAMPLE := 398.0
const Y_SECHEAD := 484.0
const Y_BUS0 := 528.0                     # 总音量；其后每行 +54
const Y_FOOT := 798.0

## 一键静音开关（审计 A4，2026-10-14 实装）。摆在「声音」小节抬头那一行的**右端**，
## 右缘对齐数值列右缘 `CX + COL_W` = 1056 —— 与下面五路音量的读数落在同一条竖线上。
## ⚠️ 为什么不另开一行：本页每一行的 y 都照抄网页稿 `_probe.txt` 的 rect 读数，正文到页脚
##    798 就用满了。再插一行必须把五路音量或整条页脚往下挪，那会一次毁掉两组锚点。
##    而抬头这一行本来就空着一段（原来放「五路总线」四个小字），放这里零位移。
const MUTE_BOX := 26.0
const MUTE_BOX_X := CX + COL_W - MUTE_BOX                 # 1030
const MUTE_LABEL_W := 60.0
const MUTE_LABEL_X := MUTE_BOX_X - 10.0 - MUTE_LABEL_W    # 960
const Y_MUTE := Y_SECHEAD + 8.0                           # 492  方框顶（行高 42、框 26 ⇒ 居中）

# 颜色（= 网页稿 `:root` 的 A 套 token）
const C_INK := Color(0.176, 0.133, 0.082)      # #2D2215
const C_INK2 := Color(0.353, 0.302, 0.243)     # #5A4D3E
const C_INK3 := Color(0.541, 0.459, 0.353)     # #8A755A
const C_CU := Color(0.451, 0.333, 0.145)       # #735525
const C_CU_LT := Color(0.561, 0.424, 0.180)    # #8F6C2E
const C_PAPER_HI := Color(1.0, 0.988, 0.957)   # #FFFCF4

## 外圈「空背景」的两层全屏纱。数值 = `components/achievement_list.tscn` 的 VeilWarm / VeilDark
## —— 两页要看起来是同一套系统，色值和叠放顺序**必须逐位一致**，改一处就得改两处。
const VEIL_WARM := Color(0.894, 0.867, 0.812, 0.26)
const VEIL_DARK := Color(0.275, 0.212, 0.141, 0.28)

## 音量/字号这类会**写盘**的设置：拖动时的合并窗口（秒）。
## ⚠️ `AudioManager.set_bus_volume` / `Settings.set_text_font_size` 每次调用都会落盘
##    （`Settings._save()` = 写 tmp + 读回校验 + rename）⇒ **绝不能直接挂在 `value_changed` 上**
##    拖动时会一帧写一次盘。`AudioManager` 的文件头也专门写了这条。
const COMMIT_DEBOUNCE := 0.2

## 五路音量行：( 小写总线键, 主标签, 副标签 )。顺序 = 网页稿自上而下。
## 键必须落在 `Settings.AUDIO_KEYS` / `AudioManager.MIX_BUSES` 里（都是小写）。
const BUS_ROWS := [
	["master", "总音量", "Master"],
	["music", "音乐", "Music"],
	["sfx", "音效", "SFX"],
	["ui", "界面音", "UI"],
	["ambience", "环境音", "Ambience"],
]

var _page: Control = null
var _content: Control = null
var _flip: PaperFlip = null

var _closing: bool = false

var _sample_label: Label = null
var _font_slider: HSlider = null
var _font_value: Label = null
var _bus_sliders: Dictionary = {}        # 总线键 → HSlider
var _bus_values: Dictionary = {}         # 总线键 → Label
var _commit_timer: SceneTreeTimer = null
## 页脚按钮的反馈计时器（「已保存」/「没有存档」短暂替换按钮文字后还原）
var _flash_timer: SceneTreeTimer = null
var _pending: Dictionary = {}            # 待落盘的设置：{"font": int} / {"bus:键": [键, 线性]}
var _row_rects: Dictionary = {}
var _mute_box: Panel = null
var _mute_tick: Control = null
var _mute_hover: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 模态：吃掉落到本页的点击
	_build()
	# p=0 起步（纸一点没露），然后立刻开翻。
	_flip.play(0.0, 1.0)


# ================================================================ 建树
func _build() -> void:
	_page = Control.new()
	_page.name = "Page"
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_page)

	# 外圈 = 空背景：两层全屏纱，与成就画卷同一套（见文件头「外圈背景」）
	_page.add_child(_veil("VeilWarm", VEIL_WARM))
	_page.add_child(_veil("VeilDark", VEIL_DARK))
	_page.add_child(_tex(SHEET_TEX, "Sheet",
		SHEET_X - SHEET_PAD, SHEET_Y - SHEET_PAD,
		SHEET_W + SHEET_PAD * 2.0, SHEET_H + SHEET_PAD * 2.0))
	var doodle := _tex(DOODLE_TEX, "Doodle", DOODLE_X, DOODLE_Y, 400.0, 300.0)
	# 网页稿 `.doodlewrap{mix-blend-mode:multiply;opacity:.92}`。
	# 这张 PNG 自带真透明通道（笔迹 11.4% 非空），普通 alpha 合成与 multiply 等价 ⇒ 不用材质。
	doodle.modulate.a = 0.92
	_page.add_child(doodle)

	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(_content)

	_build_head()
	_build_language_row()
	_build_font_row()
	_build_sound_section()
	_build_foot()

	# 翻页层：**必须是最后一个孩子**（它就是画在最上面的那条线），
	# 且**不能**被算进 `_page`（见 `paper_flip.gd` 文件头那条红线）。
	_flip = PaperFlip.new()
	_flip.name = "Flip"
	add_child(_flip)
	_flip.setup([_page])
	_flip.set_side(1.0)      # 左侧是新翻进来的设置页 ⇒ 折线扫过 = 把它盖上


func _tex(t: Texture2D, nm: String, x: float, y: float, w: float, h: float) -> TextureRect:
	var n := TextureRect.new()
	n.name = nm
	n.texture = t
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.position = Vector2(x, y)
	n.size = Vector2(w, h)
	return n


## 全屏纱（外圈空背景）。写法与相邻的 `_tex(...)` 对齐：**绝对 (0,0,1920,1080)**。
## 工程 stretch = canvas_items + keep、逻辑分辨率恒定 ⇒ 绝对尺寸与锚点铺满等价；统一成一种写法，
## 探针才能用同一把尺子对差（`rows` 里的 rect 全是绝对坐标）。
func _veil(nm: String, col: Color) -> ColorRect:
	var n := ColorRect.new()
	n.name = nm
	n.color = col
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.position = Vector2(0.0, 0.0)
	n.size = Vector2(1920.0, 1080.0)
	return n


func _label(text: String, fs: int, col: Color, x: float, y: float, w: float, h: float,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	_content.add_child(l)
	return l


func _build_head() -> void:
	# 网页稿 `h1{font-size:42px;letter-spacing:.18em}` —— Godot 的 Label 没有字距，
	# 用「字与字之间插一个空格」等价代掉（本工程既有做法）。
	_label("设 置", 42, C_INK, CX, Y_TITLE, CW, TITLE_H)
	# `.head .flourish{width:250px;margin:6px 0 0 -4px;opacity:.9}` → 左缘 436-4=432
	var fl := _tex(FLOURISH_TEX, "Flourish", CX - 4.0, Y_FLOURISH, 250.0, 34.5)
	fl.modulate.a = 0.90
	_content.add_child(fl)

	# 分隔线是**两根**（网页稿 `.rule` 里两条 path）：铜色 2px + 亮铜 1px。
	# 线比 `.head` 的盒子宽 —— 网页稿那条 path 一直画到纸页右缘（x=1118 于 1048 宽的盒子里，
	# `overflow:visible` 放它出来）。这里照做：从 CX+2 拉到纸内右缘前 2px。
	var rule_w := (SHEET_X + SHEET_W - 2.0) - (CX + 2.0)
	_content.add_child(_rule(CX + 2.0, Y_RULE, rule_w, 2.0,
		Color(C_CU.r, C_CU.g, C_CU.b, 0.52)))
	_content.add_child(_rule(CX + 2.0, Y_RULE + 3.0, rule_w, 1.0,
		Color(C_CU_LT.r, C_CU_LT.g, C_CU_LT.b, 0.34)))

	# 供探针逐行对差（数字 = `_probe.txt` 里 `.head` / `.rule` 的 rect）
	_row_rects["head"] = Rect2(CX, Y_TITLE, CW, 87.0)
	_row_rects["rule"] = Rect2(CX, Y_RULE, CW, 7.0)
	_row_rects["body"] = Rect2(CX, Y_LANG, CW, 626.0)
	_row_rects["col"] = Rect2(CX, Y_LANG, COL_W, 582.0)


## A 套分隔线（项目现成构件 `ui_rule`）。**只画形状，不画文字**。
## ⚠️ `ui_rule` 把线画在自己的**竖直中位**，所以「想让线落在 y 上」给的是 `y - h/2`；
##    这里统一按 `h` 内的中位来摆（h=7 时中位 +3.5，与网页稿 `M2 3.5` 对上）。
func _rule(x: float, y: float, w: float, lw: float, col: Color) -> Control:
	var r := Control.new()
	r.set_script(RULE_SCRIPT)
	r.set("show_ends", false)
	r.set("show_line", true)
	r.set("line_w", lw)
	r.set("line_color", col)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(x, y)
	r.size = Vector2(w, 7.0)
	return r


func _row_kv(label: String, sub: String, y: float) -> void:
	_label(label, 19, C_INK, CX, y + 3.0, K_W, 26.0)
	if sub != "":
		_label(sub, 12, C_INK3, CX, y + 27.0, K_W, 20.0)


func _row_value(text: String, y: float) -> Label:
	return _label(text, 17, C_INK2, CX + COL_W - V_W, y, V_W, ROW_H,
		HORIZONTAL_ALIGNMENT_RIGHT)


## 语言行：代码里**没有**语言项（全工程搜不到 locale / TranslationServer）⇒ 只有一个选项。
## 照网页稿做成一颗**暗色牌子**（`.pill.dim`）而不是能按的按钮：
## 「一个按不动的牌子」本身就把「这一项现在不可选」说清了。
## ⚠️ 牌子上**不放下拉箭头**（审计 S1，2026-10-14 去掉）：网页稿那颗三点折线是「这里能展开」
##    的暗示，而本工程只有一个语言、展开不出任何东西 —— 留着它等于挂一个永远兑不了的承诺。
##    少一个可点的假象，比多一个装饰重要。
func _build_language_row() -> void:
	_row_rects["lang"] = Rect2(CX, Y_LANG, COL_W, ROW_H)
	_row_kv("语言", "目前只有中文", Y_LANG)

	var pill_w := 156.0
	var pill_y := Y_LANG + (ROW_H - 40.0) * 0.5      # .c 竖直居中，牌高 40
	var box := Panel.new()
	box.name = "LangPill"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_PAPER_HI.r, C_PAPER_HI.g, C_PAPER_HI.b, 0.42)
	sb.set_border_width_all(0)
	sb.border_width_left = 2       # 1.6px 的四边描边：StyleBoxFlat 只支持整数宽度，取 2 最接近
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(C_CU.r, C_CU.g, C_CU.b, 0.52)
	sb.set_corner_radius_all(3)
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(CTRL_X, pill_y)
	box.size = Vector2(pill_w, 40.0)
	_content.add_child(box)

	var txt := Label.new()
	txt.text = "简体中文"
	txt.add_theme_font_size_override("font_size", 17)
	txt.add_theme_color_override("font_color", C_INK)
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.position = Vector2(14.0, 0.0)          # .pill padding 0 14px
	txt.size = Vector2(pill_w - 28.0, 40.0)    # 左右各 14，箭头撤掉后不必再留它那 18px
	box.add_child(txt)

	# `.v` 是空的（网页稿这一行没有数值），但保留占位，让行宽与其它行一致。
	_row_value("", Y_LANG)


func _build_font_row() -> void:
	_row_rects["font"] = Rect2(CX, Y_FONT, COL_W, ROW_H)
	_row_kv("字体大小", "对话框与正文", Y_FONT)
	_font_slider = _slider(CTRL_X, Y_FONT + 14.0, SLIDER_W,
		12.0, 32.0, 1.0, float(Settings.text_font_size))
	_font_slider.name = "FontSlider"           # 名字给探针用（按名取节点，不必把引用暴露出去）
	_font_slider.value_changed.connect(_on_font_slider)
	_font_value = _row_value(str(Settings.text_font_size), Y_FONT)

	# 字迹样张：字号一动就跟着变 —— 这块存在的意义就是「改了立刻看得见」。
	# `.sample{margin:2px 0 8px 156px;padding:10px 14px;border-left:3px solid rgba(143,108,46,.42);
	#          background:rgba(255,252,244,.30);min-height:44px}` → 盒高 64
	var box := Panel.new()
	box.name = "FontSample"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_PAPER_HI.r, C_PAPER_HI.g, C_PAPER_HI.b, 0.30)
	sb.border_width_left = 3
	sb.border_color = Color(C_CU_LT.r, C_CU_LT.g, C_CU_LT.b, 0.42)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(CTRL_X, Y_SAMPLE)
	box.size = Vector2(COL_W - K_W, 64.0)
	_content.add_child(box)

	_sample_label = Label.new()
	_sample_label.text = "今天我想画一条河，河上有一座很旧的桥。"
	_sample_label.add_theme_font_size_override("font_size", Settings.text_font_size)
	_sample_label.add_theme_color_override("font_color", C_INK)
	_sample_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠️ Panel 不排子节点 ⇒ `content_margin` 只是写着给人看的，**必须自己缩字号框**，
	#    否则样张文字会顶在纸上那条铜色竖线上（网页稿 `.sample` 的 padding 是 10px 14px）。
	_sample_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sample_label.offset_left = 14.0
	_sample_label.offset_right = -14.0
	_sample_label.offset_top = 10.0
	_sample_label.offset_bottom = -10.0
	box.add_child(_sample_label)

	Settings.text_font_size_changed.connect(_on_font_size_changed)
	_row_rects["sample"] = Rect2(CTRL_X, Y_SAMPLE, COL_W - K_W, 64.0)


func _build_sound_section() -> void:
	_row_rects["sechead"] = Rect2(CX, Y_SECHEAD, COL_W, 42.0)
	_label("声音", 19, C_INK, CX, Y_SECHEAD, 52.0, 42.0)
	_build_mute_toggle()
	# 小节抬头右侧那根横线：从「声音」二字之后拉到静音开关之前。
	# ⚠️ 网页稿那条 path（`M0 1 L618 1`）比它的盒子（≈510px）长、靠 `overflow:visible`
	#    溢出去，实际会**从右端那几个字底下穿过去**。这里**故意不收**那个溢出：
	#    线在开关左缘前 12px 收住，保证「静音」二字与方框干干净净。
	var line_x := CX + 50.0
	var line_w := (MUTE_LABEL_X - 12.0) - line_x
	_content.add_child(_rule(line_x, Y_SECHEAD + 20.0, line_w, 1.6,
		Color(C_CU_LT.r, C_CU_LT.g, C_CU_LT.b, 0.44)))

	for i in BUS_ROWS.size():
		var row: Array = BUS_ROWS[i]
		var key: String = row[0]
		var y: float = Y_BUS0 + ROW_H * i
		_row_rects["bus_" + key] = Rect2(CX, y, COL_W, ROW_H)
		_row_kv(row[1], row[2], y)
		var v := int(round(AudioManager.get_bus_volume(key) * 100.0))
		var sl := _slider(CTRL_X, y + 14.0, SLIDER_W, 0.0, 100.0, 1.0, float(v))
		sl.name = "Bus_" + key                 # 名字给探针用
		sl.value_changed.connect(_on_bus_slider.bind(key))
		_bus_sliders[key] = sl
		_bus_values[key] = _row_value(str(v), y)


## 一键静音（审计 A4）。手搓一个纸上的小方框，**不用 `CheckBox`** ——
## 全工程的按钮都由 Autoload `ButtonSkin` 统一换皮，而 `CheckBox` 是 `Button` 的子类，
## 挂上去会被套上「能按的纸按钮」那层皮。勾选框要表达的是「开 / 关」，不是「按一下」，
## 所以照语言行那颗牌子的做法自建：`Panel` 方框 + 手绘勾 + 一个「静音」标签。
##
## 落盘走 `AudioManager.set_muted()`（它内部回调 `Settings.set_audio_muted()` 写盘）。
## 它不像滑条那样是连续值 —— 一次点击一次写盘，不必进 `COMMIT_DEBOUNCE` 那个合并窗口。
func _build_mute_toggle() -> void:
	_label("静音", 17, C_INK2, MUTE_LABEL_X, Y_SECHEAD + 6.0, MUTE_LABEL_W, 30.0,
		HORIZONTAL_ALIGNMENT_RIGHT)

	_mute_box = Panel.new()
	_mute_box.name = "MuteBox"
	_mute_box.mouse_filter = Control.MOUSE_FILTER_STOP
	_mute_box.position = Vector2(MUTE_BOX_X, Y_MUTE)
	_mute_box.size = Vector2(MUTE_BOX, MUTE_BOX)
	_content.add_child(_mute_box)

	# 勾用 `CanvasItem.draw` 就地画 —— 同语言行那颗旧箭头，不为一个记号单开脚本文件。
	_mute_tick = Control.new()
	_mute_tick.name = "Tick"
	_mute_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mute_tick.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mute_tick.draw.connect(_draw_mute_tick)
	_mute_box.add_child(_mute_tick)

	_mute_box.gui_input.connect(_on_mute_input)
	_mute_box.mouse_entered.connect(func() -> void: _sync_mute_view(true))
	_mute_box.mouse_exited.connect(func() -> void: _sync_mute_view(false))
	# 静音状态也可能从别处改（读档后套用设置）⇒ 跟着信号回填视图，别只认自己这一下点击。
	Settings.audio_muted_changed.connect(func(_muted: bool) -> void: _refresh_mute_view())
	_refresh_mute_view()


## 方框的皮。静置 / 悬浮两套预先生成好，切换只换 stylebox、不去改资源属性。
func _mute_stylebox(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_PAPER_HI.r, C_PAPER_HI.g, C_PAPER_HI.b, 0.62 if hover else 0.42)
	sb.set_border_width_all(2)
	sb.border_color = Color(C_CU.r, C_CU.g, C_CU.b, 0.95 if hover else 0.62)
	sb.set_corner_radius_all(3)
	return sb


## 切换悬浮态：鼠标进出方框时改皮的明暗。
func _sync_mute_view(hover: bool) -> void:
	_mute_hover = hover
	_refresh_mute_view()


## 按**当前的开关值**重画方框与勾。悬浮态取自 `_mute_hover`（不猜）。
## ⚠️ 不必在这里 `query_redraw` 之外多做判断：静音时勾不画，就是「没有勾」这一个事实。
func _refresh_mute_view() -> void:
	if _mute_box == null:
		return
	_mute_box.add_theme_stylebox_override("panel", _mute_stylebox(_mute_hover))
	if _mute_tick != null:
		_mute_tick.queue_redraw()


## 勾。方框 26×26，笔画在框内留 5px 净空。
func _draw_mute_tick() -> void:
	if _mute_tick == null or not AudioManager.is_muted():
		return
	_mute_tick.draw_polyline(
		PackedVector2Array([Vector2(6.0, 13.0), Vector2(10.5, 18.0), Vector2(19.5, 7.5)]),
		Color(C_CU.r, C_CU.g, C_CU.b, 0.94), 2.0, true)


## 点一下开关：翻转静音。关 → 开那一下**先解除静音再响一声**，让玩家立刻听到声音回来了；
## 开 → 关那一声正好被静音吃掉，不必特意跳过。
func _on_mute_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_mute_box.accept_event()
	AudioManager.set_muted(not AudioManager.is_muted())
	AudioManager.play_ui("ui_click_secondary")


## 滑条 —— 数值照抄网页稿 `.slider`：
##   track  `top:11;height:4;background:rgba(115,85,37,.26);border-radius:2px`
##   fill   `top:11;height:4;background:rgba(143,108,46,.72);border-radius:2px`
##   knob   26×26，`top:0;margin-top:-3`
## ⚠️ Godot 的 HSlider 把样式盒按**它自己的最小尺寸**竖直居中画 ⇒
##    想得到 4px 的槽，`content_margin_top/bottom` 必须是 **2**（2+2=4），不是 4。
## ⚠️ `grabber_offset = -3` 正好等于网页稿的 `margin-top:-3`，别改成 0。
## 钮用 26px 那颗 `slider_knob_l.png`（现役 `slider_knob.png` 是 14px 的，当年给 480x480 小面板用）。
func _slider(x: float, y: float, w: float, mn: float, mx: float, st: float, val: float) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = st
	sl.value = val
	sl.mouse_filter = Control.MOUSE_FILTER_STOP
	sl.position = Vector2(x, y)
	sl.size = Vector2(w, 26.0)
	sl.theme = _slider_theme()
	_content.add_child(sl)
	# 刻度：网页稿 `.ticks i` 五根 1.4×10 的小竖线（0/25/50/75/100%）。
	# 排在滑条**之后** ⇒ 画在槽上面；`mouse_filter=IGNORE` ⇒ 不吃拖动。
	_content.add_child(_ticks(x, y, w))
	# 松手立刻提交，不必等去抖窗口
	sl.drag_ended.connect(func(_changed: bool) -> void: _commit_now(_key_of(sl)))
	return sl


func _slider_theme() -> Theme:
	var th := Theme.new()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(C_CU.r, C_CU.g, C_CU.b, 0.26)
	track.set_corner_radius_all(2)
	track.content_margin_top = 2.0
	track.content_margin_bottom = 2.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.561, 0.424, 0.180, 0.72)
	fill.set_corner_radius_all(2)
	fill.content_margin_top = 2.0
	fill.content_margin_bottom = 2.0
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	th.set_icon("grabber", "HSlider", KNOB_L)
	th.set_icon("grabber_highlight", "HSlider", KNOB_L)
	th.set_icon("grabber_disabled", "HSlider", KNOB_L)
	th.set_constant("grabber_offset", "HSlider", -3)
	return th


## 五根刻度。滑条盒高 26、槽在 11..15 ⇒ 刻度从 y+10 起、高 10。
func _ticks(x: float, y: float, w: float) -> Control:
	var t := Control.new()
	t.name = "Ticks"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.position = Vector2(x, y + 10.0)
	t.size = Vector2(w, 10.0)
	t.draw.connect(func() -> void:
		var col := Color(C_CU.r, C_CU.g, C_CU.b, 0.34)
		for i in 5:
			var px := w * 0.25 * float(i)
			px = minf(px, w - 1.4)
			t.draw_rect(Rect2(px, 0.0, 1.4, 10.0), col))
	return t


func _key_of(sl: HSlider) -> String:
	for k in _bus_sliders:
		if _bus_sliders[k] == sl:
			return k
	return ""


func _build_foot() -> void:
	# `.foot{justify-content:flex-end;gap:16px;padding-top:14px}` ⇒ 右对齐、自 BTN_X 起
	for i in FOOT_TEXTS.size():
		var b := Button.new()
		b.name = "Foot%d" % i
		b.text = FOOT_TEXTS[i]
		b.add_theme_font_size_override("font_size", 19)
		b.position = Vector2(BTN_X + (BTN_W + BTN_GAP) * float(i), BTN_Y)
		b.size = Vector2(BTN_W, BTN_H)
		_content.add_child(b)
		match i:
			0: b.pressed.connect(_on_save_pressed)
			1: b.pressed.connect(_on_load_pressed)
			2: b.pressed.connect(func() -> void: close_menu())
			3: b.pressed.connect(_on_menu_pressed)
			4: b.pressed.connect(_on_quit_pressed)
	# 按钮带自 BTN_X 起跨到内容右缘（新增两颗后不再是 COL_W 的 620 宽）
	_row_rects["foot"] = Rect2(CX, Y_FOOT, CW, 72.0)


# ================================================================ 设置项 → 真接口
func _on_font_slider(value: float) -> void:
	# 只做「看得见」的部分：样张与读数立刻跟手；落盘走去抖
	var v := int(round(value))
	_sample_label.add_theme_font_size_override("font_size", v)
	_font_value.text = str(v)
	_pending["font"] = v
	_schedule_commit()


func _on_font_size_changed(size: int) -> void:
	if _sample_label != null:
		_sample_label.add_theme_font_size_override("font_size", size)
	if _font_slider != null and not is_equal_approx(_font_slider.value, float(size)):
		_font_slider.set_value_no_signal(float(size))
	if _font_value != null:
		_font_value.text = str(size)


func _on_bus_slider(value: float, key: String) -> void:
	_bus_values[key].text = str(int(round(value)))
	_pending["bus:" + key] = [key, clampf(value / 100.0, 0.0, 1.0)]
	_schedule_commit()


## 合并窗口：拖动期间攒着，停手 0.2s 或松手时一次性落盘。
func _schedule_commit() -> void:
	if _commit_timer != null:
		return
	_commit_timer = get_tree().create_timer(COMMIT_DEBOUNCE)
	_commit_timer.timeout.connect(_commit_now.bind(""))


func _commit_now(_key: String = "") -> void:
	_commit_timer = null
	if _pending.is_empty():
		return
	var todo := _pending.duplicate()
	_pending.clear()
	if todo.has("font"):
		Settings.set_text_font_size(int(todo["font"]))
	for k in todo:
		if k.begins_with("bus:"):
			var pair: Array = todo[k]
			AudioManager.set_bus_volume(pair[0], pair[1])


# ================================================================ 进度（存 / 读档，D-SV10）
## 本页新增两颗进度按钮。**剧情位置也在存档里** —— 从对话界面呼出本页时，
## `Player.plot` 正指向「当前那一句」，`save_game` 会一并写盘；
## 读档由 `SaveLoader.load_game` 换回存档场景，若那时正在剧情中，还会续播到中断的那一句。

## 「保存进度」：把当前 Player 状态写盘（含剧情位置锚点 Player.plot）。
func _on_save_pressed() -> void:
	_commit_now()                      # 顺手提交还没落盘的设置（拖滑块未松手就点保存）
	var ok: bool = SaveLoader.save_game()
	_flash_foot(0, "已保存" if ok else "保存失败")


## 「读取存档」：二次确认后读档（会丢弃当前未保存的进度）。
func _on_load_pressed() -> void:
	if not SaveLoader.has_save():
		_flash_foot(1, "没有存档")
		return
	var info: Dictionary = SaveLoader.peek_save_info()
	_confirm(
		"读取存档",
		"将回到「第 %d 天 · %s」，当前未保存的进度会丢失。确定吗？" % [
			int(info.get("time", 1)), String(info.get("player_name", ""))],
		_do_load)


## 读档：先让设置页**翻出去**（翻页跑完、自行出栈），再读档换场景。
## 反过来（先读档再翻页）会让换场景把翻页砍在第 0 帧 —— 与 `_goto_title` 同一处理。
func _do_load() -> void:
	close_menu(func() -> void: SaveLoader.load_game())


## 页脚按钮的轻量反馈：短暂把按钮文字换成结果（「已保存」/「没有存档」），1.4s 还原。
## 不做 Toast —— 复用按钮自身文字，零新素材、零新节点。
func _flash_foot(idx: int, msg: String) -> void:
	var b: Button = _content.get_node_or_null("Foot%d" % idx) as Button
	if b == null:
		return
	b.text = msg
	if _flash_timer != null and _flash_timer.timeout.is_connected(_restore_foot_labels):
		_flash_timer.timeout.disconnect(_restore_foot_labels)
	_flash_timer = get_tree().create_timer(1.4)
	_flash_timer.timeout.connect(_restore_foot_labels)


func _restore_foot_labels() -> void:
	for i in FOOT_TEXTS.size():
		var b: Button = _content.get_node_or_null("Foot%d" % i) as Button
		if b != null:
			b.text = FOOT_TEXTS[i]


# ================================================================ 出口
func _on_menu_pressed() -> void:
	if get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == TITLE_SCENE:
		close_menu()          # 本来就在主菜单上，等同于「返回」
		return
	_confirm("返回主菜单", "确定回到主菜单吗？未保存的进度会丢失。", _goto_title)


## 回主菜单：**先把标题场景换到纸页底下，再翻出去** —— 一次动作，不是「翻出去 + 再溶解」两次。
## 纸页以 `persist: true` 入栈（调用方的责任），所以 `OverlayRoot._on_scene_changed`
## 不会在换场景那一刻把它清掉；这里换完立刻开始翻页，动画结束时才出栈。
func _goto_title() -> void:
	if _closing:
		return
	get_tree().change_scene_to_file(TITLE_SCENE)
	EventSignal.scene_entered.emit(TITLE_SCENE)
	close_menu()


func _on_quit_pressed() -> void:
	close_menu(func() -> void: get_tree().quit())


## 关闭：先翻出去（折线左→右扫过，露出底下那一屏），动画跑完再出栈释放。
##
## ⚠️ **不要改成「先出栈再动画」**：`OverlayRoot.close_top()` 会在 `close_method` 之后
##    兜底 `close_overlay(node)` → 立刻 `queue_free()` → 动画砍在第 0 帧。
##    正因为这条，调用方入栈时用的是 `esc_closes: false` + 本组件自己接 Esc。
func close_menu(on_done: Callable = Callable()) -> void:
	if _closing:
		return
	_closing = true
	_commit_now()
	_flip.play(1.0, 0.0, func() -> void:
		closed.emit()
		if is_inside_tree():
			OverlayRoot.close_overlay(self)
		if on_done.is_valid():
			on_done.call())


func _unhandled_key_input(event: InputEvent) -> void:
	if _closing:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_menu()


func _confirm(dialog_title: String, message: String, on_confirm: Callable) -> void:
	var scene: PackedScene = load(CONFIRM_DIALOG_PATH)
	if scene == null:
		push_warning("SettingsMenu: 找不到 %s，跳过二次确认" % CONFIRM_DIALOG_PATH)
		on_confirm.call()
		return
	var dialog: Node = scene.instantiate()
	OverlayRoot.push_overlay(dialog, {
		"modal": true, "esc_closes": true, "close_method": "close_dialog",
	})
	dialog.setup(dialog_title, message)
	dialog.confirmed.connect(func() -> void: on_confirm.call())


# ================================================================ 翻页（对外）
func flip_in() -> void:
	_closing = false
	_flip.play(_flip.p(), 1.0, Callable())


func flip_p() -> float:
	return _flip.p()


func fold_layer() -> PaperFold:
	return _flip.fold()


# ================================================================ 探针接口
## 一次把验收要用的读数交出去。**探针不要自己另算一遍几何**（尺子编错了会伪装成实现错了）。
func probe_state() -> Dictionary:
	var rows := {}
	for k in _row_rects:
		var r: Rect2 = _row_rects[k]
		rows[k] = Rect2(r.position, r.size)
	var bus := {}
	for k in _bus_sliders:
		bus[k] = {
			"value": (_bus_sliders[k] as HSlider).value,
			"text": (_bus_values[k] as Label).text,
			"rect": (_bus_sliders[k] as HSlider).get_global_rect(),
			"linear": AudioManager.get_bus_volume(k),
			"server_db": _server_db(k),
		}
	return {
		"closing": _closing,
		"flip": _flip.probe_state() if _flip != null else {},
		"rows": rows,
		"page_rect": _page.get_global_rect() if _page != null else Rect2(),
		"veil_warm_rect": _rect_of("VeilWarm"),
		"veil_dark_rect": _rect_of("VeilDark"),
		"sheet_rect": _rect_of("Sheet"),
		"doodle_rect": _rect_of("Doodle"),
		"sample_rect": _rect_of("FontSample"),
		"font_slider": _font_slider.value if _font_slider != null else -1.0,
		"font_text": _font_value.text if _font_value != null else "",
		"sample_font_size": _sample_label.get_theme_font_size("font_size") if _sample_label != null else -1,
		"bus": bus,
		# 一键静音（审计 A4）。`muted` 是 `AudioManager` 的内存真值，
		# `mute_rect` 用来证明那个方框确实摆在声音小节抬头那一行的右端。
		"muted": AudioManager.is_muted(),
		"mute_rect": _mute_box.get_global_rect() if _mute_box != null else Rect2(),
	}


func _rect_of(nm: String) -> Rect2:
	if _page == null:
		return Rect2()
	var n := _page.find_child(nm, true, false)
	if n is Control:
		return (n as Control).get_global_rect()
	return Rect2()


## 某路总线在 AudioServer 里的实际 dB —— 用来证明「滑条真的进了引擎」，
## 而不是只改了一个本地数字。总线名大小写敏感，映射表取自 `AudioManager.MIX_BUSES`（单一出处）。
func _server_db(key: String) -> float:
	for nm in AudioManager.MIX_BUSES:
		var n := String(nm)
		if n.to_lower() == key.to_lower():
			var idx := AudioServer.get_bus_index(n)
			return AudioServer.get_bus_volume_db(idx) if idx >= 0 else -999.0
	return -999.0


## 设置内容真正占到的下缘（用来量「纸页还剩多少」）。
func content_bottom() -> float:
	var foot: Rect2 = _row_rects.get("foot", Rect2())
	return foot.position.y + foot.size.y


## 页脚的按钮（探针要量「五颗都在、右对齐到内容右缘 1484」）。按显示顺序。
func foot_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for i in FOOT_TEXTS.size():
		var b := _content.get_node_or_null("Foot%d" % i)
		if b is Button:
			out.append(b as Button)
	return out
