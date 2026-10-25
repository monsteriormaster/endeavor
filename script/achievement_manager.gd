extends Node

## 成就系统管理器（autoload `AchievementManager`）。
## 负责成就配置加载、解锁状态维护、解锁弹窗串行队列、成就列表面板呼出。
##
## 解锁流程：
##   EffectProcessor.apply 收到 achievement effect → 调本管理器 unlock(id)
##   → 幂等检查 → 写 Player.achievements_unlocked → 广播 EventSignal.achievement_unlocked
##   → 入队弹窗（串行显示，避免同时刷屏丢失）
##
## 预解锁：_ready 扫描 achieve==true 的成就，直接置位（不弹窗——启动时主场景未加载，
## 弹窗会出现在黑屏上无意义；元成就语义是"默认已解锁"，在成就墙显示为已解锁即可）。
##
## 存档：解锁状态由 Player.achievements_unlocked 持有，随 SaveLoader 白名单持久化。

const ACHIEVEMENTS_PATH := "res://resoures/achievements.json"
const POPUP_SCENE_PATH := "res://components/achievement_popup.tscn"
const LIST_SCENE_PATH := "res://components/achievement_list.tscn"

## `unlock_after_leaving()` 的最长等待帧数。换场景失败也要把成就发出去，
## 不能因为等不到新场景就静默吃掉一次解锁。
const MAX_WAIT_FRAMES := 60

## 惰性加载的成就配置缓存 {id: {name, description, point, achieve?, path?}}
var _cache: Dictionary = {}

## 弹窗队列：同时解锁多个成就时串行显示，避免重叠丢失。
var _popup_queue: Array[String] = []
var _popup_showing: bool = false


func _ready() -> void:
	_load_config()
	# 预解锁元成就（achieve==true）：直接置位，不弹窗。
	# autoload _ready 时主场景尚未加载，弹窗会出现在黑屏上无意义；
	# 元成就语义是"默认已解锁"，在成就墙显示为已解锁即可，无需"达成"反馈。
	for id in _cache:
		if bool(_cache[id].get("achieve", false)):
			Player.achievements_unlocked[id] = true


## 加载成就配置 JSON 到缓存。非字典 / 缺失 → push_warning + 缓存空。
func _load_config() -> void:
	_cache.clear()
	var f := FileAccess.open(ACHIEVEMENTS_PATH, FileAccess.READ)
	if f == null:
		push_warning("AchievementManager: 找不到 achievements.json（%s）" % ACHIEVEMENTS_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("AchievementManager: achievements.json 解析失败（非字典）")
		return
	_cache = parsed


## 解锁一个成就。幂等：已解锁 / 未知 id 静默跳过。
func unlock(id: String) -> void:
	if not _cache.has(id):
		push_warning("AchievementManager: 未知成就 id '%s'，跳过" % id)
		return
	_do_unlock(id)


## 换场景**之后再**解锁（供「进入游戏界面才该弹」的成就用，如开局成就）。
##
## 为什么要绕这一道：
##   ① 在 `selection.before_trans()` 里直接 unlock，弹窗会压在**角色创建表**上；
##   ② selection 换场景后立刻被 free，而节点 free 之后它身上的 `await` 永远不再恢复 ——
##      所以「等两帧」不能写在 selection 里，必须挂在 autoload（本管理器）身上。
##
## 判据：`current_scene` 已存在、已在树中、且路径不等于 `from_path`。
## 最多等 MAX_WAIT_FRAMES 帧，超时照样解锁（宁可早弹，不可静默吞掉）。
func unlock_after_leaving(from_path: String, id: String) -> void:
	if not _cache.has(id):
		push_warning("AchievementManager: 未知成就 id '%s'，跳过" % id)
		return
	_defer_unlock_until_scene_changed(from_path, id)


func _defer_unlock_until_scene_changed(from_path: String, id: String) -> void:
	var waited := 0
	while waited < MAX_WAIT_FRAMES:
		await get_tree().process_frame
		waited += 1
		var cs: Node = get_tree().current_scene
		if cs != null and cs.is_inside_tree() and String(cs.scene_file_path) != from_path:
			break
	if waited >= MAX_WAIT_FRAMES:
		push_warning("AchievementManager: 等新场景超时（%d 帧），仍解锁 '%s'" % [MAX_WAIT_FRAMES, id])
	unlock(id)


## 实际解锁逻辑（无未知 id 守卫，供 unlock 内部调用）。
func _do_unlock(id: String) -> void:
	if Player.achievements_unlocked.has(id):
		return  # 幂等
	Player.achievements_unlocked[id] = true
	var cfg: Dictionary = _cache[id]
	EventSignal.achievement_unlocked.emit(id, String(cfg.get("name", id)))
	_popup_queue.append(id)
	_try_show_next_popup()


## 尝试显示队列中下一个弹窗。无显示中且有排队时呼出。
func _try_show_next_popup() -> void:
	if _popup_showing:
		return
	if _popup_queue.is_empty():
		return
	# 树正在关闭时不再呼出新弹窗——quit/teardown 会触发 popup tree_exited 级联，
	# 此时 OverlayRoot 可能已脱离树，push_overlay 会崩。清空队列防止级联。
	# 用 is_inside_tree() 而非 get_tree()==null：后者在节点脱离树时会本身 push_error。
	if not is_instance_valid(OverlayRoot) or not OverlayRoot.is_inside_tree():
		_popup_queue.clear()
		_popup_showing = false
		return
	var id: String = _popup_queue.pop_front()
	var scene: PackedScene = load(POPUP_SCENE_PATH)
	if scene == null:
		push_warning("AchievementManager: 找不到 achievement_popup.tscn（%s）" % POPUP_SCENE_PATH)
		return
	var popup: Node = scene.instantiate()
	if not is_instance_valid(popup):
		push_warning("AchievementManager: achievement_popup 实例化失败")
		return
	OverlayRoot.push_overlay(popup, {
		"modal": false,
		"esc_closes": false,
		"persist": true,
	})
	_popup_showing = true
	# popup 自带 2s Timer 关闭自己（close_overlay → queue_free → tree_exited）；
	# 此处监听 tree_exited 出列下一个，避免同时刷屏丢失。
	popup.tree_exited.connect(_on_popup_closed)
	popup.setup(_cache[id])


func _on_popup_closed() -> void:
	_popup_showing = false
	_try_show_next_popup()


## 返回缓存深拷贝（避免外部修改污染缓存）。
func get_all() -> Dictionary:
	return _cache.duplicate(true)


## 成就是否已解锁。
func is_unlocked(id: String) -> bool:
	return Player.achievements_unlocked.has(id)


## 已解锁成就数。
func get_unlocked_count() -> int:
	return Player.achievements_unlocked.size()


## 总积分（所有成就 point 之和）。
func get_total_points() -> int:
	var total := 0
	for id in _cache:
		total += int(_cache[id].get("point", 0))
	return total


## 已解锁积分。
func get_unlocked_points() -> int:
	var total := 0
	for id in _cache:
		if Player.achievements_unlocked.has(id):
			total += int(_cache[id].get("point", 0))
	return total


## 呼出成就列表面板。
func open_list() -> void:
	var scene: PackedScene = load(LIST_SCENE_PATH)
	if scene == null:
		push_warning("AchievementManager: 找不到 achievement_list.tscn（%s）" % LIST_SCENE_PATH)
		return
	var list: Node = scene.instantiate()
	if not is_instance_valid(list):
		push_warning("AchievementManager: achievement_list 实例化失败")
		return
	OverlayRoot.push_overlay(list, {
		"modal": true,
		# 🔴 必须 false：本面板走**翻页**进场/出场（0.5s）。`OverlayRoot.close_top()` 在
		#    `close_method` 之后会兜底 `close_overlay` ⇒ 立刻 queue_free ⇒ 翻页死在第 0 帧。
		#    Esc 由 `achievement_list._unhandled_key_input` 自己接，语义不变。
		"esc_closes": false,
		"close_method": "close",
	})
	list.setup()
