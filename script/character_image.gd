## character 的 image 字段解析器。
## 单一职责：根据 characters.json 的一项（含 image / gender），给出可加载的 Texture2D 路径。
## 解析策略：
##   1. 显式 image 字段存在 + 资源可加载 → 用它。
##   2. 否则按 gender 回落：男 → man.png，女 → woman.png，其他 → man.png 兜底。
##   3. 回退图也不存在 → 返回空串，调用方保持原状（不爆错）。
##
## 用法（静态方法，无需实例化）：
##   var path := CharacterImage.resolve_path(info)
##   if path != "":
##       var tex := load(path)
##
## 设计意图：原来 character.gd / character_panel.gd 都直接 load(info["image"])，
## 当 image 字段缺失或指向不存在的路径时静默失败 / 直接崩。
## 现在统一收敛到这里，保证：
##   - 没有 image 的角色（孤儿、路人）自动用男女默认剪影；
##   - 显式 image 指向缺失文件时也走回落，而不是空白；
##   - 一处定义，两处调用，行为一致。
class_name CharacterImage extends RefCounted

## 回落图路径。仅此处定义常量，调用方不得再硬编码。
const DEFAULT_MALE_PATH := "res://art/man.png"
const DEFAULT_FEMALE_PATH := "res://art/woman.png"


## 解析 info 的 image 字段，回落到 gender 决定的默认立绘。
## 返回 "res://..." 形式的可加载路径，无法确定时返回 ""。
static func resolve_path(info: Dictionary) -> String:
	# 显式 image：字段存在、非空、对应资源可加载 → 直接返回
	var has_image_field: bool = info.has("image") and info["image"] != null and str(info["image"]) != ""
	if has_image_field:
		var p: String = str(info["image"])
		if ResourceLoader.exists(p, "Texture2D"):
			return p

	# 回落：按 gender 选男女默认剪影；任何 gender（"男"/"女"/其他）都至少有一张图兜底
	var fallback_path: String = DEFAULT_MALE_PATH
	var gender: String = str(info.get("gender", ""))
	if gender == "女":
		fallback_path = DEFAULT_FEMALE_PATH
	if ResourceLoader.exists(fallback_path, "Texture2D"):
		return fallback_path
	# 两张默认图都不存在（资产没就位）→ 空串，让调用方自己处理
	return ""
