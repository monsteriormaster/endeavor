"""
鉴定处理器 - 负责加载JSON鉴定配置并执行鉴定流程

使用方法：
    CheckProcessor.run_check(file_path, check_name)
    例如：
    CheckProcessor.run_check("res://resoures/checks/sample_check.json", "盗窃判定")

JSON 配置格式见 resoures/checks/sample_check.json

依赖：
    check_ui.tscn 鉴定界面
    Player 单例（属性、词条、物品、装备）
    PlotImporter 单例（分支触发剧情）
    EventSignal 单例
"""

extends Node

signal check_completed(result: Dictionary)

const CHECK_UI_PATH = "res://components/check_ui.tscn"

## 属性名 -> Player 变量名
const ATTR_MAP = {
	"int": "player_int",
	"app": "player_app",
	"str": "player_str",
	"bod": "player_bod",
	"edu": "player_edu",
}

## 属性名 -> 中文显示
const ATTR_DISPLAY = {
	"int": "智力",
	"app": "魅力",
	"str": "力量",
	"bod": "体魄",
	"edu": "教育",
}


# ============================================================
#  公共 API
# ============================================================

## 待处理队列：鉴定进行中再次 run_check 时入队，前一次结算后自动续跑（D-C6）。
## 元素为 [file_path, check_name]。
var _pending_checks: Array = []

## 执行鉴定。fire-and-forget，与 PlotImporter.add_plot 用法一致。
## 进行中再次调用不会静默丢失，而是进入队列等前一个结算完再跑（D-C6）。
func run_check(file_path: String, check_name: String) -> void:
	if Player.is_check_exist:
		_pending_checks.append([file_path, check_name])
		return
	_start_check(file_path, check_name)


## 真正启动一次鉴定（置状态 → 加载 → 校验 → 展示）。
func _start_check(file_path: String, check_name: String) -> void:
	Player.is_check_exist = true

	var check_data := _load_check(file_path, check_name)
	if check_data.is_empty():
		push_error("鉴定处理器：未找到鉴定 '%s'（文件：%s）" % [check_name, file_path])
		_finish_check()
		return

	# D-C5：branches 必须含 success 与 failure，缺失即视为配置错误并中止（不再静默吞掉）。
	if not _validate_branches(check_name, check_data):
		_finish_check()
		return

	var resolved := _resolve_check(check_data)
	_show_check_ui(check_data, resolved)


## D-C5：校验 branches 至少含 success + failure（大成功/大失败可缺省，结算时回退）。
func _validate_branches(check_name: String, check_data: Dictionary) -> bool:
	var branches: Variant = check_data.get("branches", null)
	if not (branches is Dictionary):
		push_error("鉴定处理器：'%s' 缺少 branches（必须含 success 与 failure）" % check_name)
		return false
	if not ("success" in branches):
		push_error("鉴定处理器：'%s' 的 branches 缺少 success 分支" % check_name)
		return false
	if not ("failure" in branches):
		push_error("鉴定处理器：'%s' 的 branches 缺少 failure 分支" % check_name)
		return false
	return true


## 一次鉴定彻底结束：清状态，并续跑队列中的下一个（D-C6）。
func _finish_check() -> void:
	Player.is_check_exist = false
	if not _pending_checks.is_empty():
		var next: Array = _pending_checks.pop_front()
		_start_check(next[0], next[1])


# ============================================================
#  加载
# ============================================================

func _load_check(file_path: String, check_name: String) -> Dictionary:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("鉴定处理器：无法打开文件 %s" % file_path)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data.get(check_name, {})


# ============================================================
#  鉴定结算
# ============================================================

## 计算鉴定的全部数值，返回 resolved 字典
func _resolve_check(check_data: Dictionary) -> Dictionary:
	# 1. 骰面 x = 加权平均（向下取整，至少 1）
	var attrs: Dictionary = check_data.get("attrs", {})
	var x := _calc_x(attrs)

	# 2. 难度 Y
	var difficulty := int(check_data.get("difficulty", 1))

	# 3. 加成（加在掷骰结果上，不加在 x 上）
	var modifiers_config: Array = check_data.get("modifiers", [])
	var active_modifiers := _get_active_modifiers(modifiers_config)
	var modifier_total := 0
	for mod in active_modifiers:
		modifier_total += int(mod["bonus"])
	# D-DOC17（2026-08-26）：玩家装备/持有物的 check_bonus（任意鉴定结果+1，如"精心磨制的小刀"）。
	# ⚠️ 装备是三槽字典，必须取**值**（equipment_names）；直接喂字典会把槽位名当装备名查。
	modifier_total += CardRegistry.total_check_bonus(Player.equipment_names())

	# 4. 掷骰 1dx
	var roll := _roll_dice(x)

	# 5. 最终值 = 骰子 + 加成
	var final_value := roll + modifier_total

	# 6. 成功等级
	var margin := final_value - difficulty
	var result_level := _determine_result_level(check_data, margin)

	# 7. 是否可能成功（x + 加成上限 < 难度 时为不可能）
	var max_possible := x + modifier_total
	var impossible := max_possible < difficulty

	return {
		"x": x,
		"difficulty": difficulty,
		"roll": roll,
		"modifiers": active_modifiers,
		"modifier_total": modifier_total,
		"final": final_value,
		"margin": margin,
		"result_level": result_level,
		"impossible": impossible,
		"attrs": attrs,
	}


## 骰面 x = (Σ 属性×权重) / (Σ 权重)，向下取整，至少 1
func _calc_x(attrs: Dictionary) -> int:
	# 骰面吃 tag/装备 bonus：生效值 = 玩家裸值 + 已持有 tag 的 bonus + 装备 bonus
	#（与 check modifiers 简单相加；同一 tag 勿在 bonus 与 modifiers 两处重复配置）
	var eff_attrs := Player.effective_self_attrs()
	var weighted_sum := 0
	var weight_total := 0
	for attr_name in attrs:
		var weight := int(attrs[attr_name])
		var player_var: String = ATTR_MAP.get(attr_name, "")
		if player_var == "":
			continue
		var attr_value := int(eff_attrs.get(attr_name, Player.get(player_var)))
		weighted_sum += attr_value * weight
		weight_total += weight

	if weight_total == 0:
		return 1

	var x := int(float(weighted_sum) / float(weight_total))
	return max(1, x)


## 遍历加成配置，返回当前生效的加成列表
func _get_active_modifiers(modifiers_config: Array) -> Array:
	var result: Array = []
	for mod_config in modifiers_config:
		var source: String = mod_config.get("source", "")
		var mod_name: String = mod_config.get("name", "")
		var bonus := int(mod_config.get("bonus", 0))
		var desc: String = mod_config.get("desc", mod_name)
		var active := false

		match source:
			"tag":
				active = mod_name in Player.player_tags
			"num_tag":
				var left := int(mod_config.get("left", 0))
				var right := int(mod_config.get("right", 999999))
				active = Player.player_meet_num_tag(mod_name, left, right)
			"stuff":
				active = mod_name in Player.player_stuff
			"equipment":
				# 三槽字典 → 比值（槽位名不是装备名）。
				active = mod_name in Player.equipment_names()
			"npc_tag":
				var npc_name: String = mod_config.get("npc", "")
				active = Player.npc_has_tags(npc_name, [mod_name], 1)
			_:
				active = false

		if active:
			result.append({
				"source": source,
				"name": mod_name,
				"bonus": bonus,
				"desc": desc,
			})

	return result


## 掷 1dx（1 到 x 的随机整数）
func _roll_dice(x: int) -> int:
	if x <= 0:
		return 0
	return randi() % x + 1


## 根据余量(margin = 最终值 - 难度)判定成功等级
func _determine_result_level(check_data: Dictionary, margin: int) -> String:
	var crit_success_margin := int(check_data.get("crit_success_margin", 3))
	var crit_failure_margin := int(check_data.get("crit_failure_margin", -3))

	if margin >= crit_success_margin:
		return "crit_success"
	elif margin >= 0:
		return "success"
	elif margin > crit_failure_margin:
		return "failure"
	else:
		return "crit_failure"


# ============================================================
#  UI
# ============================================================

func _show_check_ui(check_data: Dictionary, resolved: Dictionary) -> void:
	var ui_scene = load(CHECK_UI_PATH)
	var check_ui = ui_scene.instantiate()
	# 统一交给覆盖层管理器（D-UI6）。鉴定结算必须看完才能继续，因此 Esc 不放行。
	# 同 plot_importer：本函数可能被 _ready 阶段的剧情串到调用，保持 deferred。
	OverlayRoot.push_overlay.call_deferred(check_ui, {
		"modal": true,
		"esc_closes": false,
	})
	check_ui.show_check.call_deferred(check_data, resolved, self)


## UI "继续" 按钮回调 —— 执行对应分支
func on_check_confirmed(check_data: Dictionary, resolved: Dictionary) -> void:
	var result_level: String = resolved["result_level"]
	var branches: Dictionary = check_data.get("branches", {})

	# 选择分支：精确匹配优先，大成功回退到成功，大失败回退到失败
	var branch: Variant = null
	if branches.has(result_level):
		branch = branches[result_level]
	elif result_level == "crit_success" and branches.has("success"):
		branch = branches["success"]
	elif result_level == "crit_failure" and branches.has("failure"):
		branch = branches["failure"]

	if branch != null and branch is Dictionary:
		# 执行效果
		var effect: Dictionary = branch.get("effect", {})
		if not effect.is_empty():
			deal_effect(effect)

		# 触发剧情
		var plot: Variant = branch.get("plot", null)
		if plot != null and plot is Dictionary:
			var plot_path: String = plot.get("path", "")
			var plot_name: String = plot.get("name", "")
			if plot_path != "" and plot_name != "":
				PlotImporter.add_plot(plot_path, plot_name)

	check_completed.emit(resolved)
	# D-C6：当前鉴定彻底结束，清状态并续跑队列中的下一个（用 _finish_check 而非直接置 false）
	_finish_check()


# ============================================================
#  效果处理（与 dialogue_ui.gd 的 deal_effect 格式一致）
#  全部字段类型（money/tags/num_tags/stuff/attrs/npc/child/
#  equipment/remove_tags/remove_num_tags/name_child）统一由
#  EffectProcessor 处理，本函数仅做薄转发。
# ============================================================

func deal_effect(dialogue_effects: Dictionary) -> void:
	# 鉴定系统 effect 处理统一转发 EffectProcessor（三系统共用同一套 effect 契约）。
	# 鉴定无流程态 tag 隔离（tags 直接进 player_tags）、无 name_child 阻塞需求——默认 context 即可。
	EffectProcessor.apply(dialogue_effects)
