extends ElderModifier
class_name ElderModRedIgniteAllHits

func _init() -> void:
	super._init("ignite_all_hits", "red", "Ignite All Hits", "Every cast applies a 1s burn DoT. Repeats add +0.5s duration.")
	on_hit = func(target: Node, damage: int, source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_burn"):
			var duration: float = 1.0 + 0.5 * float(stack_count - 1)
			# Burn DPS uses the same fraction as native red burn.
			target.apply_burn(float(damage) * 0.15, duration)
