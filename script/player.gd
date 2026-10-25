"""
游戏内实时数据
所有人物都会以字典的形式存在npc里，为便于调试主角的数据单独列出来了
注意 在该文件添加修改的变量必须在 res://script/save_loader.gd 中做对应修改，确保存档系统正常

以下是一些辅助函数
player_attr_meet(att: String, compare: String, value: int)，用于比较pc的数值
npc_has_tags(npc: String, tags: Array, method := 1),用于判断npc是否满足标签，method1为all，0为any
player_has_tag(tags: Array, method := 1),用于判断pc是否满足标签，method1为all，0为any
"""


extends Node

## HUD 依赖的数值发生变化时广播（关闭缺陷 D-UI1：主 UI 不再靠 _process 每帧轮询刷新）。
## 触发源：time / player_money / player_bac / player_name 的 setter；
## 批量改数据（如读档）后请显式调用 notify_stats_changed()，避免遗漏。
signal stats_changed

## 贵族等级常量映射（D-NOB）：数值 1~5 -> 爵位名。
## 1 男爵 / 2 子爵 / 3 伯爵 / 4 侯爵 / 5 公爵。
const NOBILITY_RANKS := {
	1: "男爵",
	2: "子爵",
	3: "伯爵",
	4: "侯爵",
	5: "公爵",
}

## 裸属性**上限**（设计：5=正常人、10=人类极限；裸值封顶 10，tag/装备可继续叠生效值）。
## ⚠️ **只有上限、没有下限**（2026-10-06 用户拍板：**允许属性负值**）。
##    0 = 通常人类的下限，但**不是硬底** —— 意外跌到 0 以下在跑团语境里是可以解释的
##    （重伤 / 诅咒 / 天生缺陷），所以 `change_*` 一律**不许**加 `maxi(..., 0)`。
##    · 建角侧的直接后果：14 条天赋里 11 条带负值 attrs，只选「以力破巧」(bod −1) 不选
##      「平凡可贵」(clamp 3~7) 时，体魄就是 −1，预览与结算都照实显示 `→ −1`。
##    · 骰子侧已统一兜住：骰面一律 `max(1, 面数)`（`Player.roll_dice` / `CardData.weighted_x` /
##      `trigger_popup._roll_attr_die`），负属性退化成 `1d1`（只能掷出下限 1），**不会出 `1d-1`**。
##    · 唯一还会夹值的地方是**天赋自带的 clamp**（`EffectProcessor.clamp_attrs`，如「平凡可贵」3~7）。
const ATTR_MAX := 10

@export_group("curtain_scence")
@export var path = ''#当前路径
## 当前正在经历的**剧情位置**锚点（D-SV10）。格式与全工程 plot 键一致，多一个 index：
##   {"path": 剧情 JSON 资源路径, "name": 剧情名, "index": 当前句号, "ctx": 文本变量上下文}
## 空字典 = 当前不在任何剧情中。写入/清空由 PlotImporter 负责，index 由 DialogueUI 每句更新；
## 读档后由 PlotImporter.resume_plot_if_any() 据此续播到中断的那一句。
## ⚠️ 本字段原本是 String（恒为空、无人写入），2026-10-13 改为 Dictionary。
##    老档里的空串会被 SaveLoader._coerce 按默认值类型丢弃成 {}，属前向兼容，不升 SAVE_VERSION。
@export var plot = {}
@export var exact_situation = {}#该回合已经进行的操作 

@export_group("player")
@export var player_age :=16.0 
@export var time := 1:
	set(value):
		time = value
		stats_changed.emit()
#用于定义时间相关的事件
## 开局金钱（2026-10-23 用户拍板：**5**，不再是 100）。
## 与 `resoures` 无关，真正的三处口径必须同步：本默认值 / `save_loader.PERSISTENT_FIELDS`
## 的 `"player_money"` 默认值（新游戏走 `apply_save_data({})` 取的就是它）/
## `TutorialManager.complete_tutorial()` 的教程奖励 +45。
## 节奏：初始 5 → 教程结束 50 → 每天过回合 −5（`main_ui._apply_daily_living_cost`）。
@export var player_money = 5:
	set(value):
		player_money = value
		stats_changed.emit()
@export var player_app_fact =""
## 名字的「未填」状态**只有一种表示** = 空串。
## 历史默认值曾是一个占位串（见 NAME_PLACEHOLDER），旧存档里可能还留着它，
## 所以判定要两种都认，但**写入侧只允许空串** —— 两种未填状态并存是 bug 温床。
const NAME_PLACEHOLDER := "请输入你的名字"
## 留空时的兜底名。2026-10-06 由「主角」改为「维克多」（用户拍板）。
## ⚠️ 改名要一并处理 scene/selection.gd 的离开提醒：那边已经改成引用本常量，
##    所以这里改完即同步；不要在那句文案里重新写死名字。
const NAME_FALLBACK := "维克多"

## 主角在 `Player.npc` 字典里的键名。全工程唯一来源（selection.gd / main_ui.gd /
## card_chip.gd 都按它取主角条目）；别再各写一份字符串字面量。
const HERO_KEY := "Hero"

## 主角立绘的**保底**路径。正常路径 = `Player.npc[HERO_KEY]["image"]`
## （由 main_ui.ensure_hero_card 从 characters.json 的 Hero 模板填入）。
## ⚠️ 改主角立绘时以 characters.json 的 `Hero.image` 为准，这里只是模板尚未建立时的兜底；
##    两者指向同一张图（`art/hero.png`），改动要同步。
const HERO_IMAGE_FALLBACK := "res://art/hero.png"

## 主角卡的**静态身份词条**（与 characters.json 的 `Hero.tags` 三件套一致）。
##
## 🔴 为什么必须单独列出来（2026-10-24 修「孩子送不回去」）：`get_hero_card()` 的 tags 原先
##    只取 `player_tags`（成长/剧情词条要实时反映），于是 characters.json 里写的身份词条
##    一进手牌就被丢掉。而**卡牌情况**只认 tag 认人 —— 「归还孩子」的 `[["主角"]]`、
##    「调查大学图书馆·主角调查」的 `[["player"]]` 全都判不过，前者于是恒落
##    「手续必须你亲自办理」（lock_execute），玩家怎么放卡都送不回去。
##    识别主角的规范写法是 id `"Hero"`（any_slot.names），但 卡牌情况 表达不了 id，
##    所以这里把身份词条补回卡上，让两套判据都成立。
const HERO_IDENTITY_TAGS: Array[String] = ["player", "主角", "hero"]

@export var player_name = "":
	set(value):
		player_name = value
		stats_changed.emit()


## 名字有效吗？空串 / 纯空白 / 停在历史占位串上，都算「没填」。
func has_valid_name() -> bool:
	var n: String = String(player_name).strip_edges()
	return n != "" and n != NAME_PLACEHOLDER


## 显示用名：没填就兜底成 NAME_FALLBACK（现为「维克多」）。
## ⚠️ 全工程**只此一处**做这个兜底 —— 别在每个读取点各写一份，
##    否则一定出现「有的地方兜了、有的地方把「请输入你的名字」印到剧情里」。
##    唯一例外是对话面板的玩家选项行（那里按对话口径显示「你」，见 dialogue_ui._player_label）。
func player_display_name() -> String:
	var n: String = String(player_name).strip_edges()
	if n == "" or n == NAME_PLACEHOLDER:
		return NAME_FALLBACK
	return n

@export var player_app:int =0 #魅力
@export var player_int:int =0 #智力
@export var player_edu:int =1 #教育，暂时只和学校的剧情相关
@export var player_bod:int =0 #体魄
@export var player_str:int =0 #力量
#背景，暂时忽略
@export var player_bac:String ="男爵": #
	set(value):
		player_bac = value
		stats_changed.emit()
@export var nobility:int = 1: #贵族等级（1男爵~5公爵）
	set(value):
		nobility = clampi(value, 1, 5)
		player_bac = NOBILITY_RANKS.get(nobility, "男爵")
		stats_changed.emit()
@export var player_att:int =20 #属性点
#属性，用于鉴定,edu 和 bac暂时保留
## 主角装备 —— **三槽字典** `{"weapon": 装备名, "armor": 装备名, "jewelry": 装备名}`
## （2026-10-24 由数组改造，见本文件「装备（三槽制）」一节）。
##
## 🔴 为什么必须换成字典：NPC 条目的 equipment 一直是字典（`{slot: 名}`），
##    而 `character_panel.equipmentdeal()` 只认字典 —— 主角这边是数组 ⇒ **三个装备槽永远画成空的**，
##    玩家装了也看不见，这正是「装备不能安装」的一半。现在两边同形态，「装上 → 面板立刻有」。
## 老档里的数组形态由 `SaveLoader.apply_save_data` → `migrate_equipment_from_array()` 归槽。
@export var player_equipment := {}#装备（三槽字典）
@export var player_tags = []#词条
@export var player_num_tags := {}#可堆叠的词条
## 带 turn 的 tag 的剩余回合 {tag名: 剩余回合}。获得带 turn 的 tag 时登记，每「下一天」递减，
## 归零移除（见 _on_day_changed）。随 SaveLoader 白名单持久化（否则读档后永不消失）。
## 语义（2026-08-25 定）：获得当天 = 第 1 回合，turn=N 即存在 N 个回合，第 N 次「下一天」移除。
@export var tag_turns := {}
@export var gift_att = 15#天赋点数
@export var  player_stuff :=[]#物品

## 手牌账本（D-HAND1，2026-10-14）—— **「玩家手上有哪些卡」的真值**。
##
## 为什么必须存在：`CardArea` 是场景内节点，`change_scene_to_file` 一销毁就没了。过去全靠
## `main_ui._restore_hand()` 里三条写死的规则补回（主角 / 管家 / 孩子），于是**其余一切卡**
## —— 买的书、打听来的秘氛困惑博学、杂货店买的货、任何 `add_to_hand` 给的人物卡 ——
## 都会在切场景时静默蒸发。现在手牌是这里的持久状态，CardArea 只是它的视图。
##
## 元素 = `CardData.to_data()` 的快照字典。**顺序 = 手牌显示顺序**。
## ⚠️ 重复项只会出现在「可堆叠」卡上（与 CardArea 唯一性同口径）。
## ⚠️ 快照只作兜底：兑现一律走 `EffectProcessor.resolve_hand_entry()` —— 它优先取实时数据源
##    （主角 / npc 条目 / CardRegistry），取不到才用快照。这样 npc 改名、孩子属性成长都能同步。
## ⚠️ 进 `SaveLoader.PERSISTENT_FIELDS` 白名单，否则读档照样丢。
@export var hand: Array = []

## 老档迁移是否已经跑过（D-HAND2，2026-10-14）。
##
## 为什么需要它：迁移原本的安全阀是「hand 为空才跑」，可**手牌为空是一件太常见的事**
## —— 玩家把手上唯一一张卡拖进触发器卡槽的那几秒钟，账本就是空的。此时任何一个新场景
## `_restore_hand()` 都会再迁移一次，把 `Player.npc` 里的孩子卡（和主角卡）凭空补回来：
## 「被触发器占用的角色，切个场景就自己回到了手上」。
## 迁移是**一次性的老档修复**，不是补卡规则 —— 跑过就必须钉住。
@export var hand_migrated := false

## 手牌账本**世代**（瞬态，不进存档白名单）。`SaveLoader.apply_save_data` 每灌一次数据 +1。
##
## 为什么需要它（2026-10-24「点继续游戏手牌全没」）：`CardArea` 是场景内视图，切场景时它的
## `_exit_tree` 会把手里的 `_cards` 整本写回账本 —— 这条兜底在「正常换幕」时是对的（内容相同），
## 但**读档时**账本刚被 `apply_save_data` 换成存档内容，旧视图手里还是上一局的快照，
## 于是它这一写就把新账本整个盖掉（实测：读档前的 3 张覆盖掉存档里的 2 张；若旧视图是空的，
## 就是「所有卡片消失」）。
## 视图在 `_ready` 记下当时的世代，离场时世代不符 = 自己那份已经作废 → 一个字都不写。
var hand_gen: int = 0


# ============================================================
#  手牌账本 API（D-HAND1）
# ============================================================

## 当前账本里的卡 id 序列（含「可堆叠」造成的重复）。
func hand_ids() -> Array[String]:
	var out: Array[String] = []
	for entry in hand:
		if entry is Dictionary:
			out.append(String((entry as Dictionary).get("id", "")))
	return out


## 账本里是否已有该 id（按 CardArea 同款口径：`_card_id_of` 用 id，无 id 时退化 display_name）。
func hand_has(cid: String) -> bool:
	for entry in hand:
		if entry is Dictionary and String((entry as Dictionary).get("id", "")) == cid:
			return true
	return false


## 记一张进手牌。返回 true=新登记，false=已存在且不可堆叠（与 CardArea.add_card 同口径）。
func add_hand_card(card: CardData) -> bool:
	if card == null:
		return false
	var cid := _hand_id_of(card)
	if cid == "":
		return false
	if hand_has(cid) and not card.is_stackable():
		return false
	hand.append(card.to_data())
	return true


## 从手牌摘一张（拖进卡槽时用）。返回 true=确实摘掉了。
func remove_hand_card(cid: String) -> bool:
	for i in hand.size():
		if hand[i] is Dictionary and String((hand[i] as Dictionary).get("id", "")) == cid:
			hand.remove_at(i)
			return true
	return false


## 整本替换（CardArea 内容/顺序变化时全量写回，保证保存的是显示顺序）。
func set_hand_from(cards: Array) -> void:
	hand.clear()
	for c in cards:
		if c is CardData:
			hand.append((c as CardData).to_data())


## 注销失效条目（对应卡已无法兑现，多为数据里删掉了）。返回摘掉条数。
func drop_hand_entries(indices: Array) -> int:
	var n := 0
	var idxs: Array = indices.duplicate()
	idxs.sort()
	for i in range(idxs.size() - 1, -1, -1):
		var at := int(idxs[i])
		if at >= 0 and at < hand.size():
			hand.remove_at(at)
			n += 1
	return n


## 老档迁移（D-HAND1）：`hand` 是新增字段，老存档里没有它。
##
## 若不迁移，玩家一读旧档就会看到手牌空掉（比切场景丢卡还难解释）。所以这里把
## 旧 `main_ui._restore_hand()` 那三条写死的规则原样搬过来、跑一次，之后就交给账本。
## 幂等：同一进程内第二次调用不会重复补（`hand_migrated` 落地进存档白名单，
## 读档后由 `SaveLoader.apply_save_data` 灌回，跨会话也只补一次）。
##
## ⚠️ 老档可以放心「一条都没有」地补；但**不能在每次手牌变空时都重放** —— 那会把刚放进
##    触发器卡槽的角色卡复活回手上（D-HAND2）。这里两条短路径都打钉。
## `force=true`：绕过 `hand_migrated` 这枚钉，**只给 `SaveLoader` 的一次性事故补偿用**
## （2026-10-24「继续游戏手牌全没」，见 `SaveLoader._repair_empty_hand_once`）。
## 手上有卡时 force 也照样跳过补卡，只打钉 —— 所以 force 不会给正常档白送卡。
func migrate_hand_from_progress(force: bool = false) -> void:
	if hand_migrated and not force:
		return
	if not hand.is_empty():
		# 有内容就说明这是新档（账本已经在记账），别去复放老规则 —— 但同样要打钉，
		# 否则「先用着 → 某天真把手牌用空了」的老档仍会在那时被误补一次。
		hand_migrated = true
		return
	# 主角卡：原先靠 tag「第二天剧情」补回（对应「第二天剧情」2th 的 add_to_hand:["Hero"]）
	if player_has_tags(["第二天剧情"]):
		add_hand_card(get_hero_card())
	# 管家卡：原先靠 tag「斯库奇引导1」补回（内部标识符仍是旧字，见 characters.json）
	if player_has_tags(["斯库奇引导1"]):
		var sicourge: CardData = CardRegistry.get_card("Sicourge")
		if sicourge != null:
			add_hand_card(sicourge)
	# 孩子卡：扫 npc 里带 child tag 的条目实时构造
	for key in npc:
		var entry: Variant = npc[key]
		if entry is Dictionary and ("child" in (entry as Dictionary).get("tags", [])):
			add_hand_card(CardData.from_character(String(key), entry as Dictionary))
	hand_migrated = true


## 清空手牌（新游戏 / 特殊剧情用）。
func clear_hand() -> void:
	hand.clear()


## 账本 id 归一：与 `CardArea._card_id_of` 同口径（id 为空时退化成 display_name）。
static func _hand_id_of(card: CardData) -> String:
	return card.id if card.id != "" else card.display_name
## 成就解锁状态 {成就id:true}，由 AchievementManager 维护，随 SaveLoader 白名单持久化
@export var achievements_unlocked := {}
## 打听池已抽事件 id（商业街打听，随机不重复；随 SaveLoader 白名单持久化）
@export var inquiry_drawn := []
## 回合级触发器「本回合已消耗」卡 id（D-DOC24）：{触发id: [卡id...]}。
## 语义 = 该触发器**本回合实例**中已被消耗掉的卡（如神秘杂货店被买走的商品）：吸附/装槽时排除，
## 使已消耗的槽位保持空位（「被买了就没了」）。**仅本回合有效**——过天由
## `TriggerManager.advance_turn()`（回合边界唯一入口）清空，下回合实例重建时全池重抽
## （商品重新上架，池不足卡槽数就空着）。
## 随 SaveLoader 白名单持久化：同一天内存读档仍保持已消耗状态（跨回合由 advance_turn 清空）。
## 取代旧的 Player.goods_sold（D-DOC23 专用单字段 → D-DOC24 通用化，2026-09-13 用户拍板）。
@export var trigger_consumed := {}
## 报纸剧情新闻队列（剧情 effect `news` 入队；过天由 NewspaperGenerator 队首消费，多余顺移下天）
@export var pending_news := []
## 次日生效 tag 队列（D-PENDING-TAGS，2026-10-24）：effect `pending_tags` 入队，过天
##（_on_day_changed）统一转正。剧情要「第二天才出现」的节奏用这个，别用立即 tags。
## 随 SaveLoader 白名单持久化（读档/跨天一致）。
@export var pending_tags := []
## 上一天报纸 roll 到的随机效果 id（避免连续两天相同；随 SaveLoader 白名单持久化）
@export var last_flavor := ""
## 当天报纸快照（过天生成，供「报纸」按钮订阅者回看；随 SaveLoader 白名单持久化）
@export var daily_newspaper := {}

## 🎓 毕业结局状态（D-GRAD1，2026-10-16）——
##   第 20 回合起、有孩子且上满三次学（player_num_tags["学校学习"]≥3）时，由 TriggerManager
##   触发「毕业剧情连播 → 游戏结束（存档 + 回标题）」。两字段随存档持久化，专门为了
##   「结局播到一半存档/读档不断链」：
##   · graduation_stage："" = 未触发；"playing" = 剧情队列播放中；"done" = 已收场
##     （回标题前落盘，标题「继续游戏」读回后不会再播一遍）。
##   · graduation_queue：剩余待播剧情键（dialogue_registry 键名），按天赋分流：
##     gifted → ["毕业作品-选择方向", "毕业作品-毕业展"]；common → ["毕业和礼物"]。
##   ⚠️ 别用 tag 表示 stage —— tag 会进 show_when 判定，等于凭空多一个全局开关；
##      也别只存运行时变量 —— 半路读档要靠它把队列接回去。
@export var graduation_stage := ""
@export var graduation_queue: Array = []

@export_group("others")
@export var development = {}#剧情发展情况
@export var npc = {}#其他角色，包括伙伴，伙伴仅仅多一个追随的标签

@export var tutorial_progress := {} # 教学进度：{序列id: 已完成步骤数}（由 SaveLoader 存档）

## 反 SL 种子（D-SV6 / 鉴定 GDD §6）：一局游戏内固定，随存档持久化。
## 所有随机判定必须走 make_rng()，禁止裸 randi()——否则读档重来可刷结果。
@export var campaign_seed := ""

## 派生只读：唯一收养孩子的名字（{child_name} 文本 / 旧逻辑兼容用）。
## 孩子现已并入 npc（统一带 "child" 标签），此处只读取、不再单独存储，
## 从根本上消除「双份数据 + 手动同步」。设计上只收养一个孩子，
## 返回第一个带 child 标签的 npc 条目的 name；无孩子时返回空串。
var child_name: String:
	get:
		for key in npc:
			var entry: Variant = npc[key]
			if entry is Dictionary and "child" in entry.get("tags", []):
				return String(entry.get("name", key))
		return ""

#@export var character_label = {
	#"神速":{"description":"当你追上了风，当声音被甩在身后，会是怎样光景？"},
	#
	#"灵感":{"description":"世界的真相在你眼前浮现。"},
#
	#"灾厄":{"description":"灾厄是一把可怕的钥匙，它会开启什么呢？"},	
	#
	#"学习":{"description":"苟日新，日日新。"},
#}

@export var is_dialogue_exist := false
@export var is_check_exist := false

#属性改变函数（裸值增量；**只封顶** ATTR_MAX=10 = 人类极限，奖励到顶后不再增长）
# ⚠️ 这里**故意不写下限**：允许负值，0 只是通常人类的下限（理由见 ATTR_MAX 上方注释）。
#    别顺手改成 maxi(mini(...), 0) —— 那会让「以力破巧」这类负值天赋的体魄 −1 静默消失。
func change_int(value:int):
	player_int = mini(player_int + value, ATTR_MAX)


func change_app(value:int):
	player_app = mini(player_app + value, ATTR_MAX)

	
func change_bod(value:int):
	player_bod = mini(player_bod + value, ATTR_MAX)

	
func change_str(value:int):
	player_str = mini(player_str + value, ATTR_MAX)

	
func change_att(value:int):
	player_att += value	


# ============================================================
#  装备（三槽制：weapon / armor / jewelry，2026-10-24）
# ============================================================

## 装备槽顺序 —— 必须与 `character_panel.gd::SLOTS3` 一致。
## 顺序有意义：一件物品可以同时属于多个类（「精心磨制的小刀」= weapon+jewelry+tool），
## 归槽一律按**本数组顺序取首个命中**，与 `CardData.category_minor()` 的「武器优先」同口径。
const EQUIP_SLOTS: Array[String] = ["weapon", "armor", "jewelry"]
const EQUIP_SLOT_CN := {"weapon": "武器", "armor": "防具", "jewelry": "饰品"}


## 这张卡能进哪一槽。不是装备（三槽都不命中）返回 ""。
## 🔴 只认 `card_class`（items/*.json 的 `class`），**不认 tags** —— tags 里的「武器 / 饰品」
##    是文案用的，和槽位不是一回事（「精心磨制的小刀」tags 有「武器」「工具」，class 才是 weapon/jewelry）。
static func equip_slot_of(card: CardData) -> String:
	if card == null or card.card_type != "item":
		return ""
	for slot in EQUIP_SLOTS:
		if slot in card.card_class:
			return slot
	return ""


## 装备名 → 槽位。注册表里没有（剧情临时授予的物品）就查 TagRegistry 的 items 缓存。
static func equip_slot_of_name(item_name: String) -> String:
	var card: CardData = CardRegistry.get_card(item_name)
	if card != null:
		return equip_slot_of(card)
	return equip_slot_of_class_list(TagRegistry.get_equipment(item_name).get("class", []))


## 类列表 → 槽位（`class` 支持字符串 / 数组两种写法，与 `CardData._to_class_array` 同口径）。
static func equip_slot_of_class_list(raw: Variant) -> String:
	var classes: Array = []
	if raw is String:
		classes.append(String(raw))
	elif raw is Array:
		classes = raw
	for slot in EQUIP_SLOTS:
		if slot in classes:
			return slot
	return ""


## 某角色的装备字典 —— **返回引用**（写回用），调用方不要长期持有。
## Hero → `player_equipment`；其余 → npc 条目的 `equipment`。
## 条目里是数组（老档 / 剧情脚本写出来的）时**原地收敛成字典**，全工程只此一处做形态兜底。
func equipment_map_of(npc_key: String) -> Dictionary:
	if npc_key == "" or npc_key == HERO_KEY:
		if not (player_equipment is Dictionary):
			var legacy: Variant = player_equipment
			player_equipment = _equip_array_to_map(legacy) if legacy is Array else {}
		return player_equipment
	var entry: Variant = npc.get(npc_key, null)
	if not (entry is Dictionary):
		return {}
	var e: Dictionary = entry
	var raw: Variant = e.get("equipment", {})
	if raw is Dictionary:
		# 🔴 必须补键：`Dictionary.get(k, {})` 在键不存在时给的是**一个游离的临时字典**，
		#    往它里面写不会落进条目 —— 装备等于装进虚空（探针 _equip_probe 的 E 段踩过）。
		if not e.has("equipment"):
			e["equipment"] = raw
		return raw
	e["equipment"] = _equip_array_to_map(raw if raw is Array else [])
	return e["equipment"]


## 某角色身上全部装备名（`total_check_bonus` / 鉴定 modifiers 的 `source:"equipment"` 用）。
## 字典只管取值 —— 槽位名（weapon 等）**不是**装备名，直接遍历字典会把键喂进去。
func equipment_names(npc_key: String = HERO_KEY) -> Array:
	var out: Array = []
	var m := equipment_map_of(npc_key)
	for k in m:
		var n := String(m[k])
		if n != "":
			out.append(n)
	return out


## 装一张装备卡到某角色身上。**同类替换**：旧装备不销毁，由调用方（UI）送回手牌。
## 返回 {"ok":bool, "slot":String, "replaced":String, "reason":String}
##   reason: ""（成功）/ "not_equipment"（不是装备卡）/ "already"（这一槽已经是它）
func equip_card(npc_key: String, card: CardData) -> Dictionary:
	var slot := equip_slot_of(card)
	if slot == "":
		return {"ok": false, "slot": "", "replaced": "", "reason": "not_equipment"}
	var m := equipment_map_of(npc_key)
	var prev := String(m.get(slot, ""))
	if prev == card.id:
		return {"ok": false, "slot": slot, "replaced": "", "reason": "already"}
	m[slot] = card.id
	_sync_equipment_owner(npc_key)
	return {"ok": true, "slot": slot, "replaced": prev, "reason": ""}


## 按装备名装到主角身上（JSON effect 的 `equipment` 数组走这条）。返回被替换的装备名。
## 查不到类别（既不在注册表也不在 items 缓存）→ 忽略 + warning：三槽制下没有「无槽装备」的落脚点。
func equip_by_name(item_name: String) -> String:
	var slot := equip_slot_of_name(item_name)
	if slot == "":
		push_warning("Player.equip_by_name：「%s」不是装备（查不到 class），已忽略" % item_name)
		return ""
	var m := equipment_map_of(HERO_KEY)
	var prev := String(m.get(slot, ""))
	if prev == item_name:
		return ""
	m[slot] = item_name
	_sync_equipment_owner(HERO_KEY)
	return prev


## 卸下某槽的装备，返回被卸下的装备名（"" = 本来空着）。
func unequip_slot(npc_key: String, slot: String) -> String:
	var m := equipment_map_of(npc_key)
	var prev := String(m.get(slot, ""))
	if prev == "":
		return ""
	m.erase(slot)
	_sync_equipment_owner(npc_key)
	return prev


## 换完装备后的收尾：Hero 要把 player_equipment 镜像进 npc 条目（人物面板读的是条目），
## 其余角色条目即真值；两者都发一次 stats_changed 让 HUD / 生效属性重算。
func _sync_equipment_owner(npc_key: String) -> void:
	if npc_key == "" or npc_key == HERO_KEY:
		hero_merge()
	notify_stats_changed()


## 数组形态 → 三槽字典。同槽多件时**后出现的覆盖前面的**（数组顺序 = 获得顺序）。
static func _equip_array_to_map(raw: Array) -> Dictionary:
	var out := {}
	for v in raw:
		var n := String(v)
		if n == "":
			continue
		var slot := equip_slot_of_name(n)
		if slot == "":
			push_warning("Player：装备「%s」查不到 class，未归槽（已丢弃）" % n)
			continue
		out[slot] = n
	return out


## 老档迁移（由 `SaveLoader.apply_save_data` 调）：把数组形态的装备灌进三槽字典。
## 幂等：只在拿到非空数组时才会被调用；不覆盖已经归好槽的字典。
func migrate_equipment_from_array(raw: Array) -> void:
	var mapped := _equip_array_to_map(raw)
	if mapped.is_empty():
		return
	player_equipment = mapped
	print("[Player] 老档装备迁移为三槽字典：%s" % str(mapped))


# ============================================================
#  生效属性（实值）统一入口 —— 裸值 + tag bonus + 装备 bonus
#  口径统一：全项目判定/显示的「实值」都从这里取，不再各处手拼 attrs/tags。
#  转发 TagRegistry.effective_attrs（含 tag/装备 bonus）。
# ============================================================

## 生效属性统一入口。subject 三种形态：
##   - CardData          → .attrs + .tags + 对应装备（主角卡用 player_equipment，NPC 查 npc 条目）
##   - String(npc_key)   → npc 条目；"Hero" 回落主角
##   - Dictionary         → {"attrs":{}, "tags":[], "equipment"?}
func effective_attrs_of(subject: Variant) -> Dictionary:
	if subject is CardData:
		var c: CardData = subject
		return TagRegistry.effective_attrs(c.attrs, c.tags, _equipment_of_card(c))
	if subject is String:
		return effective_npc_attrs(String(subject))
	if subject is Dictionary:
		var d: Dictionary = subject
		return TagRegistry.effective_attrs(d.get("attrs", {}), d.get("tags", []), d.get("equipment", null))
	return {}


## 主角生效属性（裸值 + tag bonus + player_equipment 装备 bonus）。
func effective_self_attrs() -> Dictionary:
	return TagRegistry.effective_attrs(
		{"int": player_int, "app": player_app, "str": player_str, "bod": player_bod},
		player_tags,
		player_equipment
	)


## NPC 生效属性（按 npc key；"Hero" 回落主角）。含 npc 条目的 equipment（如有）。
func effective_npc_attrs(npc_key: String) -> Dictionary:
	if npc_key == "Hero":
		return effective_self_attrs()
	var d: Dictionary = npc.get(npc_key, {})
	return TagRegistry.effective_attrs(
		{"int": int(d.get("int", 0)), "app": int(d.get("app", 0)), "str": int(d.get("str", 0)), "bod": int(d.get("bod", 0))},
		d.get("tags", []),
		d.get("equipment", null)
	)


## CardData 对应的装备：主角卡（id=="Hero"）→ player_equipment；NPC → 查 npc 条目 equipment。
func _equipment_of_card(c: CardData) -> Variant:
	if c.id == "Hero":
		return player_equipment
	var d: Dictionary = npc.get(c.id, {})
	return d.get("equipment", null)


## 贵族等级 -> 爵位名（D-NOB）。rank 缺省取当前 Player.nobility，越界按 1~5 夹取。
func player_nobility_title(rank: int = -1) -> String:
	var r := rank if rank > 0 else int(nobility)
	r = clampi(r, 1, 5)
	return NOBILITY_RANKS.get(r, "男爵")


func get_npc_data(npc_name: String) -> Dictionary:
	return npc.get(npc_name, {})


func npc_has_tags(npc: String, tags: Array, method := 1) -> bool:
	var npc_data = get_npc_data(npc)
	var npc_tags = npc_data.get("tags", [])
	if method == 1 :
		return tags.all(func(tag): return tag in npc_tags)
	else:
		return tags.any(func(tag): return tag in npc_tags)


## NPC 键反查（2026-10-24 触发器 npc_num_tags 起）。
## 顺序：Player.npc 的键精确命中 → 条目里的 name / display_name 反查（数据里常写中文名，
## 如「露易丝」→ Louise，跟 EffectProcessor._npc_key_of 同一口径）→ 都没有返回 ""。
## ⚠️ 返回 "" 由调用方决定语义：触发器的 show_when 一律「判否 + warning」，
## 键写错要吵出来，不能因为查不到就当无约束放行。
func resolve_npc_key(npc_name: String) -> String:
	if npc.has(npc_name):
		return npc_name
	for key in npc:
		var entry: Variant = npc[key]
		if entry is Dictionary:
			if String((entry as Dictionary).get("name", "")) == npc_name:
				return String(key)
			if String((entry as Dictionary).get("display_name", "")) == npc_name:
				return String(key)
	return ""


## NPC 的数值词条读值（缺省 0）。键走 resolve_npc_key，所以中文名也能读。
func npc_num_tag_value(npc_name: String, tag: String) -> int:
	var key := resolve_npc_key(npc_name)
	if key == "":
		return 0
	var entry: Dictionary = get_npc_data(key)
	var nts: Variant = entry.get("num_tags", {})
	if not (nts is Dictionary):
		return 0
	return int((nts as Dictionary).get(tag, 0))

	
func player_attr_meet(att: String, compare: String, value: int) -> bool:
	var player_attr  
	match att:
		"app":
			player_attr = player_app
		"int":
			player_attr = player_int
		"bod":
			player_attr = player_bod
		"str":
			player_attr = player_str
		"edu":
			player_attr = player_edu
		_:
			return false  


	match compare:
		"=":
			return player_attr == value
		">":
			return player_attr >= value
		"<":
			return player_attr <= value
		_:
			return false  
		

func player_has_tags(tags: Array, method := 1) -> bool:
	if method == 1 :
		return tags.all(func(tag): return tag in player_tags)
	else:
		return tags.any(func(tag): return tag in player_tags)		
		
		
func player_meet_num_tag(tag: String,left: int,right: int) -> bool:		
	if tag in player_num_tags:
		if player_num_tags[tag] >= left && player_num_tags[tag] <= right:
			return true
	return false
	
	
func npc_meet_num_tag(tag: String,npcname: String,left: int,right: int) -> bool:	
	if npcname in npc:
		if "num_tags" in npc[npcname]:	
			if tag in npc[npcname].num_tags:
				if npc[npcname].num_tags[tag] >= left && npc[npcname].num_tags[tag] <= right:
					return true
	return false


func _ready() -> void:
	# 订阅过天信号做 tag 到期倒计时。Player 是第 1 个 Autoload、早于 EventSignal 初始化，
	# 故 call_deferred 延迟到所有 Autoload 就绪后再 connect，避免访问未就绪单例。
	_connect_day_changed.call_deferred()


func _connect_day_changed() -> void:
	if EventSignal.has_signal("day_changed"):
		EventSignal.day_changed.connect(_on_day_changed)


## 过天回调：玩家 + 所有 NPC 的带 turn tag 递减，归零移除。有到期时同步 Hero 卡 + 刷新 HUD。
## 注：`trigger_consumed`（回合级触发器已消耗表）**不在此清空**——由
## `TriggerManager.advance_turn()` 在同一次 day_changed 里与「回合实例重建」一并处理
## （D-DOC24：两个动作必须同序，否则新一天的货架会错误排除昨天卖掉的商品）。
func _on_day_changed(_day: int) -> void:
	var changed := false
	# D-PENDING-TAGS：次日生效 tag 转正（统一走 grant_tag：去重 + turn 计时登记）。
	if not pending_tags.is_empty():
		for t in pending_tags:
			grant_tag(String(t))
		pending_tags.clear()
		changed = true
	if _tick_tag_turns(player_tags, tag_turns):
		changed = true
	for key in npc:
		var entry: Variant = npc[key]
		if entry is Dictionary and entry.has("tag_turns") and entry["tag_turns"] is Dictionary:
			if _tick_tag_turns(entry.get("tags", []), entry["tag_turns"]):
				changed = true
	if changed:
		# 玩家 tag 被移除 → Hero 卡 tags 需同步（mirror 只在 EffectProcessor.apply 末尾跑，覆盖不到这里）
		hero_merge()
		notify_stats_changed()


## 递减一个主体的 tag 计时；归零的 tag 从 tags 数组移除、清计时条目。
## 返回是否有 tag 到期（未到期仅递减，不算「变动」，避免无谓刷新）。
func _tick_tag_turns(tags: Array, turns: Dictionary) -> bool:
	var expired: Array = []
	for tag_name in turns.keys():
		var remaining := int(turns[tag_name]) - 1
		if remaining <= 0:
			expired.append(String(tag_name))
		else:
			turns[tag_name] = remaining
	if expired.is_empty():
		return false
	for tag_name in expired:
		turns.erase(tag_name)
		tags.erase(tag_name)
	return true


## 给玩家加一个 tag（去重），并按 tags.json 的 turn 登记 / 刷新剩余回合。
## 带 turn 的 tag 重复 grant = 重置计时（疲惫续命）；无 turn 的 tag 仅去重 append。
## 统一入口：EffectProcessor 直落分支与 TriggerManager.complete_flow 都走这里，
## 保证「tag 落进 player_tags」与「turn 计时登记」永远成对发生。
func grant_tag(tag: String) -> void:
	if not (tag in player_tags):
		player_tags.append(tag)
	var t := TagRegistry.get_turn(tag)
	if t > 0:
		tag_turns[tag] = t
	else:
		tag_turns.erase(tag)


## 摘除玩家 tag，并同步清掉其回合计时（若有）。与 grant_tag 对称。
func remove_tag(tag: String) -> void:
	if tag in player_tags:
		player_tags.erase(tag)
	tag_turns.erase(tag)


## 批量修改数据后手动广播一次（读档、结算等场合），供 HUD 刷新。
func notify_stats_changed() -> void:
	stats_changed.emit()


# ============================================================
#  反 SL 随机源（鉴定 GDD §6 / 存档 GDD D-SV6）
# ============================================================

## 确保本局有种子；没有则生成一个（新游戏 / 老档读入时调用）。返回种子。
func ensure_campaign_seed() -> String:
	if campaign_seed == "":
		campaign_seed = "%d-%d" % [int(Time.get_unix_time_from_system()), randi()]
	return campaign_seed


## 确定性随机源：**同一局 + 同一天 + 同一 seed_key → 结果恒定**。
## 读档重来不会改变结果，把"刷结果"转化为"回去做准备"（反 SL）。
## seed_key 建议带上业务名与对象名，如 "voyage:主管张三"。
## extra 用于同一天内需要多次独立掷骰的场合（如第 2 次出航）。
func make_rng(seed_key: String, extra: String = "") -> RandomNumberGenerator:
	return make_rng_for_day(seed_key, time, extra)


## 指定天数的确定性随机源（2026-10-15 孩子线二轮）。
## 除了「换一天就换一组结果」，与 make_rng 完全同一口径（同一条 seed 拼装式），
## 所以 make_rng(key) == make_rng_for_day(key, time)。
## 用途：需要**回看前一天掷出了什么**的判定 —— 目前唯一消费者是 TriggerSpot 的
## show_when.chance「隔天保底」（第 x 天没出现 → 第 x+1 天必现，见 trigger_spot.gd）。
func make_rng_for_day(seed_key: String, day: int, extra: String = "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ensure_campaign_seed() + "|" + seed_key + "|" + str(day) + "|" + extra)
	return rng


## 便捷：确定性 dX 掷骰（默认 d10，见家业经营 GDD 骰子档 B）。
func roll_dice(seed_key: String, sides: int = 10, extra: String = "") -> int:
	return make_rng(seed_key, extra).randi_range(1, max(1, sides))


## 把玩家实时属性同步进"主角卡"（npc 里的主角条目），供人物面板 / 卡牌系统读取。
## 只覆盖会随成长变化的字段，image / description / gender 等静态字段保持原样。
## 注意：主角在 npc 里的键名是 "Hero"（selection.gd、main_ui.gd 都用它），
## 旧实现写成 `npc.hero` 会直接 KeyError，这里改为按键名取并加存在性守卫。
## 运行期一致性由 EffectProcessor._mirror_player_to_hero() 在每次 apply 末尾自动保证；
## 本方法保留给 save_loader 在存档前 / 读档后作双保险（修正旧档 hero 与 player_* 不一致）。
## 用 duplicate 避免引用共享——hero 是独立副本，值与 player_* 一致但不耦合。
func hero_merge(hero_key: String = HERO_KEY) -> void:
	var card: Variant = npc.get(hero_key, null)
	if not (card is Dictionary):
		return
	card["name"] = player_display_name()
	card["int"] = player_int
	card["app"] = player_app
	card["str"] = player_str
	card["bod"] = player_bod
	card["equipment"] = player_equipment.duplicate()
	card["tags"] = player_tags.duplicate()
	card["num_tags"] = player_num_tags.duplicate()


## 构造代表「主角」的 CardData（亲历鉴定 protagonist_only 用）。
## 亲历鉴定的执行者恒为主角，故从 Player 自身属性即时构建，不依赖卡牌注册表。
## 注：本函数返回的卡只在本流程内使用，不入卡牌区、不写回注册表。
##
## 🔴 2026-10-10 修：「主角有时卡牌里没有图片」。
##    本函数原先**完全不设 icon_path**（保持 CardData 的默认空串），而 `CardChip._try_load_icon()`
##    当时的实现是「icon_path 为空就直接 return null」。结果两张来源不同的主角卡表现不一致：
##      · `CardRegistry.get_card("Hero")`（characters.json 静态预设，读 `image`）→ 有图 ✅
##      · `Player.get_hero_card()`（`_restore_hand` / `add_to_hand` 走这条）→ 图像区空白 ❌
##    静默、不报错，所以像"随机"。
##    现在补上 icon_path，并连同 description 一起取，使两个来源产出的主角卡等价。
func get_hero_card() -> CardData:
	var c := CardData.new()
	c.id = "Hero"
	c.card_type = "character"
	c.display_name = player_display_name()
	c.attrs = {"int": player_int, "app": player_app, "str": player_str, "bod": player_bod}
	var ts: Array[String] = []
	# 身份词条在前（卡牌情况 用 tag 认主角），剧情/成长词条随后并去重。
	for t in HERO_IDENTITY_TAGS:
		ts.append(String(t))
	for t in player_tags:
		var s := String(t)
		if not (s in ts):
			ts.append(s)
	c.tags = ts
	c.icon_path = hero_image_path()
	c.description = String(hero_entry().get("description", ""))
	return c


## 主角在 Player.npc 里的条目（不存在时返回空字典，不新增、不报错）。
func hero_entry() -> Dictionary:
	var entry: Variant = npc.get(HERO_KEY, null)
	return entry if entry is Dictionary else {}


## 主角立绘路径。**权威来源 = `Player.npc["Hero"]["image"]`** —— 它由
## `main_ui.ensure_hero_card()` 从 characters.json 的 Hero 模板填进去（`image` 是静态字段，
## `hero_merge()` 只同步成长字段，不会覆盖它）。
## 模板还没建立（如纯逻辑探针、无主 UI 的流程）时用 HERO_IMAGE_FALLBACK 保底。
## ⚠️ 刻意**不**回落到 `CardRegistry.get_card("Hero")`：Player 是第一个 autoload，
##    `--script` 等无水合场景里 CardRegistry 可能不存在；跨 autoload 取数会变成隐性依赖。
func hero_image_path() -> String:
	var p := String(hero_entry().get("image", ""))
	return p if p != "" else HERO_IMAGE_FALLBACK
