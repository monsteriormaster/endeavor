extends Node2D

## 常驻主 UI：顶栏（作弊 / 金钱 / 时间 / 贵族等级 / 设置）+ 右下「下一天」；单击手牌人物卡呼出人物面板。
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
const NEWSPAPER_POPUP_PATH := "res://components/newspaper.tscn"
const NEWSPAPER_HINTS_PATH := "res://resoures/plot/newspaper/hints.json"
const NEWSPAPER_HINT_PLOT := "报纸未订阅"
## 教程第一段（学校）场景 —— 「下一天」拦截只在这里生效，见 `_in_tutorial_first_scene()`。
const TUTORIAL_FIRST_SCENE := "res://scene/tutorial_1.tscn"

## 每日生活开销（2026-10-23 用户拍板）：**教程结束之后**，每过一天扣 5。
## 经济节奏：开局 5 → 教程结束 +45 = 50 → 每天 −5（只够撑 10 天，逼玩家去赚钱）。
## ⚠️ 教程期间**不扣**：教程里唯一一次真过天是「第 1 天已回家」放行的那次脚本化过场
##    （学校 → 家业），不算自由过天。若那时也扣，初始 5 直接变负、教程后凑不出 50。
## 判据用 `TutorialManager.is_completed()`（看存档里的 `tutorial_progress`），不看门控 tag。
const DAILY_LIVING_COST := 5

## 破产结局（2026-10-23 用户拍板）：「钱扣到负数 → 达成破产结局，成就『恭喜你破产了』，
## 出结算页（中间四个字：恭喜你破产了），再点一次回主菜单」。
##
## 与通关结算页（`scene/ending.tscn` / D-END2）**共用同一屏**，只换文案与解锁的成就 id ——
## 用户口径是「出现游戏结束」，这一屏的语义就是它，没有第二套页面。
## ⚠️ 这里**不再夹 0**：旧实现 `maxi(0, money - 10)` 会让玩家永远看不到「扣到负数」，
##    也就永远触发不了这个结局。夹底改为破产后的**清零清算**（见 `_trigger_bankruptcy`）。
const BANKRUPT_ACH := "恭喜你破产了"
const BANKRUPT_TEXT := "恭喜你破产了"
const ENDING_SCENE := "res://scene/ending.tscn"

## 「下一天」按钮锁定开关。由 TutorialManager.unlock_next_day() 置回 false（教程收尾兜底）。
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
@onready var _next_day_button: Button = $next_day
@onready var _card_area: CardArea = $CardArea
## 右上角「进行中行动」面板（ActionPanel 实例）。由「事件列表」按钮开关其显隐。
@onready var _action_panel: ActionPanel = $ActionPanel


## 暴露主 UI 卡牌区，供购书/触发器等把结算得到的卡（book_acquired / cards_returned）塞进来。
func get_card_area() -> CardArea:
	return _card_area


# ============================================================
#  给二级图标提示面板用的「界面禁入区」
# ============================================================

## 常驻主 UI 里**有实底**的那几块控件的屏幕矩形。
##
## 给谁用：主城二级图标（`components/scene_spot.gd`）的悬浮提示面板。那块提示是
## 「写在纸上的墨」—— **没有底、没有框**（M-ANI1 v4）。所以它一旦落在这几块控件上，
## 墨字就压在深色面板上，直接读不出来；反过来若面板画在下面，就是被盖掉。两条都不能要。
##
## 只报**真的挡得住**的三块：顶栏纸 / 「进行中行动」板 / 手牌卡槽。
## 矩形一律从 .tscn 的 offset_* 实读（不在这里写死数字）—— 布局改了这一份就自动跟着变，
## 否则以后谁把卡槽挪个位置，提示就会重新钻进去，而且不会有任何报错。
##
## ⚠️ `ActionPanel` 的根节点是**锚定全屏的壳**（`offset_right/bottom` 会被算到屏幕外），
## 真正有底的是它的 `Panel` 子节点。要报的是后者。
## ⚠️ `next_day`（下一天）不再单列：它在 CardArea 的矩形里面，报卡槽就一起管住了。
func panel_forbidden_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	_add_forbidden(out, get_node_or_null("TopBarPaper"))
	_add_forbidden(out, get_node_or_null("ActionPanel/Panel"))
	_add_forbidden(out, get_node_or_null("CardArea"))
	return out


func _add_forbidden(out: Array[Rect2], n: Node) -> void:
	if n == null:
		return
	var c := n as Control
	if c == null or not c.is_visible_in_tree():
		return
	var r := c.get_global_rect()
	if r.size.x > 0.0 and r.size.y > 0.0:
		out.append(r)


func _ready() -> void:
	ensure_hero_card()
	# D-HAND3：其余 npc 条目同样补齐静态外观字段（老档/部分剧情路径建的条目缺 image/gender，
	# 会让角色卡切场景后专属立绘掉成通用剪影）。必须在 `_restore_hand()` 之前跑。
	ensure_npc_static_fields()
	# D-UI1：事件驱动替代 _process 轮询
	if not Player.stats_changed.is_connected(_on_stats_changed):
		Player.stats_changed.connect(_on_stats_changed)
	data_upgrade()
	_refresh_next_day_button()
	# 把卡牌区交给触发器子系统，使其结算后能经 cards_returned / book_acquired 归还卡牌。
	TriggerManager.register_card_area(_card_area)
	# 手牌卡点击 → 播该 NPC 的「引导对话」（新手教程「点管家卡」）
	_card_area.card_clicked.connect(_on_card_clicked)
	# 切场景后 CardArea 重建，按进度把该在手牌的卡加回（新手教程 Hero/Sicourge）
	_restore_hand()


## 手牌重建：CardArea 是场景内节点，切场景即销毁，由本函数按持久账本把它重建出来。
##
## D-HAND1（2026-10-14）之前的写法：在这里写死三条「按进度补卡」规则（主角 / 管家 / 孩子），
## 于是只有这三张能回来，**其余一切卡**——买的书、打听来的秘氛困惑博学、杂货店买的货、
## 剧情 add_to_hand 给的任何人物卡——都在切场景时静默蒸发。现在「玩家手上有什么」是
## `Player.hand` 的真值（每次增删都由 CardArea 同步进去），这里只负责把账本兑现成卡。
##
## 代价：这里不再「重放」任何规则。好处是账本不会复活已被消耗掉的卡（旧规则每次进主 UI
## 都把 Hero 塞回去，即便它正躺在某个卡槽里执行任务）。
func _restore_hand() -> void:
	# 老存档没有 hand 字段。SaveLoader.apply_save_data 已迁移过一次；这里是给「未经读档」
	# 的路径（例如中途热更新进来的进程）兜同样的底。hand 非空时它自己会立刻返回。
	Player.migrate_hand_from_progress()
	var entries: Array = Player.hand
	var cards: Array[CardData] = []
	var dead: Array = []
	for i in entries.size():
		var card := EffectProcessor.resolve_hand_entry(entries[i])
		if card == null:
			# 兑现不出来 = 这张卡的来源数据已经没了（JSON 里删掉的角色 / 失效物品）。
			# 留着只会每次进场景都重试一次，直接注销。
			dead.append(i)
			continue
		cards.append(card)
	if not cards.is_empty():
		_card_area.restore_from(cards)
	if not dead.is_empty():
		Player.drop_hand_entries(dead)


func _on_stats_changed() -> void:
	data_upgrade()


## 单击手牌卡：人物卡 → 打开该角色人物面板（character_panel）；
## 道具卡 → 打开卡牌详情（CardDetailPopup）。
## 新手教程「点管家卡」例外：该 NPC 挂了 talk_hint 时优先播引导对话（只一次）。
func _on_card_clicked(card: CardData) -> void:
	if card == null:
		return
	if card.card_type == "character":
		var npc_key := EffectProcessor._npc_key_of(card)
		var entry: Dictionary = Player.npc.get(npc_key, {})
		var hint: Variant = entry.get("talk_hint", null)
		if hint is Dictionary:
			entry.erase("talk_hint")  # 只播一次
			var p: Dictionary = hint
			var pp := String(p.get("path", ""))
			var pn := String(p.get("name", ""))
			if pp != "" and pn != "":
				PlotImporter.add_plot(pp, pn)
				return
			# hint 数据异常（path/name 为空）时，不应静默吞掉点击 → 落到下方打开人物面板
		_open_character_panel(card)
	else:
		CardDetailPopup.open(card)


# ============================================================
#  顶栏数据
# ============================================================

## 刷新顶栏所有文本。可被外部安全地重复调用。
##
## 货币口径（2026-10-14 拍板）：**无单位**，直接显示 `Player.player_money` 的裸值。
## 旧写法在数字后拼了一个「万」字，与内容侧的实际量级（个位到几十）对不上，
## 玩家会以为顶栏那个数比实际大一万倍。不同货币之间的解释交给经济系统，这里不加后缀。
func data_upgrade() -> void:
	if not is_node_ready():
		return
	_money_label.text = "金钱：" + str(Player.player_money)
	_noble_label.text = "贵族等级：" + Player.player_nobility_title() + "（" + str(Player.nobility) + "）"
	_time_label.text = "时间：第" + str(Player.time) + "天"


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


## D-HAND3（2026-10-23）：给 `Player.npc` 所有条目补齐**静态外观字段**。
##
## 为什么需要（探针 `debug/_hand_face_probe` 抓的现场）：手牌角色卡在切场景 / 读档后由
## `main_ui._restore_hand()` → `EffectProcessor.live_card_for_id` 按 `Player.npc` 条目**实时重建**，
## 而 `CardData.from_character` 只拷条目里有的字段。老档或部分剧情路径建的条目只带玩法字段
## （name / attrs / tags / equipment），缺 `image` / `gender` / `description` —— 于是：
##   · 立绘：`CardChip.resolve_icon_path` 查不到条目 image，按 gender 回落 —— gender 也缺
##     → 一律掉成 man.png 通用剪影（专属立绘「消失」，同一张卡前后长得不一样）；
##   · 描述：详情弹窗清空。
## 玩家看到的就是「切个场景，卡的内容变了」。
##
## 范式与 `ensure_hero_card()` 相同（D-UI3 已拍板）：**只补预设里有、条目里缺的字段**，
## 且只碰静态外观三件套（image / gender / description）。name / attrs / tags / equipment /
## num_tags / talk_queue 等玩法字段**一概不碰** —— 那些是运行时真值，补了会覆盖改名窗的
## 改名、学校送学的成长与剧情写入的 tag。
##
## ⚠️ 必须排在 `_restore_hand()` 之前：手牌重建读的就是这些条目。
## ⚠️ 键不在 characters.json（剧情自建角色 / 中文键别名）是正常情况 → 走 `preset_npc_quiet`
##    （不告警、不降级空壳），返回空字典就跳过。
func ensure_npc_static_fields() -> void:
	for key in Player.npc:
		var entry: Variant = Player.npc[key]
		if not (entry is Dictionary):
			continue
		if String(key) == hero:
			continue  # 主角由 ensure_hero_card() 负责（走模板 + hero_merge，字段口径不同）
		var e := entry as Dictionary
		var preset := EffectProcessor.preset_npc_quiet(String(key))
		if preset.is_empty():
			continue
		for field in ["image", "gender", "description"]:
			if not e.has(field) and preset.has(field):
				e[field] = preset[field]


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

## 作弊按钮 → 呼出 QuickBug 调试面板（非模态；自由添加卡片 / 改任意角色 tags·数值·num_tags）。
func _on_cheat_pressed() -> void:
	QuickBug.open()


## 打开人物面板（单击手牌人物卡）。npc 条目不存在时先从 characters.json 加载预设，
## 并补齐 character_panel 依赖的 equipment / tags 字段，避免 KeyError。
func _open_character_panel(card: CardData) -> void:
	var npc_key := EffectProcessor._npc_key_of(card)
	if not Player.npc.has(npc_key):
		Player.npc[npc_key] = EffectProcessor._load_preset_npc(npc_key)
	var entry: Dictionary = Player.npc[npc_key]
	if not entry.has("equipment"):
		entry["equipment"] = {}
	if not entry.has("tags"):
		entry["tags"] = []
	var scene: PackedScene = load(CHARACTER_PANNEL_PATH)
	if scene == null:
		push_error("Main_ui: 找不到人物面板场景 %s" % CHARACTER_PANNEL_PATH)
		return
	var panel: Node = scene.instantiate()
	# 「点外收起时点到的是不是同一张卡」靠这条 meta 判（见 OverlayRoot.close_with_click_through）：
	# 点自己刚打开的那张卡 = 只收起，不重开。
	panel.set_meta("card_panel_key", npc_key)
	# 对齐 TriggerManager.open_trigger：deferred 入栈 + setup。避免在卡牌 _gui_input
	# 回调栈内同步 add_child Window（PopupPanel）到 root 干扰输入分发。
	#
	# `exclusive: false` + `outside_click_closes: true` 是**行为契约**（2026-10-23 用户拍板）：
	# 点面板外 → 面板收起；若点的是另一张手牌 → 关掉本面板并直接打开那张卡的详情。
	# exclusive 必须为 false：嵌入子窗口独占时会把窗口外的点击整个吞掉，拦截层收不到
	# ⇒「点外收起」根本不会触发（探针 `_card_panel_click_probe` 已实证）。
	OverlayRoot.push_overlay.call_deferred(panel, {
		"modal": true,
		"esc_closes": true,
		"exclusive": false,
		"outside_click_closes": true,
		"close_method": "close_panel",
	})
	panel.setup.call_deferred(npc_key)


## 设置按钮 → 设置菜单（D-UI4）
func _on_setting_pressed() -> void:
	var scene: PackedScene = load(SETTINGS_MENU_PATH)
	if scene == null:
		push_error("Main_ui: 找不到设置菜单场景 %s" % SETTINGS_MENU_PATH)
		return
	var menu: Node = scene.instantiate()
	# ⚠️ `esc_closes: false, persist: true` 是**契约**，别改回 true：
	#    · esc_closes:true ⇒ `OverlayRoot.close_top()` 在 `close_menu()` 之后会兜底
	#      `close_overlay` ⇒ 立刻 queue_free ⇒ 0.5s 翻页死在第 0 帧（Esc 由本组件自己接）。
	#    · persist:true ⇒ 点「返回主菜单」时会 `change_scene_to_file(loading.tscn)`，
	#      没有 persist 的话 `_on_scene_changed` 会在那一刻把它清掉，翻页演不完。
	OverlayRoot.push_overlay(menu, {
		"modal": true,
		"esc_closes": false,
		"persist": true,
	})


## 「下一天」：推进回合。
##
## D-UI7：过天不再 save_game() + load_game() 整场景重载。
## 整场景重载会让所有场景内状态（已显隐的角色、已打开的面板、已消耗的触发点）回滚，
## 而且每天多做一次磁盘读 + 场景重建。现在只推进数据、存档并广播。
##
## 过天**不再负责换幕**（2026-10-23）：原实现在末尾按 `Player.path` 判断「本回合预约了新场景」
## 就 change_scene。但 `Player.path` 同时是**回档锚点**（`tutorial_1.gd::_ready` 会无条件写它），
## 一旦它停留在上一幕（如 tutorial_1），玩家在家业里点「下一天」就会被切回学校 —— 探针
## `debug/_tut_nextday_repro.gd` 的 ② 已实证。真正的换幕点都在各自的写入方：
## `ActionQueue._land`（异步结算 goto_scene）、`TriggerManager.execute_pending_goto_scene`、
## `SceneSpot._go_to_scene` —— 它们写完 `Player.path` 立刻自己切，无需过天再补一次。
func _on_next_day_pressed() -> void:
	# D-UI2 配套：教学锁定期间即使按钮 disabled 被外部改动，逻辑层也不放行
	if is_next_day_locked:
		return

	# 新手教程拦截（2026-10-23 用户拍板）：**教程期间「下一天」一律拦住并给文本**。
	# 唯一放行的是「第 1 天已执行『回家』」这一次 —— 那是脚本化过场（学校 → 家业），
	# 不是自由过天；不放行玩家就永远进不了家业。
	# 文本按进度分三档，让提示对得上玩家此刻该做的事（同一句反复出现最招人烦）：
	#   ① 还没执行「回家」（第 1 天在学校）→「我还不想那么早休息」
	#   ② 已回家、还没和管家说话          →「先去和管家说说话」
	#   ③ 已和管家说完、还没点家业         →「该把家里的事理一理了」（点完家业教程即结束）
	# 教程完成（摘「进行新手教程」）或持有「家业已执行」→ 拦截整体失效。
	if Player.player_has_tags([TutorialManager.TUTORIAL_GATE_TAG]) \
			and not Player.player_has_tags([TutorialManager.TUTORIAL_DONE_TAG]) \
			and not Player.player_has_tags(["家业已执行"]):
		var hint := ""
		if not Player.player_has_tags(["想回家了"]):
			hint = "我还不想那么早休息"
		elif _in_tutorial_first_scene():
			hint = ""  # 学校的脚本化过场：放行，不切「教程不能过天」这条路
		elif Player.player_has_tags(["斯库奇引导1"]):
			hint = "该把家里的事理一理了"
		else:
			hint = "先去和管家说说话"
		if hint != "":
			print("[Main_ui] 教程拦截「下一天」→ 播「%s」（scene=%s path=%s tags=%s）" % [
				hint, _current_scene_path(), str(Player.path), str(Player.player_tags)])
			PlotImporter.add_plot("res://resoures/plot/misson/beginning.json", hint)
			return

	# 过天音已移除（2026-10-14）：原在此处播 `ui_next_day`（设计圣经 §3.6：机械上弦 + 铜徽章扣合，
	# 全工程唯一「郑重」的 UI 音），现改为静默过天。`ui_next_day` 素材与 `audio_manager.gd` 注册表条目
	# 保留，需要时可在此处一行接回（注意仍要放在上面的拦截 `return` 之后）。
	Player.time += 1
	# M-SUN1 v2：太阳约 1 秒滑过剩余白天 + 整个夜，停回次日清晨（影子与地图色温跟着走）。
	SunClock.fast_forward_to_dawn()
	_apply_daily_living_cost()
	_apply_daily_newspaper_cost()
	# 破产（2026-10-23）：钱被扣到负数 → 直接进结算页，本回合后面的事（存档 / 广播 /
	# 报纸）都不做了 —— 玩家已经没有下一个回合。判定放在两条扣费之后、存档之前，
	# 这样「订阅报纸 −1」把最后一点钱扣穿也算破产。
	if Player.player_money < 0:
		_trigger_bankruptcy()
		return
	SaveLoader.save_game()
	EventSignal.day_changed.emit(Player.time)
	_spawn_daily_newspaper()


## 当前场景是不是**教程第一段**（学校 / tutorial_1）。
##
## 「下一天」拦截只在这里生效 —— 家业与之后的任何场景都不该再弹「我还不想那么早休息」。
## 判据两路，缺一不可：
##   ① `current_scene.scene_file_path` 命中 tutorial_1（真机路径）；
##   ② 树里有名为 `Tutorial1` 的节点（探针把 tutorial_1 实例 add_child 到自己的场景下，
##      此时 current_scene 是探针、file_path 对不上，但实例节点名仍是 tutorial_1.tscn 的根名）。
## 只认 file_path 会让 `debug/tutorial_e2e_check.gd` 那类"内嵌场景"探针的拦截断言假红。
func _in_tutorial_first_scene() -> bool:
	var cur: Node = get_tree().current_scene
	if cur == null:
		return false
	if _current_scene_path() == TUTORIAL_FIRST_SCENE:
		return true
	return cur.get_node_or_null("Tutorial1") != null


## current_scene 的场景路径（空场景 / 尚未换幕时返回空串，绝不抛）。
func _current_scene_path() -> String:
	var cur: Node = get_tree().current_scene
	return String(cur.scene_file_path) if cur != null else ""


## 「报纸」按钮 → 订阅者回看当天报纸；第 1 天回看教程发的那份；其余情况弹提示去订阅。
##
## 门控口径（2026-10-14 教程首份报纸 GDD）：**从第二天开始才需要购买报纸**。
## 第 1 天那份是教程剧情播完后发给玩家的（`EffectProcessor._grant_newspaper` 已写进
## `Player.daily_newspaper`），因此第 1 天不需要「订阅报纸」也能回看；第 2 天起没订阅就是
## 没有当天的报纸，弹提示让玩家去商业街报亭买。
func _on_newspaper_pressed() -> void:
	if not Player.player_has_tags(["订阅报纸"]) and not _has_free_first_paper():
		PlotImporter.add_plot(NEWSPAPER_HINTS_PATH, NEWSPAPER_HINT_PLOT)
		return
	var paper: Dictionary = Player.daily_newspaper
	if paper.is_empty():
		# 兜底：老档有订阅 tag 但无快照（或第 1 天未过天），用固定日刊补
		paper = NewspaperGenerator.generate_fixed(Player.time)
	_show_newspaper(paper)


## 免订阅可回看 = 教程送的那份首期报纸（`Player.time` 还是第 1 天且手里有快照）。
## `daily_newspaper` 为空说明玩家还没拿到（剧情没播到），同样走提示去订阅。
func _has_free_first_paper() -> bool:
	return int(Player.time) <= 1 and not Player.daily_newspaper.is_empty()


## 每日生活开销（2026-10-23 用户拍板）：教程结束后每过一天扣 5。
## 在过天推进、存档之前扣除，确保扣费随存档落盘（读档不丢）。
## ⚠️ 2026-10-23 起**不再夹 0**：允许扣成负数，负数就是破产结局的触发条件
##    （见 `_on_next_day_pressed` 末尾与 `_trigger_bankruptcy`）。
##    旧口径「不允许负值 / 负债不在 demo 范围」（《经济系统策划案》§2 / §3.2 / Q-Eco2）
##    已被这条新拍板覆盖：负值本身也不落盘，破产时立刻清算归零。
func _apply_daily_living_cost() -> void:
	if not TutorialManager.is_completed():
		return
	Player.player_money -= DAILY_LIVING_COST


## 破产：存档 → 清覆盖层 → 进与通关共用的结算页，文案与成就换成破产那套。
##
## 顺序与 `TriggerManager._perform_game_ending()` 同构（存档 → clear_all → 换场）。
##
## **清算归零**：判定已经做完（`money < 0` 这一事实已经用掉了），落盘前把负值清成 0 ——
## 存档里不留负数。代价是档案里看不出「欠了多少」，但这一局的结局已经播过了，
## 留负数只是脏数据（而且会让读档后的下一回合立刻再破产一次）。
##
## ⚠️ **不写 `Player.path`**：它是回档锚点，玩家从标题点「继续游戏」就是按它回去的。
##    若指向结算页，就成了「继续 → 结局页 → 回标题 → 继续 → 结局页」的闭环；
##    留给最后的自由场景（家 / 主城），玩家还能接着玩 —— 这与通关那边的口径一致
##    （`_perform_game_ending` 也不改 path，所以通关后继续游戏会回到第 20 天）。
func _trigger_bankruptcy() -> void:
	print("[Main_ui] 破产：第 %d 天金钱 %d < 0 → 结算页「%s」" % [Player.time, Player.player_money, BANKRUPT_TEXT])
	Player.player_money = 0
	SaveLoader.save_game()
	OverlayRoot.clear_all()
	EndingPage.enter_with(BANKRUPT_TEXT, BANKRUPT_ACH)
	SceneTransition.change_scene(ENDING_SCENE)


## 订阅报纸的每日成本（付费订阅 GDD，2026-09-08）：持有「订阅报纸」tag 时，每天（回合）消耗金钱 1。
## 在过天推进、存档之前扣除，确保扣费随存档落盘（读档不丢）。
func _apply_daily_newspaper_cost() -> void:
	if Player.player_has_tags(["订阅报纸"]):
		Player.player_money -= 1


## 过天生成当天报纸（报纸日刊 GDD）：先存快照；有「订阅报纸」tag → 直接跳脸弹窗；否则存入收藏。
func _spawn_daily_newspaper() -> void:
	# 首份日报发行即授予「报纸推出」（幂等）：剧院支线「与经理交涉」以它为 show_when 门控。
	if not Player.player_has_tags(["报纸推出"]):
		Player.grant_tag("报纸推出")
	var paper: Dictionary = NewspaperGenerator.generate(Player.time)
	Player.daily_newspaper = paper
	if Player.player_has_tags(["订阅报纸"]):
		_show_newspaper(paper)
	else:
		# 非订阅：存入收藏（type:newspaper）。回看入口（主 UI「报纸收藏」）后续再做。
		Player.player_stuff.append({
			"type": "newspaper",
			"id": "daily_%d" % Player.time,
			"title": paper.get("title", ""),
			"date": paper.get("date", ""),
			"columns": paper.get("columns", []),
		})


## 弹当天报纸弹窗（模态 + persist，供过场跳脸与按钮回看共用）。
func _show_newspaper(paper: Dictionary) -> void:
	var popup_scene: PackedScene = load(NEWSPAPER_POPUP_PATH)
	if popup_scene == null:
		push_error("Main_ui: 找不到报纸场景 %s" % NEWSPAPER_POPUP_PATH)
		return
	var popup: Variant = popup_scene.instantiate()
	OverlayRoot.push_overlay(popup, {
		"modal": true,
		"esc_closes": true,
		"close_method": "close",
		"persist": true,
	})
	popup.show_newspaper(paper)


## 【已删除】`_goto_scheduled_scene_if_needed()`（2026-10-23）。
##
## 它做过的事：过天末尾比较 `Player.path` 与 `current_scene.scene_file_path`，不等就 change_scene
## 并补发 `scene_entered`。设计假设是「Player.path = 本回合预约的下一幕」。
##
## 为什么必须删：`Player.path` 同时是**回档锚点**，而教程第一段的 `_ready` 会无条件把它写成
## `res://scene/tutorial_1.tscn`。于是只要它停留在上一幕，玩家在家业里点一次「下一天」就会被
## **切回学校**，此后每次点下一天都在学校被教程门控拦住、反复弹「我还不想那么早休息」。
## 探针 `debug/_tut_nextday_repro.gd` 的 ② 复现了这个误切。
##
## 换幕本来就不缺这一步：`ActionQueue._land`（异步结算 goto_scene）、
## `TriggerManager.execute_pending_goto_scene`、`SceneSpot._go_to_scene` 都是**写完 `Player.path`
## 立刻自己切场景 + 发 `scene_entered`**。没有任何流程依赖过天时补切。
##
## 「事件列表」按钮（报纸按钮正下方）：开关右上角 ActionPanel（进行中行动 / 事件情况列表）的显隐。
## 默认隐藏；点一下出现、再点一下消失。按钮本身用 toggle_mode，按下态（ButtonSkin 的 pressed 纸样）
## 即「已展开」的视觉指示，符合『指示明显且统一』的美化要求。
func _on_event_list_pressed(on: bool) -> void:
	if _action_panel != null:
		_action_panel.visible = on


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
