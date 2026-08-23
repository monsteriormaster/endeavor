"""
剧情管理器 - 负责加载JSON对话数据并控制对话流程
使用方法：
调用 add_plot(file_path:String, plot_name:String) 加载特定剧情 
依赖：
DialogueGroup 和 Dialogue 资源类
dialogue_ui.tscn 场景文件
"""
extends Node

const UI = 'res://components/dialogue_ui.tscn'

func add_plot(file_path:String, plot_name:String):
	if Player.is_dialogue_exist:
		return
	Player.is_dialogue_exist = true	
	var plot =find_plot(load_json(file_path),plot_name)
	execute_dialogue(plot)
	

func load_json(file_path: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	var reply = JSON.parse_string(file.get_as_text())
	file.close()
	return reply


func find_plot(all_plot, plot_name:String):
	return all_plot.get(plot_name, {})
	
	
func execute_dialogue(plot):
	var dialogue_scene = load(UI)
	var dialogue_ui = dialogue_scene.instantiate()

	# 交给覆盖层管理器（D-UI6）。对白挂在专用 CanvasLayer 上，不再直接塞进 root：
	#   - 层级确定（业务覆盖层，压住地图与 HUD，但在教学层之下）
	#   - Esc 不关对白（esc_closes=false），对白要走自己的推进/结束流程
	#   - 切场景时自动清理，不会留在下一幕
	# 这里保持 deferred：add_plot 经常被 scene/_ready（如 guide 的开场）串到调用，
	# 此刻同步挂载会撞上 "Parent node is busy setting up children"。
	OverlayRoot.push_overlay.call_deferred(dialogue_ui, {
		"modal": true,
		"esc_closes": false,
	})
	
	var dialogue_group = DialogueGroup.new()
	dialogue_group.layout = String(plot.get("layout", "default"))
	
	for i in range(1000):  
		var key = str(i) + "th"
		if plot.has(key):
			var dialogue_data = plot[key]
			
			var dialogue = Dialogue.new()
			dialogue.character_name = dialogue_data.get("name", "")
			dialogue.content = dialogue_data.get("text", "")
			dialogue.is_option = dialogue_data.get("is_option",false)
			dialogue.next =dialogue_data.get("next",-1)
			dialogue.effect = dialogue_data.get("effect",{})
			# 条件跳转 nexts：[{"condition": <条件>, "next": <int>}]，首个命中条件的 next 生效
			var raw_nexts = dialogue_data.get("nexts", [])
			dialogue.nexts = []
			for ne in raw_nexts:
				dialogue.nexts.append({
					"condition": ne.get("condition", {}),
					"next": ne.get("next", -1)
				})
			var ctx: Variant = dialogue_data.get("context", {})
			if ctx is Dictionary:
				dialogue.context = ctx
			dialogue.options = []
			if dialogue_data.has("options"):
				for option_data in dialogue_data["options"]:
					var option = {
						"text": option_data.get("text", ""),
						"next": option_data.get("next", -1),
						"effect": option_data.get("effect", {}),
						"condition": option_data.get("condition", {})
					}
					option['is_ava'] = deal_condition(option["condition"])
					dialogue.options.append(option)
						
			dialogue_group.dialogue_list.append(dialogue)
		else:
			break

	# 同样 deferred：保证 _ready 跑完、@export 节点就位再调用。
	dialogue_ui.show_dialogue_group.call_deferred(dialogue_group)
	

func deal_condition(condition)-> bool:
	if condition == {}: 
		return true
	else:
		if sentence_condition(condition):
			return true	
	return false	
		

func sentence_condition(condition)-> bool:
	
	if "money" in condition:
		var money_condition = condition.money
		var left = money_condition.get("left", 0)
		var right = money_condition.get("right", 9999999)
		
		# 检查玩家金钱是否在[left, right]范围内
		if Player.player_money < left or Player.player_money > right:
			return false
	
	if "tags" in condition:
		var tags = condition.tags
		
		# 检查玩家是否拥有指定标签
		if not Player.player_has_tags(tags, 1):
			return false
	
	if "num_tags" in condition:
		var num_tags = condition.num_tags
		for num_tag in num_tags:
			if not Player.player_meet_num_tag(num_tags[num_tag].name,num_tags[num_tag].left,num_tags[num_tag].right):
				return false
	
	if "npc" in condition:
		var npc_conditions = condition.npc
		
		for npc_name in npc_conditions:
			var npc_condition = npc_conditions[npc_name]
			var tags = npc_condition.get("tags", [])
			var num_tags = npc_condition.get("num_tags", {})
			# 检查NPC是否拥有指定标签
			if not Player.npc_has_tags(npc_name, tags, 1):
				return false
			
			for num_tag_name in num_tags:
				if not Player.npc_meet_num_tag(num_tags[num_tag_name].name,npc_name,num_tags[num_tag_name].left,num_tags[num_tag_name].right):
					return false

	if "attrs" in condition:
		var attrs = condition.attrs
		for attr_name in attrs:
			var attr_cond = attrs[attr_name]
			for compare in attr_cond:
				var value := int(attr_cond[compare])
				if not Player.player_attr_meet(attr_name, compare, value):
					return false

	# D-NOB：贵族等级门控。写法同 attrs：{"nobility": {">": 2}} / {"=": 3} / {"<": 4}
	# 语义与 player_attr_meet 一致：">"=≥(noble>=value)，"<"=≤，"="=相等。
	if "nobility" in condition:
		var noble_cond = condition.nobility
		var noble := int(Player.nobility)
		for compare in noble_cond:
			var value := int(noble_cond[compare])
			match compare:
				"=":
					if noble != value:
						return false
				">":
					if noble < value:
						return false
				"<":
					if noble > value:
						return false

	if "child" in condition:
		var child_conditions = condition.child
		for child_id in child_conditions:
			var child_condition = child_conditions[child_id]
			var tags = child_condition.get("tags", [])
			var num_tags = child_condition.get("num_tags", {})
			var matched := false
			if child_id == "*" or child_id == "":
				for cid in Player.npc.keys():
					if _npc_is_child(cid) and Player.npc_has_tags(cid, tags, 1) and _npc_meet_num_tag_for(cid, num_tags):
						matched = true
						break
			elif Player.npc.has(child_id) and _npc_is_child(child_id):
				if Player.npc_has_tags(child_id, tags, 1) and _npc_meet_num_tag_for(child_id, num_tags):
					matched = true
			if not matched:
				return false

	return true


## 孩子判定辅助：指定 npc 条目是否带 "child" 标签（孩子已并入 npc 系统）。
static func _npc_is_child(cid: String) -> bool:
	var entry: Variant = Player.npc.get(cid, null)
	return entry is Dictionary and "child" in entry.get("tags", [])


## 孩子数值标签区间判定：检查指定孩子 npc 的 num_tags 是否全部落在 [left, right]。
static func _npc_meet_num_tag_for(cid: String, num_tags: Dictionary) -> bool:
	for nt_name in num_tags:
		var spec = num_tags[nt_name]
		var name = spec.get("name", nt_name)
		var left = int(spec.get("left", 0))
		var right = int(spec.get("right", 9999999))
		if not Player.npc_meet_num_tag(name, cid, left, right):
			return false
	return true


# ============================================================
#  按键名播放剧情（D-C2 / 亲历鉴定「入剧情」）
# ============================================================

## 对话框键名 → 剧情文件路径 的注册表（数据驱动，集中配置）。
## 位于 resoures/plot/dialogue_registry.json，结构 {"剧情键名": "res://...json路径"}。
## 设计意图：触发器 harvest.dialogue 只写「键名」，由本注册表解析到具体文件，
## 实现「绝大部分剧情播放可通过配置 JSON 完成」。
var _dialogue_registry: Dictionary = {}


## 按对话键名播放剧情（D-C2）。键名取自触发器 harvest.dialogue / fail_harvest.dialogue。
## 未注册 / 指向文件不存在 → 安全 no-op（仅 push_warning），不报错不崩溃，
## 便于尚未配置剧情时照常推进（如 demo 阶段很多 dialogue 键仅占位）。
func play_by_key(plot_key: String) -> void:
	if plot_key == "":
		return
	_ensure_registry()
	var path: Variant = _dialogue_registry.get(plot_key, null)
	if path == null or not (path is String):
		push_warning("PlotImporter: 未注册剧情键 '%s'，跳过播放（如需播放请在 dialogue_registry.json 登记）" % plot_key)
		return
	if not ResourceLoader.exists(path):
		push_warning("PlotImporter: 剧情键 '%s' 指向文件不存在：%s" % [plot_key, path])
		return
	add_plot(path, plot_key)


## 惰性加载注册表（首次使用时读，之后缓存）。
func _ensure_registry() -> void:
	if not _dialogue_registry.is_empty():
		return
	var f := FileAccess.open("res://resoures/plot/dialogue_registry.json", FileAccess.READ)
	if f == null:
		push_warning("PlotImporter: 找不到 dialogue_registry.json（res://resoures/plot/dialogue_registry.json），剧情键播放将全部 no-op")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_dialogue_registry = parsed
	else:
		push_warning("PlotImporter: dialogue_registry.json 解析失败（非字典）")
