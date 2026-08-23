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

@export_group("curtain_scence")
@export var path = ''#当前路径
@export var plot = ''#当前正在经历的事件
@export var exact_situation = {}#该回合已经进行的操作 

@export_group("player")
@export var player_age :=16.0 
@export var time := 1:
	set(value):
		time = value
		stats_changed.emit()
#用于定义时间相关的事件
@export var player_money = 100:
	set(value):
		player_money = value
		stats_changed.emit()
@export var player_app_fact =""
@export var player_name ="请输入你的名字":
	set(value):
		player_name = value
		stats_changed.emit()

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
@export var player_equipment = []#装备
@export var player_tags = []#词条
@export var player_num_tags := {}#可堆叠的词条
@export var gift_att = 60#天赋点数
@export var  player_stuff :=[]#物品
## 成就解锁状态 {成就id:true}，由 AchievementManager 维护，随 SaveLoader 白名单持久化
@export var achievements_unlocked := {}

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

#属性改变函数
func change_int(value:int):
	player_int += value


func change_app(value:int):
	player_app += value	

	
func change_bod(value:int):
	player_bod += value

	
func change_str(value:int):
	player_str += value	

	
func change_att(value:int):
	player_att += value	


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
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ensure_campaign_seed() + "|" + seed_key + "|" + str(time) + "|" + extra)
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
func hero_merge(hero_key: String = "Hero") -> void:
	var card: Variant = npc.get(hero_key, null)
	if not (card is Dictionary):
		return
	card["name"] = player_name
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
func get_hero_card() -> CardData:
	var c := CardData.new()
	c.id = "Hero"
	c.card_type = "character"
	c.display_name = player_name if player_name != "" else "主角"
	c.attrs = {"int": player_int, "app": player_app, "str": player_str, "bod": player_bod}
	var ts: Array[String] = []
	for t in player_tags:
		ts.append(String(t))
	c.tags = ts
	return c
