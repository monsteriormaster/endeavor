extends Resource
class_name DialogueGroup

## 显示布局
## "default" = 底部全宽对话框（普通 NPC 对话）
## "newspaper" = 屏幕居中弹窗，点击任意位置或回车关闭（报纸、布告等）
@export var layout: String = "default"

@export var dialogue_list : Array[Dialogue]
