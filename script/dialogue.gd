extends Resource

class_name Dialogue

@export var character_name : String
@export_multiline var content : String

## 立绘指定（可选）。空串 = 按 character_name 自动反查（默认行为，绝大多数节点不用写）；
## "-" = 强制不显示立绘；"res://..." = 直接指定路径；其他值 = 角色 key 或中文名。
## 解析见 script/portrait_registry.gd。
@export var portrait := ""

@export var is_option := false
@export var options = []
@export var next := -1
## 条件跳转：步骤级按条件自动选 next（覆盖固定 next）。
## 元素为 {"condition": <条件字典>, "next": <int>}，按顺序取首个命中条件的 next；
## 无条件（缺 condition 或为空）的条目作为默认兜底。无命中则回落到 next。
## 见 plot_importer.sentence_condition（condition 写法与 option.condition 一致，额外支持 child 键）。
@export var nexts = []
@export var effect := {}
@export var is_effect_excute := false
## 文本变量上下文（调用方注入的动态变量，如卡牌名/流程 tag/计算提示）。
## 见 script/text_vars.gd —— 文本中的 {占位符} 会先在此字典查找，再回落全局 player.*/npc.*。
@export var context: Dictionary = {}
