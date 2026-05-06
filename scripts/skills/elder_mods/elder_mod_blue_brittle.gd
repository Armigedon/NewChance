extends ElderModifier
class_name ElderModBlueBrittle

# Brittle: hits against frozen enemies deal +100% damage and shatter freeze.
# Stack: +50% per copy.
func _init() -> void:
	super._init("brittle", "blue", "Brittle", "Hits against frozen enemies deal +100% damage and shatter freeze. Stack: +50%.")
	damage_multiplier = func(target: Node, _base_damage: int, stack_count: int) -> float:
		if not is_instance_valid(target):
			return 1.0
		if not target.has_method("is_frozen"):
			return 1.0
		if not target.is_frozen():
			return 1.0
		return 2.0 + 0.5 * float(stack_count - 1)
	on_hit = func(target: Node, _damage: int, _source_pos: Vector3, _stack_count: int) -> void:
		if is_instance_valid(target) and target.has_method("is_frozen") and target.is_frozen():
			# Shatter freeze.
			if "_frozen_remaining" in target:
				target._frozen_remaining = 0.0
