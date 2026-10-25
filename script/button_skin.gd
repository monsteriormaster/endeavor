extends Node
## 全局按钮皮肤 —— 「全工程所有按钮都从同一套素材里选」的唯一落地点。
##
## ▍为什么要一个 Autoload（而不是逐个改 .tscn）：
##   用户口径：「之后所有的按钮都要按我们做的这些里选」。逐个改 .tscn 是死路 ——
##   工程里已有 42 个 Button 节点散在 17 个场景，**将来新增一个就漏一个**。
##   这里挂在 `SceneTree.node_added` 上：任何 Button 一进场景树就被套上皮，
##   写新界面时不需要记得做任何事。这就是「按钮库」的执行机构。
##
## ▍皮 = 两档九宫格贴图（`art/ui/btn_paper_l.png` / `btn_paper_s.png`）：
##   · 大档 200x60，caps 40/16 → 能服务的最短边 = 32px（覆盖 44 / 48 / 52 / 99 的弹窗与标题按钮）
##   · 小档 104x36，caps 10/8  → 最小短边 20px（专治手牌筛选 84x28、建角加减 40x41）
##   —— 九宫格硬约束：`caps >= 最内层装饰的「内缩 + 圆角半径」`，于是
##      **一张贴图能服务的最短边 = 2 x caps**。84x28 在大档下 28 < 32，数学上无解，只能另出一张。
##
## ▍四态靠 StyleBoxTexture.modulate_color 调色，**不烤四份素材**。
##   ⚠️ 绝不能用 `Control.modulate` —— 那会把按钮上的文字一起染色（对话面板踩过这个坑）。
##
## ▍动效由子节点 `PaperButtonFX` 提供 —— **不动按钮自己的脚本**（原因见该文件头）。
##
## ▍两条**自动**不碰的规则（比 meta 逃生口常用得多）：
##   ① `OptionButton`（下拉框）—— 是 Button 的子类但不是按钮，箭头会浮在纸中间。
##   ② **自绘控件** —— 见 `_self_drawn()`。工程里现存三种，都是「拿 Button 当点击热区」：
##        · `scene_spot.tscn`   地图节点（180x180）—— `normal` 槽显式设成空样式
##        · `character.tscn`    地图人物卡（200×353.33）—— `_ready()` 里把五槽清成 StyleBoxEmpty，
##                              卡面由内嵌的 `card_chip` 实例承担（2026-10-16 改版）
##        · `trigger_spot.tscn` 触发器热区       —— 在 `_ready()` 里自绘
##      判定放在**按钮自己 `_ready()` 之后**：`node_added` 早于 `_ready`，
##      抢在自绘之前套皮不但会被随后的 override 顶掉，还白留一圈铅笔动效。
##      ⚠️ 这正是 2026-10-06 实测抓到的回归：主城 10 个地图节点一度全被套上纸片背景。
##      ⚠️ **不能**简单按「有没有 override」判 —— `achievement_list.CloseButton`
##         （`ach_tag_plate.tres`）与 `character_panel.closebutton`（`SB_btn_*`）
##         都把自己的旧皮肤写在 .tscn 里，那正是本次要**替换**的目标，豁免掉就漏了。
##
## ▍逃生口：节点上打 `meta(&"btn_skin_skip", true)` 的按钮完全不被碰
##   （留给「外观另有语义但又不自绘」的按钮；目前全工程没有用户）。

## 贴图与九宫格边块。改素材必须同步改这两组常量。
const TEX_L: Texture2D = preload("res://art/ui/btn_paper_l.png")
const TEX_S: Texture2D = preload("res://art/ui/btn_paper_s.png")
const CAP_L := Vector2(40.0, 16.0)
const CAP_S := Vector2(10.0, 8.0)
## 文字内边距（**不是** texture margin）。必须明显小于 caps，
## 否则 content_margin 会把按钮的 minimum_size 顶大 —— 88x44 的「执行」会被撑成 112 宽。
const PAD_L := Vector2(24.0, 8.0)
const PAD_S := Vector2(8.0, 4.0)
## 短边小于这个值就改用小档。大档的下限是 2x16 = 32，留 4px 余量。
const SMALL_MAX: float = 36.0

## 四态的调色（乘在贴图上）。悬浮微亮 / 按下压暗 / 禁用发灰。
const TINT_NORMAL := Color(1.00, 1.00, 1.00)
const TINT_HOVER := Color(1.05, 1.04, 1.00)
const TINT_PRESSED := Color(0.86, 0.78, 0.66)
const TINT_DISABLED := Color(0.82, 0.81, 0.78)

const FX_SCRIPT: GDScript = preload("res://script/paper_button_fx.gd")

## ── 点击音（`design/音频设计圣经.md` §3.6）──
## 全工程按钮的点击音也从这里统一挂，理由同上：逐个改 .tscn 必漏。
##
## 「主 / 次」按钮不是引擎概念，设计圣经却分了两档音色（primary「笃」/ secondary「哑喀」）。
## 判据按**可解释性**排序：
##   ① 节点上显式声明 `meta(&"btn_click_sfx", "ui_click_secondary")` → 直接用（最可靠）
##   ② 名字或文字命中 `SECONDARY_HINTS`（关闭 / 取消 / 返回 …）→ 判为次要
##   ③ 其余 → 主按钮音
## ⚠️ 启发式只影响**音色选择**，不影响任何功能行为；判错也只是「关闭」响了「笃」，
##    所以这里可以容忍模糊，不需要给每个按钮强制打标。
const META_CLICK_HOOKED := &"_btn_click_hooked"
const META_CLICK_SFX := &"btn_click_sfx"
const SECONDARY_HINTS := ["close", "cancel", "back", "skip", "quit", "exit",
	"关闭", "取消", "返回", "跳过", "退出", "放弃"]

const META_WATCH := &"_btn_skin_watch"
const META_SMALL := &"_btn_skin_small"
const META_SKINNED := &"_btn_skin_done"
## 入树那一刻，这个 Button 的 `normal` 槽**是否已被场景声明**。
## 用来区分「旧皮肤写在 .tscn 里」（要替换）与「控件在 `_ready()` 里自绘」（不碰）。
const META_HAD_NORMAL := &"_btn_skin_had_normal"
const SKIP_KEY := &"btn_skin_skip"

var _empty: StyleBoxEmpty = null


func _ready() -> void:
	# `node_added` 覆盖之后才进树的一切；`_sweep` 兜底「在本 Autoload `_ready()` 之前
	# 就已经在树里」的那些（Autoload 按 `project.godot` 顺序就绪，早于主场景）。
	get_tree().node_added.connect(_on_node_added)
	_sweep(get_tree().root)


## `OptionButton`（下拉框）必须排除 —— 它是 `Button` 的子类，但「下拉框」不是「按钮」，
## 套上纸片只会让它的下拉箭头浮在一块纸中间。
## `CheckBox` / `CheckButton` 则**保留**（勾选钮本来就该是纸上一个小方块，
## 建角页那 14 条天赋正是这个形态）。
func _wants_skin(node: Node) -> bool:
	return node is Button and not (node is OptionButton)


func _on_node_added(node: Node) -> void:
	if _wants_skin(node):
		_watch(node as Button)


## 覆盖式扫描（开局兜底）：Autoload 之前的场景树内容不会触发 node_added。
func _sweep(n: Node) -> void:
	if _wants_skin(n):
		_watch(n as Button)
	for c in n.get_children():
		_sweep(c)


func _watch(btn: Button) -> void:
	if not is_instance_valid(btn) or btn.has_meta(META_WATCH):
		return
	btn.set_meta(META_WATCH, true)
	_hook_click_sfx(btn)
	# 先记一笔：此刻只有**场景声明**的 override 存在，脚本的 `_ready()` 还没跑。
	# 之后拿它和「就绪后」的状态一比，就知道样式是场景给的（要替换）还是控件自绘的（不碰）。
	btn.set_meta(META_HAD_NORMAL, btn.has_theme_stylebox_override("normal"))
	# 尺寸是**布局之后**才定的，而入树那一刻往往是 0 → 必须跟着 resized 重新判档。
	if not btn.resized.is_connected(_on_btn_resized):
		btn.resized.connect(_on_btn_resized.bind(btn))
	# ⚠️ `node_added` 早于该节点的 `_ready()`。自绘控件是在自己的 `_ready()` 里上样的 ——
	# 抢在它之前套皮会被随后 override 顶掉，还白留一圈铅笔动效。所以推迟到就绪之后。
	if btn.is_node_ready():
		_refresh(btn)                            # 早已就绪（_sweep 兜底路径）
	else:
		btn.ready.connect(_refresh.bind(btn), CONNECT_ONE_SHOT)


## 挂点击音。⚠️ 必须在 `_watch`（入树一次性）里挂，**不能放进 `_skin`** ——
## `_skin` 会随 `resized` 反复执行，在那里连 `pressed` 会连出好几份，一次点击响 N 下。
func _hook_click_sfx(btn: Button) -> void:
	if btn.has_meta(META_CLICK_HOOKED):
		return
	btn.set_meta(META_CLICK_HOOKED, true)
	# ⚠️ 「拿 Button 当点击热区」的自绘控件（地图节点 / 卡牌 / 触发器热区）**不给统一点击音**：
	#    它们各自的语义音效已经盖住这次交互（地图节点 → 转场合幕、卡牌 → 拾起/落位），
	#    再叠一个「哒」会让一次点击响三下。判据**复用 `_self_drawn`**，不另造第二套。
	if _self_drawn(btn):
		return
	if btn.is_node_ready():
		_maybe_connect_click(btn)
	else:
		# `node_added` 早于 `_ready()`；「在自己的 `_ready()` 里自绘」的控件这一刻还看不出来。
		btn.ready.connect(_maybe_connect_click.bind(btn), CONNECT_ONE_SHOT)


func _maybe_connect_click(btn: Button) -> void:
	if not is_instance_valid(btn) or _self_drawn(btn):
		return
	if btn.pressed.is_connected(_on_btn_pressed):
		return
	btn.pressed.connect(_on_btn_pressed.bind(btn))


func _on_btn_pressed(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	var sfx := "ui_click_primary"
	if btn.has_meta(META_CLICK_SFX):
		sfx = String(btn.get_meta(META_CLICK_SFX))
	elif _is_secondary(btn):
		sfx = "ui_click_secondary"
	AudioManager.play_sfx(sfx)


func _is_secondary(btn: Button) -> bool:
	var s := (String(btn.name) + " " + btn.text).to_lower()
	for h in SECONDARY_HINTS:
		if s.contains(String(h).to_lower()):
			return true
	return false


func _on_btn_resized(btn: Button) -> void:
	if not is_instance_valid(btn) or not btn.is_node_ready():
		return                                   # 等 `ready` 里那次 _refresh
	_refresh(btn)


## 这个 Button 是「拿 Button 当点击热区的自绘控件」而不是按钮 → 一律不碰。
## 两条判据，合起来正好覆盖工程里现存的三种（卡牌 / 地图节点 / 触发器热区）：
##   ① `normal` 槽被显式设成**空样式** —— 它明说了「我不要底」。
##   ② 入树时还没有 `normal` override，就绪后却有了 —— 控件在自己的 `_ready()` 里自绘。
## ⚠️ 不能只按「有没有 override」判：`achievement_list` / `character_panel` 里
##    写在 .tscn 里的**旧皮肤**同样是 override，那正是本次要替换的目标。
func _self_drawn(btn: Button) -> bool:
	if not btn.has_theme_stylebox_override("normal"):
		return false
	if btn.get_theme_stylebox("normal") is StyleBoxEmpty:
		return true
	return not bool(btn.get_meta(META_HAD_NORMAL, false))


## 判档 + 套皮。**只在「跨档」时才重套**，免得每次 resized 都重造一遍 StyleBox。
func _refresh(btn: Button) -> void:
	if not is_instance_valid(btn):
		return
	if btn.has_meta(SKIP_KEY) and bool(btn.get_meta(SKIP_KEY)):
		return
	# 我们自己套过皮之后 `normal` 槽也是 override → 只在**没套过**时才做自绘判定，
	# 否则跨档重套会被自己的 override 挡下，永远停在第一档。
	if not btn.has_meta(META_SKINNED) and _self_drawn(btn):
		return
	var sz: Vector2 = btn.size
	if sz.x <= 0.0 or sz.y <= 0.0:
		return                                   # 还没布局，等 resized
	var small: bool = minf(sz.x, sz.y) < SMALL_MAX
	if btn.has_meta(META_SMALL) and bool(btn.get_meta(META_SMALL)) == small:
		return
	btn.set_meta(META_SMALL, small)
	_skin(btn, small)
	btn.set_meta(META_SKINNED, true)


func _skin(btn: Button, small: bool) -> void:
	var tex: Texture2D = TEX_S if small else TEX_L
	var cap: Vector2 = CAP_S if small else CAP_L
	var pad: Vector2 = PAD_S if small else PAD_L
	btn.add_theme_stylebox_override("normal", _sb(tex, cap, pad, TINT_NORMAL))
	btn.add_theme_stylebox_override("hover", _sb(tex, cap, pad, TINT_HOVER))
	btn.add_theme_stylebox_override("pressed", _sb(tex, cap, pad, TINT_PRESSED))
	btn.add_theme_stylebox_override("disabled", _sb(tex, cap, pad, TINT_DISABLED))
	# 键盘焦点框是引擎画的一个默认矩形，压在纸片上只会添乱 → 置空。
	# ⚠️ 只设一次：它不影响 minimum_size，重复设没有意义。
	if not btn.has_theme_stylebox_override("focus"):
		if _empty == null:
			_empty = StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("focus", _empty)
	_attach_fx(btn)


## 一张纸片 StyleBoxTexture。中间 TILE 而不是拉伸 —— 按钮横向要铺几百 px，
## 直接拉会把纸纹抹成横条。
func _sb(tex: Texture2D, cap: Vector2, pad: Vector2, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = cap.x
	sb.texture_margin_right = cap.x
	sb.texture_margin_top = cap.y
	sb.texture_margin_bottom = cap.y
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	sb.modulate_color = tint
	return sb


## 挂动效子节点。**不是 set_script** —— 那会顶掉按钮自己的脚本（静默失效）。
## 九宫格的细描边必须单独开 LINEAR：工程全局 default_texture_filter = NEAREST。
##
## 🔴 必须是 `Node2D.new()`，不能是 `Node.new()`：动效脚本 `extends Node2D`（原因见该文件头，
##    一句版 = 中间夹一层非 CanvasItem 会把 Button 的画布变换链打断，笔圈会画到屏幕左上角）；
##    而且「脚本继承自 Node2D」塞不进 `Node` 实例，会直接报错。
func _attach_fx(btn: Button) -> void:
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if btn.has_node("PaperButtonFX"):
		return
	var fx := Node2D.new()
	fx.name = "PaperButtonFX"
	fx.set_script(FX_SCRIPT)
	btn.add_child(fx)
