class_name PortraitRegistry
extends RefCounted
## 对话立绘解析器（静态，单一职责）：把「说话人的显示名」变成「该用哪张立绘 + 它的内容框」。
##
## 内容框（bbox）来自离线生成的 `resoures/portraits.json` —— **运行时不解码任何图像**。
## 原因：1088×1920 的 `get_image()` 是 GPU 回读，每换一次说话人就解一次会卡顿；
## 而 bbox 是死的（素材不定就不会变），构建期算好最划算。
##
## 为什么需要 bbox：`art/` 下 29 张立绘的内容框差异极大（宽 289~1028、高 974~1984）。
## 按**整图**缩放会让人物大小随画布留白漂移 —— 露易丝（bbox 高 1539）会比阿尔温（1805）
## 明显小一圈；按**内容框**等比缩放 + 视觉身高归一，所有说话人上屏一样大。
##
## 候选顺序：
##   ① 节点显式 `portrait` 字段（`"-"` = 强制不显示 / `res://` 路径 / 角色 key 或中文名）
##   ② `portraits.json` 的 aliases（剧情写法与 characters.json 对不上的名字，如「孤儿院 院长」）
##   ③ `CardRegistry` 里 `display_name` 完全匹配的角色卡（= characters.json 全部角色）
##   ④ `Player.npc` 的实时条目（孩子被玩家改名后，剧情里的 `{child_name}` 仍要认得出）
##   ⑤ 都没命中 → 返回 `{}`，调用方**必须让立绘干净退场**（不许留占位框/裂图）
##
## 用法：
##   var p := PortraitRegistry.resolve(name_text, dialogue.portrait)
##   if p.is_empty(): 隐藏立绘
##   else: 加载 p.image，按 PortraitRegistry.bbox_of(p, tex.get_size()) 摆位

const TABLE_PATH := "resoures/portraits.json"
## explicit 字段写这个值 = 强制不显示立绘（旁白型节点想显式表态时用）。
const DISABLE_TOKEN := "-"

static var _by_image: Dictionary = {}
static var _aliases: Dictionary = {}
static var _loaded := false


## 主入口：返回 `{"image": String, "bbox": Variant}`，无立绘返回 `{}`（空字典）。
static func resolve(display_name: String, explicit: String = "") -> Dictionary:
	_ensure_loaded()

	# ① 节点显式字段优先
	var ex: String = explicit.strip_edges()
	if ex != "":
		if ex == DISABLE_TOKEN:
			return {}
		if ex.begins_with("res://"):
			return _entry(ex)
		var by_ex: String = _find_by_name(ex)
		return _entry(by_ex) if by_ex != "" else {}

	# 说话人名为空 = 旁白（全工程 26% 的节点）→ 立绘必须退场
	var nm: String = display_name.strip_edges()
	if nm == "":
		return {}

	# ② 别名表
	if _aliases.has(nm):
		return _entry(str(_aliases[nm]))

	# ③④ 注册表角色 / 运行时 npc
	var p: String = _find_by_name(nm)
	return _entry(p) if p != "" else {}


## 按名字（中文名）找立绘路径：先查注册表角色卡，再查运行时 npc 条目。
static func _find_by_name(nm: String) -> String:
	for c in CardRegistry.list_by_type("character"):
		if c == null:
			continue
		if String(c.display_name) == nm:
			var ip: String = String(c.icon_path)
			if ip != "":
				return ip
	for key in Player.npc:
		var e: Variant = Player.npc[key]
		if not (e is Dictionary):
			continue
		var d := e as Dictionary
		if String(d.get("name", "")) != nm:
			continue
		var img: String = str(d.get("image", ""))
		if img != "":
			return img
	return ""


## 把解析结果包成条目。图片不存在 → 返回 {}（宁可不显示，也不显示裂图）。
static func _entry(image_path: String) -> Dictionary:
	if image_path == "" or not ResourceLoader.exists(image_path, "Texture2D"):
		return {}
	return {"image": image_path, "bbox": _by_image.get(image_path, null)}


## 取内容框。`bbox` 缺失/格式不对 → 回退整图矩形（调用方传入贴图尺寸）。
static func bbox_of(entry: Dictionary, tex_size: Vector2) -> Rect2:
	var b: Variant = entry.get("bbox", null)
	if b is Array and (b as Array).size() == 4:
		var a := b as Array
		return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Rect2(Vector2.ZERO, tex_size)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		push_warning("PortraitRegistry: 打不开 %s（对话立绘将全部退场）" % TABLE_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("PortraitRegistry: %s 解析失败" % TABLE_PATH)
		return
	var d := parsed as Dictionary
	_by_image = d.get("by_image", {})
	_aliases = d.get("aliases", {})


## 测试/诊断用：当前加载到的条目数。
static func debug_counts() -> Dictionary:
	_ensure_loaded()
	return {"by_image": _by_image.size(), "aliases": _aliases.size()}
