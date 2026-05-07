extends RefCounted
class_name Skill

var base_color: String
var modifier_stack: Array[String] = []
# Elder modifiers stack separately from color modifiers; keyed by modifier_id
# with stack count as the value (compounds on repeat draft).
var elder_modifier_stacks: Dictionary = {}

func _init(p_base_color: String) -> void:
	base_color = p_base_color

func add_modifier(color: String) -> void:
	modifier_stack.append(color)

func modifier_count_for(color: String) -> int:
	var n: int = 0
	for c in modifier_stack:
		if c == color:
			n += 1
	return n

func has_modifier(color: String) -> bool:
	return modifier_count_for(color) > 0

func apply_elder_modifier(modifier_id: String) -> void:
	# Compounds on repeat — bumps stack count instead of adding a duplicate
	# entry. Distinct modifier ids each get their own entry.
	elder_modifier_stacks[modifier_id] = int(elder_modifier_stacks.get(modifier_id, 0)) + 1

func elder_modifier_count() -> int:
	return elder_modifier_stacks.size()

func elder_modifier_stack_count(modifier_id: String) -> int:
	return int(elder_modifier_stacks.get(modifier_id, 0))

func has_elder_modifier(modifier_id: String) -> bool:
	return elder_modifier_stacks.has(modifier_id)
