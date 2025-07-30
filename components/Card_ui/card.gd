extends Control


var velocity = Vector2.ZERO
var damping = 0.35
var stiffness = 500


enum cardState{following,dragging,folded}#对于卡牌设置了两个状态功能,一个附着点，一个拖拽.这里直接使用枚举
#新增功能在此基础上进行新增

@export var carCurrentState=cardState.folded
#@export var carCurrentState=cardState.following
@export var is_expanded := false
@export var folded_position: Vector2  # 折叠时的位置
@export var expanded_position: Vector2  # 展开时的位置
@export var fold_duration := 0.5  # 展开/折叠动画时间
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
		cardState.folded:
			pass


func toggle_expand() -> void:
	if carCurrentState == cardState.folded:
		expand()
	else:
		fold()


func expand() -> void:
	if !is_expanded:
		is_expanded = true
		visible = true
		carCurrentState = cardState.following
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(self,"global_position",expanded_position,fold_duration)


func fold() -> void:
	if is_expanded:
		is_expanded = false
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(self,"global_position",folded_position,fold_duration)
		tween.tween_callback(func():
			carCurrentState = cardState.folded
			#或者完全隐藏
			#visible =false
			)


func _on_button_button_down() -> void:
	carCurrentState = cardState.dragging
	pass # Replace with function body.


func _on_button_button_up() -> void:
	carCurrentState = cardState.following
	pass # Replace with function body.
