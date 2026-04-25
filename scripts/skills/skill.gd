extends RefCounted
class_name Skill

var base_color: String
var modifier_stack: Array[String] = []
var locked: bool = false

func _init(p_base_color: String) -> void:
	base_color = p_base_color

func add_modifier(color: String) -> void:
	if locked:
		return
	modifier_stack.append(color)

func modifier_count_for(color: String) -> int:
	var n: int = 0
	for c in modifier_stack:
		if c == color:
			n += 1
	return n

func has_modifier(color: String) -> bool:
	return modifier_count_for(color) > 0
