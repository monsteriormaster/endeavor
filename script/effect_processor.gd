class_name EffectProcessor
## 统一效果处理器。三个系统（对话 / 鉴定 / 触发器 / 天赋选择）共用同一套 effect 契约。
##
## 取代旧三处重复实现：dialogue_ui.deal_effect / check_processor.deal_effect / trigger_manager.apply_effect。
## 调用方仅需按需传入 context，行为差异（流程态 tag 隔离、goto_scene 延迟、name_child 阻塞）由 context 控制。
##
## effect 字段（扁平字典）：
##   money:int                 - 加减金钱（正给负扣）
##   tags:Array                - 玩家词条标签
##   num_tags:Dictionary       - 可堆叠词条 {名: 值}
##   stuff:Array               - 物品
##   attrs:Dictionary          - 属性 {int/app/str/bod: 增量}
##   npc:Dictionary            - 获得/修改 NPC {npc_key: {tags:[], num_tags:{}}}
##                               npc_key 不在 Player.npc 时，从 res://resoures/characters.json
##                               加载该 key 的完整预设（name/image/attrs/tags/equipment/description），
##                               再追加 effect 里的 tags/num_tags。用于"获得同伴"等场景。
##                               ⭐ 入队 tag（ENTRY_TAGS =「追随」/「跟随」）：npc 拿到其一即**自动进手牌**
##                               （`_sync_follower_card`，幂等），effect 里不必再写 add_to_hand。
##                               主角（npc_key=="Hero"）特殊：对 Hero 的改动回写 Player.player_*
##                               （双向同步），支持 tags/num_tags/attrs/name/equipment；
##                               Hero 卡成长字段由 apply 末尾 _mirror_player_to_hero() 统一镜像。
##   child:Dictionary          - 孩子（已并入 npc：创建/追加 npc 条目并强制带 "child" 标签，见 _add_child_npc）
##   child_attrs:Dictionary    - 「唯一孩子」属性增量 {int/app/str/bod: 增量}（2026-10-11 孩子线）。
##                               定位 = PlotImporter.child_key_of()（首个带 child 标签的 npc）；
##                               裸值累加 + 封顶 ATTR_MAX（与学校触发器 slot_attrs 同口径）。无孩子则跳过。
##   child_num_tag_add:Dictionary - 「唯一孩子」可堆叠词条增量 {词条: delta}（依恋/独立 等）
##   child_tags:Array          - 「唯一孩子」普通词条
##   delayed_event:Dictionary  - {days:N, plot:"剧情键名"}：N 回合后播该剧情（登记进 TriggerManager
##                               延迟队列，键名须在 dialogue_registry.json 注册）
##   equipment:Array           - 装备
##   remove_tags:Array         - 移除玩家标签（同时清流程字典与 player_tags）
##   remove_num_tags:Dictionary- 移除可堆叠词条
##   fatigue:bool              - 疲惫（酒馆打工 GDD）：无「疲惫」→ 获得「疲惫」；
##                               已有「疲惫」→ 获得「疾病」。**归属 = 执行者**（2026-10-25）：
##                               context.placed 的「执行者」槽卡（其次第一张角色卡）——
##                               Hero 落 player_tags，NPC 落其条目 tags；无执行者卡
##                               （纯剧情 effect）才回退 player_tags / 流程字典。
##                               「疲惫」带 turn=5（见 tags.json）：直落时由 Player.grant_tag /
##                               _grant_npc_tag 登记剩余回合；已有疲惫再疲劳（得疾病）→ 疲惫续命重置。
##   num_tags 值语法：int = 绝对赋值（原契约，向后兼容）；
##                    Dictionary {"add":N, "cap":M} = 在现值上 +N、封顶 M
##                    （「酒馆后厨工作经验+1（上限3）」用）。
##   goto_scene:String         - 换图（仅登记到 context，由调用方延迟执行，见 collect_goto）
##   name_child:Dictionary     - 取名弹窗（阻塞型，需 context.on_name_child 回调）
##   clamp_attrs:Dictionary    - 属性夹值 {min, max}（天赋"平凡可贵"专用）
##                               本处理器**故意不处理**：一次性夹值只在 selection 界面生效，
##                               由 selection.gd 自行解析并最后执行，避免对话/鉴定/触发器误触发。
##   achievement:String|Array - 解锁成就（成就 id 或 id 数组），转发 AchievementManager.unlock，幂等
##   slot_tags:Dictionary      - 对槽位角色施加 tag（D-DOC9）：{slot_name: [tag,...]}，
##                               需 context.placed = {slot_name: CardData}；主角卡→player_tags，NPC→npc条目
##   slot_attrs:Dictionary     - 对槽位角色施加属性增量（D-DOC9）：{slot_name: {attr: N}}，
##                               主角卡→change_*，NPC→npc条目 int/app/str/bod 字段 +N
##   slot_remove_tags:Dictionary - 移除槽位角色的 tag（D-DOC13 越狱）：{slot_name: [tag,...]}；
##                               目标 NPC 不存在或 tag 缺失则安全跳过（不新增条目、不报错）
##   slot_num_tags:Dictionary   - 槽位角色 num_tag 增量/赋值（D-DOC13 越狱）：{slot_name: {tag: spec}}；
##                               spec 为 int=绝对赋值，{"add":N,"cap":M}=增量+封顶（与 num_tags 同语法）
##
## context（可选）:
##   flow_tags:Dictionary      - 触发器流程态 tag 字典；提供则 tags 进此字典（流程结束才提交 player_tags），
##                               否则 tags 直接进 Player.player_tags（对话/鉴定/天赋）
##   collect_goto:bool         - 为 true 时把 goto_scene 写入 context["goto_scene"]，供调用方取用并延迟执行
##   on_name_child:Callable    - name_child 回调，签 (cfg:Dictionary)->void；未提供则 push_warning 跳过
##   placed:Dictionary         - {slot_name: CardData}（触发器流程），供 slot_tags/slot_attrs 定位施加对象
##
## 返回: bool - 是否阻塞（name_child 触发时为 true，调用方据此暂存 _pending_next）


const CHARACTERS_PATH := "res://resoures/characters.json"

## 入队 tag（D-FOLLOW1，2026-10-16）—— NPC 条目获得下列任一 tag 时，自动把它的角色卡补进手牌。
##
## 为什么要有这条规则：`add_to_hand` 是**显式键**，与「这个人入队了」这条剧情意图没有任何绑定，
## 于是出现「effect 写了 npc.{追随}、却漏了 add_to_hand」→ 人物永远上不了手（露易丝「死生契阔」、
## 阿尔温「阿尔温的未来」两处实测如此）。把「入队」收敛到一个 tag 上，策划只写一处，
## 就不会再有「剧情给了 tag、人却不在手里」的静默断链。
## 「追随」与「跟随」是同一语义的两种写法，两个都认；以后要加别的措辞（如「同行」）往这里加即可。
const ENTRY_TAGS: Array[String] = ["追随", "跟随"]

## characters.json 惰性缓存（首次获得预设 NPC 时加载）。
static var _characters_cache: Dictionary = {}


## 应用一个 effect 字典到 Player 状态。核心入口。
static func apply(effect: Dictionary, context: Dictionary = {}) -> bool:
	if effect.is_empty():
		return false

	var blocked := false
	var flow_tags: Variant = context.get("flow_tags", null)

	# goto_scene：仅登记到 context（触发器延迟到 complete_flow 后执行）。
	# 对话/鉴定/天赋不传 collect_goto，goto_scene 被忽略——这些系统本就不靠 effect 换图。
	var goto_v: Variant = effect.get("goto_scene", null)
	if goto_v is String and goto_v != "":
		if bool(context.get("collect_goto", false)):
			context["goto_scene"] = String(goto_v)

	# delayed_event（2026-10-11 孩子线）：把「N 回合后播某剧情」登记进 TriggerManager 的延迟队列。
	# 旧实现只在触发器 effect 里处理（trigger_manager.apply_effect），剧情 effect 走不到那条路；
	# 这里补剧情侧入口，落点与触发器侧同一函数（fire_day = 当天 + days），不产生第二套口径。
	# 键名须登记在 resoures/plot/dialogue_registry.json，否则到期只会 push_warning 跳过。
	var de_v: Variant = effect.get("delayed_event", null)
	if de_v is Dictionary:
		TriggerManager.register_delayed_event(
			int((de_v as Dictionary).get("days", 1)),
			String((de_v as Dictionary).get("plot", ""))
		)

	# pending_tags（D-PENDING-TAGS，2026-10-24）：**次日生效**的玩家 tag。剧情要
	# 「第二天才出现」的节奏（露易丝线涂鸦/涂鸦大作战）用这个，别用立即 tags——
	# 入队后过天由 Player._on_day_changed 统一转正（grant_tag 全口径：去重 + turn 计时）。
	# 随 SaveLoader 白名单持久化，读档/跨天一致。
	var pending_tags_v: Variant = effect.get("pending_tags", null)
	if pending_tags_v is Array:
		for p_tag in pending_tags_v:
			var pt := String(p_tag)
			if pt != "" and not (pt in Player.pending_tags):
				Player.pending_tags.append(pt)

	# tags：流程态隔离（触发器进 flow_tags，其余直接进 player_tags，去重）
	var tags_v: Variant = effect.get("tags", null)
	if tags_v is Array:
		for tag in tags_v:
			var t := String(tag)
			if flow_tags is Dictionary:
				flow_tags[t] = true
			else:
				# 直落 player_tags：统一走 grant_tag，顺带登记 turn 计时（带 turn 的 tag）
				Player.grant_tag(t)

	# 可堆叠词条：int = 绝对赋值（原契约）；{"add":N,"cap":M} = 增量 + 封顶
	var num_tags_v: Variant = effect.get("num_tags", null)
	if num_tags_v is Dictionary:
		for tag in num_tags_v:
			var spec: Variant = num_tags_v[tag]
			var tag_name := String(tag)
			if spec is Dictionary:
				var add := int(spec.get("add", 0))
				var cap_v: Variant = spec.get("cap", null)
				var cur := int(Player.player_num_tags.get(tag_name, 0))
				var new_val := cur + add
				if cap_v != null:
					new_val = mini(new_val, int(cap_v))
				Player.player_num_tags[tag_name] = new_val
			else:
				Player.player_num_tags[tag_name] = int(spec)

	# 物品
	var stuff_v: Variant = effect.get("stuff", null)
	if stuff_v is Array:
		for s in stuff_v:
			Player.player_stuff.append(s)

	# remove_stuff：移除物品（失去《舞春神》/越狱工具清单等）。缺失则安全跳过。
	var remove_stuff_v: Variant = effect.get("remove_stuff", null)
	if remove_stuff_v is Array:
		for s in remove_stuff_v:
			Player.player_stuff.erase(String(s))

	# 金钱
	if effect.has("money"):
		Player.player_money += int(effect["money"])

	# 属性
	var attrs_v: Variant = effect.get("attrs", null)
	if attrs_v is Dictionary:
		for attr_name in attrs_v:
			var change := int(attrs_v[attr_name])
			match str(attr_name):
				"int":
					Player.change_int(change)
				"app":
					Player.change_app(change)
				"str":
					Player.change_str(change)
				"bod":
					Player.change_bod(change)

	# npc：获得/修改 NPC。Player.npc 无此 key 时从 characters.json 加载完整预设。
	# 主角（键名 "Hero"）特殊处理：对 Hero 的改动回写 Player.player_*（双向同步）。
	# Hero 卡的成长字段由 apply 末尾 _mirror_player_to_hero() 统一镜像，故此处不再单独写 Hero 卡，
	# 只把对 Hero 的改动落到 player_*；非 Hero 的 NPC 仍按原契约写其 npc 条目。
	var npc_v: Variant = effect.get("npc", null)
	# 本条 effect 里拿到「入队 tag」的 npc 键（npc 分支结束后统一补手牌，见 ENTRY_TAGS）。
	var follow_keys: Array[String] = []
	if npc_v is Dictionary:
		for npc_name in npc_v:
			if not (npc_name is String):
				continue
			var is_hero := (String(npc_name) == "Hero")
			if not Player.npc.has(npc_name):
				Player.npc[npc_name] = _load_preset_npc(String(npc_name))
			var npc_entry: Dictionary = Player.npc[npc_name]
			if not npc_entry.has("tags"):
				npc_entry["tags"] = []
			if not npc_entry.has("num_tags"):
				npc_entry["num_tags"] = {}
			var npc_spec = npc_v[npc_name]
			if npc_spec is Dictionary:
				for cur_effect_name in npc_spec:
					match cur_effect_name:
						"tags":
							for tag in npc_spec[cur_effect_name]:
								var t := String(tag)
								if is_hero:
									# Hero 双向：标签进 player_tags，Hero 卡由末尾镜像统一覆盖
									Player.grant_tag(t)
								else:
									_grant_npc_tag(npc_entry, t)
									if t in ENTRY_TAGS:
										follow_keys.append(String(npc_name))
						"num_tags":
							for num_tag in npc_spec[cur_effect_name]:
								var ntag := String(num_tag)
								var nval = npc_spec[cur_effect_name][num_tag]
								if is_hero:
									Player.player_num_tags[ntag] = nval
								else:
									npc_entry["num_tags"][ntag] = nval
						"attrs":
							# 仅 Hero 支持 attrs（Hero 即主角，属性即 player 属性）。
							# 非 Hero 的属性改动无意义（NPC 不参与鉴定），静默忽略。
							if is_hero:
								for attr_name in npc_spec[cur_effect_name]:
									var change := int(npc_spec[cur_effect_name][attr_name])
									match str(attr_name):
										"int": Player.change_int(change)
										"app": Player.change_app(change)
										"str": Player.change_str(change)
										"bod": Player.change_bod(change)
						"name":
							# 仅 Hero 支持 name（主角改名）。非 Hero 忽略（NPC 名字不应被 effect 改）。
							if is_hero:
								Player.player_name = String(npc_spec[cur_effect_name])
						"equipment":
							# 仅 Hero 支持 equipment（主角装备双向同步）。非 Hero 忽略。
							if is_hero:
								for eq in npc_spec[cur_effect_name]:
									Player.equip_by_name(String(eq))

	# 入队 tag 落地（D-FOLLOW1）：本条 effect 里刚拿到「追随/跟随」的角色 → 补进手牌。
	# 放在 npc 分支之后：此时 Player.npc 条目已写完（tags 已在数组里），实时构造的卡才带得上新词条。
	for fk in follow_keys:
		_sync_follower_card(fk)

	# npc_num_tag_add：NPC 数值标签增量（法拉叶 love+1 等）。{npc: {tag: delta}}
	# 与 npc.num_tags 的绝对赋值互补：此处累加，保证 love 等可堆叠好感能逐次 +1。
	# Hero 走 player_num_tags（双向镜像），其余 NPC 写其 npc 条目 num_tags。
	var npc_num_tag_add_v: Variant = effect.get("npc_num_tag_add", null)
	if npc_num_tag_add_v is Dictionary:
		for npc_name in npc_num_tag_add_v:
			if not (npc_name is String):
				continue
			var spec: Variant = npc_num_tag_add_v[npc_name]
			if not (spec is Dictionary):
				continue
			var is_hero := (String(npc_name) == "Hero")
			if not Player.npc.has(npc_name):
				Player.npc[npc_name] = _load_preset_npc(String(npc_name))
			var entry: Dictionary = Player.npc[npc_name]
			if not entry.has("num_tags"):
				entry["num_tags"] = {}
			for ntag in spec:
				var tag := String(ntag)
				var delta := int(spec[ntag])
				if is_hero:
					Player.player_num_tags[tag] = int(Player.player_num_tags.get(tag, 0)) + delta
				else:
					entry["num_tags"][tag] = int(entry["num_tags"].get(tag, 0)) + delta

	# child_attrs / child_num_tag_add / child_tags（2026-10-11 孩子线）：
	# 以**唯一孩子**为目标的属性 / 可堆叠词条 / 普通词条通道。
	# 为什么单独一组键：剧情 effect 里没法写死 npc 键（孩子可能是 July 也可能是 Electra，
	# 由孤儿院三选一决定），而 npc 通道的 attrs 只认 Hero、slot_* 又要求有槽位上下文
	# （普通剧情没有 placed）→ 剧情里「child.int+1」这类成长无路可走。故补这一组：
	#   定位 = PlotImporter.child_key_of()（首个带 "child" 标签的 npc 条目），无孩子则安全跳过。
	# 属性落点与学校触发器的 slot_attrs 同口径：裸值累加、封顶 ATTR_MAX（NPC 通道上限 10）。
	var child_attrs_v: Variant = effect.get("child_attrs", null)
	var child_nta_v: Variant = effect.get("child_num_tag_add", null)
	var child_tags_v: Variant = effect.get("child_tags", null)
	if child_attrs_v is Dictionary or child_nta_v is Dictionary or child_tags_v is Array:
		var ck := PlotImporter.child_key_of()
		if ck == "":
			push_warning("EffectProcessor: child_* effect 触发但当前没有孩子（无带 child 标签的 npc），已跳过")
		else:
			var centry: Dictionary = Player.npc[ck]
			if child_attrs_v is Dictionary:
				for attr_name in child_attrs_v:
					var akey := str(attr_name)
					centry[akey] = mini(int(centry.get(akey, 0)) + int(child_attrs_v[attr_name]), Player.ATTR_MAX)
			if child_nta_v is Dictionary:
				if not centry.has("num_tags"):
					centry["num_tags"] = {}
				for ntag in child_nta_v:
					var nt := String(ntag)
					centry["num_tags"][nt] = int(centry["num_tags"].get(nt, 0)) + int(child_nta_v[ntag])
			if child_tags_v is Array:
				for tag in child_tags_v:
					_grant_npc_tag(centry, String(tag))

	# enqueue_talk（与同伴交流 GDD）：把对话 id 压入 NPC 的待聊队列 talk_queue，并自动给该
	# NPC 的「有话可说」num_tag +1（标记数与有效入队数一致，避免策划漏写导致状态不一致）。
	# {npc_name: {path,name} | [{path,name},...]}。npc 整体持久化，talk_queue 随档保存。
	var enqueue_talk_v: Variant = effect.get("enqueue_talk", null)
	if enqueue_talk_v is Dictionary:
		_apply_enqueue_talk(enqueue_talk_v)

	# slot_enqueue_talk（周游线，2026-10-10）：把待聊剧情入队到**槽位角色**的 talk_queue。
	# 与 enqueue_talk 同一套落地（talk_queue + 「有话可说」num_tag +1），区别只在目标不是写死的
	# npc 名，而是「当前流程里某槽位那张卡对应的 npc 条目」——读书时根本不知道读者是谁，
	# 只能等卡放进槽里才知道。{slot_name: {path,name} | [{path,name},...]}。
	# 用途：《雨国游记》after_read → 读书人「有话可说」，回家走「与同伴交流」播「雨国游记有话说」。
	var slot_enq_talk_v: Variant = effect.get("slot_enqueue_talk", null)
	if slot_enq_talk_v is Dictionary:
		_apply_slot_enqueue_talk(slot_enq_talk_v, context.get("placed", {}))

	# talk_hint（新手教程 GDD）：给 NPC 挂一条「引导对话」{path,name}，存条目 talk_hint。
	# 手牌上点该角色卡时播这条引导对话（播完即移除，只一次）。{npc_name: {path,name}}。
	var talk_hint_v: Variant = effect.get("talk_hint", null)
	if talk_hint_v is Dictionary:
		_apply_talk_hint(talk_hint_v)

	# child：孩子并入 npc 系统（统一带 "child" 标签）。child / name_child 共用 _add_child_npc，
	# 使孩子与普通 npc 走完全相同的创建/合并/存档/条件链路，不再有第二份平行数据。
	var child_v: Variant = effect.get("child", null)
	if child_v is Dictionary:
		for child_id in child_v:
			if not (child_id is String):
				continue
			var child_data: Variant = child_v[child_id]
			_add_child_npc(String(child_id), child_data if child_data is Dictionary else {})

	# remove_child（2026-09-26 孤儿院·归还孩子）：把当前收养的孩子还回去——
	# 删 Player.npc 中带 "child" tag 的条目，并把孩子卡从手牌移除。与 child/name_child 互逆。
	if bool(effect.get("remove_child", false)):
		_apply_remove_child()

	# 装备
	# 装备（三槽制，2026-10-24）：按 class 归槽、同类覆盖，不再是「往数组里追一个名字」。
	var equipment_v: Variant = effect.get("equipment", null)
	if equipment_v is Array:
		for eq in equipment_v:
			Player.equip_by_name(String(eq))

	# remove_tags：同时清流程字典与 player_tags（避免"加了又移除"残留）
	var remove_tags_v: Variant = effect.get("remove_tags", null)
	if remove_tags_v is Array:
		for tag in remove_tags_v:
			var t := String(tag)
			if flow_tags is Dictionary:
				flow_tags.erase(t)
			if t in Player.player_tags:
				Player.player_tags.erase(t)

	# remove_num_tags：清可堆叠词条键
	var remove_num_tags_v: Variant = effect.get("remove_num_tags", null)
	if remove_num_tags_v is Dictionary:
		for tag in remove_num_tags_v:
			Player.player_num_tags.erase(String(tag))

	# 疲惫（酒馆打工 GDD）：无「疲惫」→ 得「疲惫」；已有「疲惫」→ 得「疾病」。
	# 已有疲惫再疲劳（得疾病）→ 疲惫续命（覆盖式重置剩余回合）。
	#
	# 🔴 2026-10-25 归属修复：疲劳/疾病落**执行者**，不再一律落主角。
	#   旧实现只查 Player.player_tags ⇒ 酒馆打工不管谁去、都给主角加「疲惫/疾病」。
	#   目标定位：placed["执行者"] → 退而取第一张角色卡 → 都没有（纯剧情 effect）才回退玩家通道。
	#   Hero → player_tags（grant_tag 登记 turn）；NPC → 条目 tags（_grant_npc_tag 同口径，
	#   带 turn 的 tag 写 tag_turns，过天由 Player._on_day_changed 统一 tick）。
	if effect.has("fatigue") and bool(effect["fatigue"]):
		var target: CardData = _fatigue_target(context)
		if target == null:
			# 无执行者卡（纯剧情 effect）：沿用旧口径（流程字典 / player_tags）。
			var tired_p: bool = ("疲惫" in Player.player_tags) or (flow_tags is Dictionary and flow_tags.has("疲惫"))
			if flow_tags is Dictionary:
				flow_tags["疾病" if tired_p else "疲惫"] = true
			else:
				Player.grant_tag("疾病" if tired_p else "疲惫")
			if tired_p and ("疲惫" in Player.player_tags):
				Player.grant_tag("疲惫")
		elif _npc_key_of(target) == "Hero":
			var tired_h: bool = "疲惫" in Player.player_tags
			Player.grant_tag("疾病" if tired_h else "疲惫")
			if tired_h:
				Player.grant_tag("疲惫")
		else:
			var fkey := _npc_key_of(target)
			if not Player.npc.has(fkey):
				Player.npc[fkey] = _load_preset_npc(fkey)
			var fentry: Dictionary = Player.npc[fkey]
			var ftags_v: Variant = fentry.get("tags", [])
			var tired_n: bool = ftags_v is Array and ("疲惫" in ftags_v)
			_grant_npc_tag(fentry, "疾病" if tired_n else "疲惫")
			if tired_n:
				_grant_npc_tag(fentry, "疲惫")

	# name_child：阻塞型取名。先确保孩子 npc 条目已创建（含 child 标签 + cfg.tags，名字先填 default），
	# 再调用对话系统提供的回调弹窗；弹窗确认后由 dialogue_ui 把名字写回 Player.npc[id]["name"]。
	# 与 child effect 共用 _add_child_npc，避免重复逻辑。
	if effect.has("name_child"):
		var cb: Variant = context.get("on_name_child", null)
		if cb is Callable:
			var cfg: Dictionary = {}
			if effect["name_child"] is Dictionary:
				cfg = effect["name_child"]
			var cid: String = String(cfg.get("id", "adopted"))
			_add_child_npc(cid, {"name": cfg.get("default", ""), "tags": cfg.get("tags", [])})
			cb.call(cfg)
			blocked = true
		else:
			push_warning("EffectProcessor: name_child effect 需要 context.on_name_child 回调，当前调用方未提供，跳过")

	# achievement：解锁成就（成就 id 或 id 数组）。转发 AchievementManager.unlock，幂等。
	var ach_v: Variant = effect.get("achievement", null)
	if ach_v is String:
		AchievementManager.unlock(String(ach_v))
	elif ach_v is Array:
		for id in ach_v:
			AchievementManager.unlock(String(id))

	# slot_tags / slot_attrs（D-DOC9，2026-08-24）：对当前流程中某槽位的角色卡施加 tag / 属性增量。
	#   slot_tags: {slot_name: [tag, ...]}   slot_attrs: {slot_name: {attr: N}}
	# placed（从 context）= {slot_name: CardData}。CardData.id 对应 Player.npc 键名；
	#   主角卡（id=="Hero" 或 npc_key 为主角）→ tag 进 player_tags（或 flow_tags），attr 走 change_*。
	#   非 Hero NPC → 直接写其 npc 条目的 tags / int/app/str/bod 字段。
	var placed: Dictionary = context.get("placed", {})
	var slot_tags_v: Variant = effect.get("slot_tags", null)
	if slot_tags_v is Dictionary and not placed.is_empty():
		_apply_slot_tags(slot_tags_v, placed, flow_tags)
	var slot_attrs_v: Variant = effect.get("slot_attrs", null)
	if slot_attrs_v is Dictionary and not placed.is_empty():
		_apply_slot_attrs(slot_attrs_v, placed)

	# slot_remove_tags / slot_num_tags（D-DOC13 越狱）：移除槽位角色 tag / 槽位角色 num_tag 增量。
	# 与 slot_tags/slot_attrs 同一套 placed 定位（主角卡→player 通道，NPC→npc 条目）。
	var slot_remove_tags_v: Variant = effect.get("slot_remove_tags", null)
	if slot_remove_tags_v is Dictionary and not placed.is_empty():
		_apply_slot_remove_tags(slot_remove_tags_v, placed)
	var slot_num_tags_v: Variant = effect.get("slot_num_tags", null)
	if slot_num_tags_v is Dictionary and not placed.is_empty():
		_apply_slot_num_tags(slot_num_tags_v, placed)

	# inquiry_drawn（D-DOC14 打听池）：已抽打听事件 id 落地（随机不重复）。去重 append 进 Player.inquiry_drawn。
	var inquiry_drawn_v: Variant = effect.get("inquiry_drawn", null)
	if inquiry_drawn_v is Array:
		for id in inquiry_drawn_v:
			var sid := String(id)
			if sid != "" and not Player.inquiry_drawn.has(sid):
				Player.inquiry_drawn.append(sid)

	# trigger_consumed（D-DOC24 回合级触发器）：本回合已消耗卡 id 落地，形如 {触发id: [卡id...]}。
	# 去重 append 进 Player.trigger_consumed[触发id]——吸附/装槽时排除（已消耗槽位保持空位）；
	# 过天由 Player._on_day_changed 清空（下回合实例重建时全池重抽）。
	# 取代旧键 goods_sold（D-DOC23 专用单数组 → D-DOC24 通用化，2026-09-13）。
	var tc_v: Variant = effect.get("trigger_consumed", null)
	if tc_v is Dictionary:
		var tc: Dictionary = tc_v
		for tid in tc.keys():
			var lid := String(tid)
			var ids_v: Variant = tc[tid]
			if lid == "" or not (ids_v is Array):
				continue
			if not Player.trigger_consumed.has(lid):
				Player.trigger_consumed[lid] = []
			var bucket: Array = Player.trigger_consumed[lid]
			for id in (ids_v as Array):
				var cid := String(id)
				if cid != "" and not bucket.has(cid):
					bucket.append(cid)

	# news（报纸日刊 GDD）：剧情新闻入队。接受单个字典 {headline,body} 或字典数组，
	# 逐条 append 进 Player.pending_news（队尾），过天由 NewspaperGenerator 按序消费。
	var news_v: Variant = effect.get("news", null)
	if news_v is Dictionary:
		Player.pending_news.append((news_v as Dictionary).duplicate(true))
	elif news_v is Array:
		for n in news_v:
			if n is Dictionary:
				Player.pending_news.append((n as Dictionary).duplicate(true))

	# newspaper（新手教程报纸 GDD）：阻塞型弹报纸组件。值语法：
	#   {"newspaper": N} / {"newspaper": {"day": N}} → 读 time_events.json[N] 固定日刊；
	#   {"newspaper": {title,date,columns}} → 直接渲染。
	# 需要 context.on_newspaper 回调（dialogue_ui 提供），报纸 closed 后继续对话。
	#
	# 2026-10-14（教程首份报纸）：弹之前先 `_grant_newspaper` 落档 —— 教程第 1 天那份报纸是
	# **发给玩家的**（写当天快照 + 进收藏 + 授「报纸推出」），不是"弹一次就蒸发"。
	# 这样剧情播完后玩家真的"有"这份报纸，主 UI「报纸」按钮在第 1 天能回看它。
	var newspaper_v: Variant = effect.get("newspaper", null)
	if newspaper_v != null:
		var ncb: Variant = context.get("on_newspaper", null)
		if ncb is Callable:
			var paper: Dictionary = _newspaper_payload(newspaper_v)
			_grant_newspaper(paper)
			ncb.call(paper)
			blocked = true
		else:
			push_warning("EffectProcessor: newspaper effect 需要 context.on_newspaper 回调，当前调用方未提供，跳过")

	# add_to_hand（新手教程 GDD）：把人物卡加入主 UI 手牌 CardArea。["Hero","Sicourge"]。
	# Hero 用 Player.get_hero_card()（实时属性），NPC 用 CardRegistry 静态卡。
	var add_to_hand_v: Variant = effect.get("add_to_hand", null)
	if add_to_hand_v is Array:
		_apply_add_to_hand(add_to_hand_v)

	# clamp_attrs：天赋"平凡可贵"专用，本处理器故意不处理（由 selection 自行解析）。
	# 未知 key 同样静默忽略——保持向前兼容，便于特例标记存在。

	# 主角双向同步：所有 player_* 改动（含上方 npc["Hero"] 回写）已落定，
	# 统一镜像到 npc["Hero"] 成长字段，保证主角卡与全局始终一致。
	_mirror_player_to_hero()

	return blocked


## slot_tags 落地：对 placed 中各槽位角色卡施加 tag（D-DOC9）。
## CardData.id 对应 Player.npc 键名。主角卡（id=="Hero"）→ tag 进 player_tags / flow_tags。
## 非 Hero NPC → 写其 npc 条目的 tags 数组（去重）。
static func _apply_slot_tags(slot_tags: Dictionary, placed: Dictionary, flow_tags: Variant) -> void:
	for slot_name in slot_tags:
		var card: Variant = placed.get(String(slot_name), null)
		if not (card is CardData):
			continue
		var npc_key := String(card.id)
		var is_hero := (npc_key == "Hero")
		var tags_to_add: Array = slot_tags[slot_name] if slot_tags[slot_name] is Array else []
		if is_hero:
			for tag in tags_to_add:
				var t := String(tag)
				if flow_tags is Dictionary:
					flow_tags[t] = true
				else:
					Player.grant_tag(t)
		else:
			if not Player.npc.has(npc_key):
				Player.npc[npc_key] = _load_preset_npc(npc_key)
			var entry: Dictionary = Player.npc[npc_key]
			for tag in tags_to_add:
				_grant_npc_tag(entry, String(tag))


## slot_attrs 落地：对 placed 中各槽位角色卡施加属性增量（D-DOC9）。
## 主角卡 → 走 Player.change_*（增量）。非 Hero NPC → 直接改其 npc 条目的 int/app/str/bod 字段。
static func _apply_slot_attrs(slot_attrs: Dictionary, placed: Dictionary) -> void:
	for slot_name in slot_attrs:
		var card: Variant = placed.get(String(slot_name), null)
		if not (card is CardData):
			continue
		var npc_key := String(card.id)
		var is_hero := (npc_key == "Hero")
		var spec: Variant = slot_attrs[slot_name]
		if not (spec is Dictionary):
			continue
		if is_hero:
			for attr_name in spec:
				var change := int(spec[attr_name])
				match str(attr_name):
					"int": Player.change_int(change)
					"app": Player.change_app(change)
					"str": Player.change_str(change)
					"bod": Player.change_bod(change)
		else:
			if not Player.npc.has(npc_key):
				Player.npc[npc_key] = _load_preset_npc(npc_key)
			var entry: Dictionary = Player.npc[npc_key]
			for attr_name in spec:
				var change := int(spec[attr_name])
				var key := str(attr_name)
				# 裸值封顶 10（人类极限）：NPC 通道与主角通道同一上限。
				entry[key] = mini(int(entry.get(key, 0)) + change, Player.ATTR_MAX)


## 疲劳/疾病的目标卡（2026-10-25）：触发器流程里 = 「执行者」槽卡，其次第一张角色卡。
## 都没有（纯剧情 effect，context 无 placed）→ null，由调用方回退玩家通道。
static func _fatigue_target(context: Dictionary) -> CardData:
	var placed_v: Variant = context.get("placed", {})
	if not (placed_v is Dictionary):
		return null
	var placed: Dictionary = placed_v
	var first_v: Variant = placed.get("执行者", null)
	if first_v is CardData:
		return first_v
	for sn in placed:
		var c: Variant = placed[sn]
		if c is CardData and (c as CardData).card_type == "character":
			return c
	return null


## 从 CardData 解析对应的 npc 键（D-DOC13）：优先 id 精确命中；
## 否则按 display_name（中文名）反查 Player.npc 已有条目（剧情 effect 常用中文键）；
## 再否则回退 card.id（后续 _load_preset_npc 会做 name 兜底）。
static func _npc_key_of(card: CardData) -> String:
	if Player.npc.has(card.id):
		return card.id
	for key in Player.npc:
		var entry: Variant = Player.npc[key]
		if entry is Dictionary and str(entry.get("name", "")) == card.display_name:
			return String(key)
	return card.id


## slot_remove_tags 落地（D-DOC13）：移除槽位角色的 tag。
## 目标 NPC 不存在 / 无 tags 字段 → 安全跳过（不新增条目，满足「没有对应 tags 就不删」）。
## 主角卡（Hero）→ 从 player_tags 移除；非 Hero NPC → 从其 npc 条目 tags 数组移除。
static func _apply_slot_remove_tags(slot_remove_tags: Dictionary, placed: Dictionary) -> void:
	for slot_name in slot_remove_tags:
		var card: Variant = placed.get(String(slot_name), null)
		if not (card is CardData):
			continue
		var npc_key := _npc_key_of(card)
		var tags_to_remove: Array = slot_remove_tags[slot_name] if slot_remove_tags[slot_name] is Array else []
		if npc_key == "Hero":
			for tag in tags_to_remove:
				Player.player_tags.erase(String(tag))
		else:
			if not Player.npc.has(npc_key):
				continue
			var entry: Dictionary = Player.npc[npc_key]
			if not entry.has("tags"):
				continue
			var tags_arr: Array = entry["tags"]
			for tag in tags_to_remove:
				tags_arr.erase(String(tag))


## slot_num_tags 落地（D-DOC13）：槽位角色 num_tag 增量/赋值。
## spec 值语法：int=绝对赋值；{"add":N,"cap":M}=增量+封顶（与 num_tags 同语法）。
## 主角卡（Hero）→ player_num_tags；非 Hero NPC → 其 npc 条目 num_tags 字典。
static func _apply_slot_num_tags(slot_num_tags: Dictionary, placed: Dictionary) -> void:
	for slot_name in slot_num_tags:
		var card: Variant = placed.get(String(slot_name), null)
		if not (card is CardData):
			continue
		var npc_key := _npc_key_of(card)
		var spec: Variant = slot_num_tags[slot_name]
		if not (spec is Dictionary):
			continue
		if npc_key == "Hero":
			for tag in spec:
				_apply_num_tag_to(Player.player_num_tags, String(tag), spec[tag])
		else:
			if not Player.npc.has(npc_key):
				Player.npc[npc_key] = _load_preset_npc(npc_key)
			var entry: Dictionary = Player.npc[npc_key]
			if not entry.has("num_tags"):
				entry["num_tags"] = {}
			for tag in spec:
				_apply_num_tag_to(entry["num_tags"], String(tag), spec[tag])


## num_tag 单键落地：int 绝对赋值；{"add":N,"cap":M} 增量+封顶。
static func _apply_num_tag_to(target: Dictionary, tag: String, spec_v: Variant) -> void:
	if spec_v is Dictionary:
		var add := int(spec_v.get("add", 0))
		var cap_v: Variant = spec_v.get("cap", null)
		var cur := int(target.get(tag, 0))
		var new_val := cur + add
		if cap_v != null:
			new_val = mini(new_val, int(cap_v))
		target[tag] = new_val
	else:
		target[tag] = int(spec_v)


## 把 Player 实时数据镜像到主角卡 npc["Hero"]，覆盖成长字段：
## name/int/app/str/bod/equipment/tags/num_tags。静态字段（image/description/gender）保持原样。
## Hero 条目不存在则跳过。用 duplicate 避免引用共享导致的隐式耦合，保证 hero 是独立副本但值一致。
## 触发：每次 EffectProcessor.apply 末尾自动调用，使主角卡与全局始终一致。
static func _mirror_player_to_hero() -> void:
	var card: Variant = Player.npc.get("Hero", null)
	if not (card is Dictionary):
		return
	card["name"] = Player.player_name
	card["int"] = Player.player_int
	card["app"] = Player.player_app
	card["str"] = Player.player_str
	card["bod"] = Player.player_bod
	card["equipment"] = Player.player_equipment.duplicate()
	card["tags"] = Player.player_tags.duplicate()
	card["num_tags"] = Player.player_num_tags.duplicate()


## 给 NPC 条目加一个 tag（去重），并按 tags.json 的 turn 登记 / 刷新剩余回合。
## NPC 的计时存在条目自身的 tag_turns 字典，随 npc 白名单持久化；
## 到期由 Player._on_day_changed 遍历 npc 统一 tick（与玩家同一套机制）。
## 与 Player.grant_tag 对应：保证 NPC 带 turn tag 同样正确到期、不污染玩家状态。
static func _grant_npc_tag(entry: Dictionary, tag: String) -> void:
	if not entry.has("tags"):
		entry["tags"] = []
	if not (tag in entry["tags"]):
		entry["tags"].append(tag)
	var t := TagRegistry.get_turn(tag)
	if t > 0:
		if not entry.has("tag_turns"):
			entry["tag_turns"] = {}
		entry["tag_turns"][tag] = t
	elif entry.has("tag_turns"):
		entry["tag_turns"].erase(tag)


## 把孩子落进 npc 系统：确保 Player.npc[child_id] 存在（无则从 characters.json 加载预设，
## 再降级空壳），强制带 "child" 标签，并合并 name/tags/num_tags。
## child effect 与 name_child effect 共用此入口，使孩子成为可普通操作的 npc
## （条件判定走 npc_has_tags、人物面板走 character_panel、存档走 npc 白名单），
## 彻底消除原先 Player.child 第二份平行数据 + 手动同步的问题。
static func _add_child_npc(child_id: String, child_data: Dictionary) -> void:
	if not Player.npc.has(child_id):
		Player.npc[child_id] = _load_preset_npc(child_id)
	var entry: Dictionary = Player.npc[child_id]
	if not entry.has("tags"):
		entry["tags"] = []
	if not entry.has("num_tags"):
		entry["num_tags"] = {}
	# child 标签强制排最前（child_npc_test 16.2 契约：{child.tags} 渲染 child 在首位）。
	# 预设（characters.json）里的 child 可能不在首位，这里统一擦除后置顶。
	entry["tags"].erase("child")
	entry["tags"].insert(0, "child")
	if child_data.has("name"):
		entry["name"] = child_data["name"]
	for tag in child_data.get("tags", []):
		_grant_npc_tag(entry, String(tag))
	for num_tag in child_data.get("num_tags", {}):
		entry["num_tags"][String(num_tag)] = child_data["num_tags"][num_tag]


## 从 characters.json 加载预设 NPC 的完整数据（深拷贝，避免污染缓存）。
## 键优先按 npc_key 精确匹配（英文键，如 "Falayee"）；未命中时按各预设的 name 字段
## （中文名，如 "法拉叶"）反查——剧情/触发器常用中文名指代角色，name 字段的初衷即
## 让中文名也能解析到同一对象，避免「中文键查不到 → 降级空壳（无 name/image/attrs）」。
## 仍未找到则返回空壳 {tags:[], num_tags:{}}，保证后续 tags/num_tags 字段可用。
## 查 characters.json 预设 NPC（**安静版**，D-HAND3，2026-10-23）。
##
## 与 `_load_preset_npc` 的唯一区别：找不到时返回 `{}`、**不 push_warning**、不降级空壳。
## 谁在用：`main_ui.ensure_npc_static_fields()` 给 npc 条目补静态外观字段 ——
## 「条目键不在 characters.json」（剧情自建角色、中文键别名）是**正常情况**，不该刷警告。
static func preset_npc_quiet(npc_key: String) -> Dictionary:
	_ensure_characters_cache()
	var preset: Variant = _characters_cache.get(npc_key, null)
	if preset is Dictionary:
		return preset as Dictionary
	for key in _characters_cache:
		var entry: Variant = _characters_cache[key]
		if entry is Dictionary and str((entry as Dictionary).get("name", "")) == npc_key:
			return entry as Dictionary
	return {}


static func _load_preset_npc(npc_key: String) -> Dictionary:
	_ensure_characters_cache()
	var preset: Variant = _characters_cache.get(npc_key, null)
	if preset is Dictionary:
		return (preset as Dictionary).duplicate(true)
	for key in _characters_cache:
		var entry: Variant = _characters_cache[key]
		if entry is Dictionary and str(entry.get("name", "")) == npc_key:
			return (entry as Dictionary).duplicate(true)
	push_warning("EffectProcessor: characters.json 中未找到预设 NPC '%s'，降级为空壳" % npc_key)
	return {"tags": [], "num_tags": {}}


## 惰性加载 characters.json 到静态缓存。
static func _ensure_characters_cache() -> void:
	if not _characters_cache.is_empty():
		return
	var f := FileAccess.open(CHARACTERS_PATH, FileAccess.READ)
	if f == null:
		push_warning("EffectProcessor: 找不到 characters.json（%s），预设 NPC 加载降级为空壳" % CHARACTERS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_characters_cache = parsed
	else:
		push_warning("EffectProcessor: characters.json 解析失败（非字典）")


## newspaper effect 载荷解析：int/float/数字串 → 固定日刊 generate_fixed(day)；
## {day:N} → 同上；含 columns 的字典 → 原样返回。day 非法时回落当天。
static func _newspaper_payload(spec: Variant) -> Dictionary:
	if spec is Dictionary and (spec as Dictionary).has("columns"):
		return (spec as Dictionary).duplicate(true)
	var day := -1
	if spec is int:
		day = int(spec)
	elif spec is float:
		day = int(spec)
	elif spec is String and (spec as String).is_valid_int():
		day = int(spec)
	elif spec is Dictionary:
		day = int((spec as Dictionary).get("day", -1))
	if day <= 0:
		day = int(Player.time)
	return NewspaperGenerator.generate_fixed(day)


## 把一份报纸真正交到玩家手里（2026-10-14 教程首份报纸 GDD）。
## 弹窗只是"看一眼"，本函数负责"拥有"，三件事：
##   1. 授予「报纸推出」（幂等）——剧院支线「与经理交涉」以它为 show_when 门控；
##   2. 追加进 `Player.player_stuff` 收藏留档，id 规则与 `main_ui._spawn_daily_newspaper`
##      保持一致（`daily_<天>`），同 id 不重复追加（读档重播剧情不会堆出第二份）；
##   3. 写 `Player.daily_newspaper` 当天快照 —— **仅当这份就是今天的**，否则第 N 天的
##      回看会被别的天顶掉（剧情里补发历史报纸时尤其要注意）。
static func _grant_newspaper(paper: Dictionary) -> void:
	if paper.is_empty():
		return
	if not Player.player_has_tags(["报纸推出"]):
		Player.grant_tag("报纸推出")
	var day: int = _newspaper_day(paper)
	var nid := "daily_%d" % day
	var dup := false
	for it in Player.player_stuff:
		if it is Dictionary and String((it as Dictionary).get("id", "")) == nid:
			dup = true
			break
	if not dup:
		Player.player_stuff.append({
			"type": "newspaper",
			"id": nid,
			"title": paper.get("title", ""),
			"date": paper.get("date", ""),
			"columns": paper.get("columns", []),
		})
	if day == int(Player.time):
		Player.daily_newspaper = paper.duplicate(true)


## 从报纸快照的 `date` 字段（形如「第 3 天」）里取天数；取不出则回落当天。
static func _newspaper_day(paper: Dictionary) -> int:
	var digits := ""
	for ch in String(paper.get("date", "")):
		if String(ch).is_valid_int():
			digits += String(ch)
	return int(digits) if digits != "" else int(Player.time)


## add_to_hand 落地（新手教程 GDD）：把人物卡加入主 UI 手牌。
## 卡牌区未注册（纯代码调试场景）→ 安全跳过。
## 取卡优先级（2026-09-26 孤儿院补）：Hero 实时卡 → **Player.npc 已有条目则按条目实时构造**
## → 否则走 CardRegistry 静态预设。中间一档是为孩子卡补的：孩子进手牌后名字可能被
## 取名窗改过、属性会随学校送学增长，静态预设卡显示不出这些变化。
static func _apply_add_to_hand(ids: Array) -> void:
	var ca: CardArea = TriggerManager.get_card_area()
	for cid in ids:
		var cid_s := String(cid)
		var card := hand_card_for_id(cid_s)
		if card == null:
			continue
		if ca != null:
			# 卡牌区在场：由它负责视图 + 记账（add_card 内部会写 Player.hand）。
			# 这里**不能**再调 Player.add_hand_card —— 「可堆叠」卡会被记两遍。
			ca.add_card(card)
		else:
			# D-HAND1：卡牌区不在场（纯剧情场景 / 无主 UI 的流程）时，旧实现直接 return，
			# 等于把这张卡永久丢掉。现在照样落账本，等玩家回到带手牌的场景自动补发。
			Player.add_hand_card(card)


## 入队 tag → 手牌（D-FOLLOW1）。由 `apply()` 在 npc 分支之后调用，幂等。
##
## ⚠️ 卡 id 用 **npc 条目的键**（可能与 characters.json 的英文键不同，如阿尔温存成中文键），
##    与孩子卡同一口径 —— 只有这样才能让 `live_card_for_id` 命中 `Player.npc` 的实时条目；
##    若换成英文键，实时源查不到会回落到 `CardRegistry` 的**共享静态实例**（只读、改了污染全工程）。
## ⚠️ 已在手牌就什么都不做：否则「同一条 effect 重播 / 读档续播」会把卡加两遍。
## ⚠️ 本函数**只在授予入队 tag 的那一次调用**，不做全局扫描 —— 扫 `Player.npc` 会把「正躺在
##    触发器卡槽里」的同伴复活回手牌（D-HAND2 踩过同一个坑）。
static func _sync_follower_card(npc_key: String) -> void:
	if npc_key == "" or npc_key == "Hero":
		return
	if Player.hand_has(npc_key):
		return
	_apply_add_to_hand([npc_key])


## 手牌「兑现」：**按 id 重建一张卡的唯一入口**（D-HAND1）。
##
## 谁在用：① `add_to_hand` effect 落地；② 切场景 / 读档后 `main_ui._restore_hand()`
## 按 `Player.hand` 账本重建手牌。两边必须走同一张地图，否则会出现「剧情给的卡」和
## 「恢复出来的卡」不是同一张（比如一个读 npc 实时数据、一个读静态预设）。
## 取卡优先级： Hero → `Player.npc` 已有条目（实时构造）→ `CardRegistry` 静态预设。
## 中间一档是为孩子卡补的：孩子进手牌后名字可能被取名窗改过、属性会随学校送学增长，
## 静态预设卡显示不出这些变化。
static func hand_card_for_id(cid: String) -> CardData:
	var live := live_card_for_id(cid)
	if live != null:
		return live
	return CardRegistry.get_card(cid)


## 按 id 取**实时源**的卡实例（主角 / `Player.npc` 条目）；查不到返回 null —— **不回落注册表**。
##
## 与 `hand_card_for_id` 的唯一区别就在「查不到」这一支：后者回落 `CardRegistry` 的
## **共享静态实例**。共享实例只能读、不能改 —— 改了会污染注册表，把所有引用它的地方一起带坏。
## 所以凡是要把一张**手牌卡实例整个换掉**的场景（CardArea 方案 B 的「按源重建」），
## 必须走本函数：拿不到实时源就保持原实例（快照兜底），绝不换成注册表共享实例。
## 每次调用都是**新实例**（`Player.get_hero_card` / `_npc_entry_card` 都现造），可安全替换。
static func live_card_for_id(cid: String) -> CardData:
	if cid == "":
		return null
	if cid == "Hero":
		return Player.get_hero_card()
	if Player.npc.has(cid):
		return _npc_entry_card(cid)
	return null


## 按账本条目兑现一张卡。
##
## ⚠️ 为什么优先走实时源、把快照当兜底：账本里存的是**进手牌那一刻**的数据快照。若照抄快照，
##    npc 被改名（取名窗）、孩子属性成长、装备数值调整都不会反映到手牌上。所以凡能通过
##    id 重建的（主角 / npc 条目 / 注册表），一律当场重建；只有那些**注册表里查不到**的卡
##    —— 典型是 `CardData.from_book` 造出来的书卡（books.json 不入注册表）—— 才用快照。
static func resolve_hand_entry(entry: Variant) -> CardData:
	if not (entry is Dictionary):
		return null
	var d := entry as Dictionary
	var cid := String(d.get("id", ""))
	var live := hand_card_for_id(cid)
	if live != null:
		return live
	if cid == "" and String(d.get("display_name", "")) == "":
		return null
	return CardData.from_data(d)


## 由 Player.npc 条目**实时**构造 CardData（2026-09-26 孤儿院）。
## 与 CardRegistry.get_card（characters.json 静态预设）的区别：这里取运行时数据，
## 改过的 name、累积的 attrs/tags 都会正确反映。npc 条目字段（name/int/app/str/bod/
## tags/image/description）与 characters.json 同构，故直接复用 CardData.from_character。
static func _npc_entry_card(key: String) -> CardData:
	var entry: Variant = Player.npc.get(key, null)
	if not (entry is Dictionary):
		return null
	return CardData.from_character(key, entry as Dictionary)


## remove_child 落地（2026-09-26 孤儿院·归还孩子）：移除玩家当前收养的孩子。
## 与 child / name_child（_add_child_npc）互为逆操作：删除 Player.npc 中所有带
## "child" tag 的条目，并把对应的孩子卡从主 UI 手牌移除。单孩子设定下通常命中 0 或 1 条，
## 无孩子时安全跳过（不报错、不改任何数据）。
## 手牌匹配用「卡 id == npc 键」——孩子卡由 _npc_entry_card 以 npc 键为 id 构造，
## 因此玩家改过名字也能正确命中。
static func _apply_remove_child() -> void:
	var keys: Array = []
	for key in Player.npc.keys():
		var entry: Variant = Player.npc[key]
		if entry is Dictionary and ("child" in (entry as Dictionary).get("tags", [])):
			keys.append(String(key))
	if keys.is_empty():
		return
	var ca: CardArea = TriggerManager.get_card_area()
	if ca != null:
		for c in ca.get_cards():
			if c != null and String(c.id) in keys:
				ca.remove_card(c)
	# 槽位里那张也要抹掉：玩家是**把孩子放在卡槽里**才触发归还的，卡根本不在手牌区。
	# 只删 npc 条目不删槽卡 → 关窗时按「来自手牌」归还，`resolve_hand_entry` 回落
	# CardRegistry 静态预设 → 手牌里复活一张没有主人的孩子卡。
	var popup: TriggerPopup = TriggerManager.get_active_trigger_popup()
	if popup != null:
		popup.purge_cards(keys)
	for k in keys:
		Player.npc.erase(k)


## enqueue_talk 落地（与同伴交流 GDD）：把对话 id 追加进 NPC 的待聊队列 talk_queue，
## 并按有效入队数给该 NPC 的「有话可说」num_tag +1。
## 对话 id 沿用 plot 键格式 {path, name}（剧情散落各文件，播放时走 PlotImporter.add_plot）。
## npc_key 支持英文键 / 中文名（走 _load_preset_npc 兜底解析，与其它 npc effect 一致）。
static func _apply_enqueue_talk(spec: Dictionary) -> void:
	for npc_name in spec:
		if not (npc_name is String):
			continue
		if not Player.npc.has(npc_name):
			Player.npc[npc_name] = _load_preset_npc(String(npc_name))
		var entry: Dictionary = Player.npc[npc_name]
		if not entry.has("talk_queue"):
			entry["talk_queue"] = []
		if not entry.has("num_tags"):
			entry["num_tags"] = {}
		# 归一化为对话 id 数组（单个 dict / dict 数组均可），仅接受有效 {path,name}
		var payload: Variant = spec[npc_name]
		var plots: Array = []
		if payload is Array:
			for p in payload:
				if p is Dictionary:
					plots.append((p as Dictionary).duplicate(true))
		elif payload is Dictionary:
			plots.append((payload as Dictionary).duplicate(true))
		for p in plots:
			entry["talk_queue"].append(p)
		if plots.size() > 0:
			# Hero（主角）的「有话可说」落 Player.player_num_tags（与门控 _performer_num_tag、
			# _mirror_player_to_hero 口径一致，避免被 mirror 覆盖丢失）；NPC 落条目 num_tags。
			if String(npc_name) == "Hero":
				Player.player_num_tags["有话可说"] = int(Player.player_num_tags.get("有话可说", 0)) + plots.size()
			else:
				entry["num_tags"]["有话可说"] = int(entry["num_tags"].get("有话可说", 0)) + plots.size()


## slot_enqueue_talk 落地（周游线，2026-10-10）：按**槽位**入队待聊剧情。
## 槽位卡 → npc 键走 _npc_key_of（id 精确命中优先、中文名反查兜底），再复用 _apply_enqueue_talk，
## 保证 talk_queue /「有话可说」计数与 enqueue_talk 完全同一口径（不会出现第二套计数规则）。
## 槽位空 / 不是 CardData → 安全跳过（读书时槽里必然有执行者，但别让数据错误炸在这）。
static func _apply_slot_enqueue_talk(slot_enqueue_talk: Dictionary, placed: Dictionary) -> void:
	if placed.is_empty():
		return
	for slot_name in slot_enqueue_talk:
		var card: Variant = placed.get(String(slot_name), null)
		if not (card is CardData):
			continue
		var npc_key := _npc_key_of(card)
		if npc_key == "":
			continue
		_apply_enqueue_talk({npc_key: slot_enqueue_talk[slot_name]})


## talk_hint 落地（新手教程 GDD）：给 NPC 条目挂一条「引导对话」{path,name}。
## 手牌上点该角色卡时播这条引导对话（播完即移除，只一次）。npc 键沿用 _load_preset_npc 兜底。
static func _apply_talk_hint(spec: Dictionary) -> void:
	for npc_name in spec:
		if not (npc_name is String):
			continue
		if not Player.npc.has(npc_name):
			Player.npc[npc_name] = _load_preset_npc(String(npc_name))
		var entry: Dictionary = Player.npc[npc_name]
		var hint: Variant = spec[npc_name]
		if hint is Dictionary:
			entry["talk_hint"] = (hint as Dictionary).duplicate(true)
