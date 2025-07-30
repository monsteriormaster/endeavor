extends Control


var velocity = Vector2.ZERO
var damping = 0.35
var stiffness = 500


enum cardState{following,dragging}#对于卡牌设置了两个状态功能,一个附着点，一个拖拽.这里直接使用枚举
#新增功能在此基础上进行新增
@export var carCurrentState=cardState.following

#var follow_target
@export var follow_target:Node

func _process(delta: float) -> void:
	match carCurrentState:
		cardState.dragging:
			var target_position=get_global_position()- size/2
			global_position=global_position.lerp(target_position, 0.4)
		cardState.following:
			if follow_target!=null:
				var target_position=follow_target.global_position
				var displacement = target_position - global_position
				var force = displacement * stiffness
				velocity += force * delta
				velocity *= (1.0 - damping)
				global_position += velocity * delta


func _on_button_button_down() -> void:
	carCurrentState = cardState.dragging
	pass # Replace with function body.


func _on_button_button_up() -> void:
	carCurrentState = cardState.following
	pass # Replace with function body.
