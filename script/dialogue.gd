extends Resource

class_name Dialogue

@export var character_name : String
@export_multiline var content : String

@export var is_option := false
@export var options = []
@export var next := -1
@export var effect := ""
