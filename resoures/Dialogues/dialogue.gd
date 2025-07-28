extends Resource
class_name Dialogue
#@export 的关键字用于确保变量可编辑,单个对话的数据框结构
@export var character_name : String
@export_multiline var content : String#用于文本框来显示变量
@export var avater : Texture
@export var show_on_left : bool#用于记录对话数据是否应该被显示在左边
