extends ElderModifier
class_name ElderModBlueChillAllHits

func _init() -> void:
	super._init("chill_all_hits", "blue", "Chill All Hits", "Every cast applies 1 chill stack. Repeats add +1 stack per hit.")
	on_hit = func(target: Node, _damage: int, _source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_chill"):
			target.apply_chill(stack_count)
