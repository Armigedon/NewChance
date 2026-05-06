extends ElderModifier
class_name ElderModPurpleCrushingMass

func _init() -> void:
	super._init("crushing_mass", "purple", "Crushing Mass", "Pulled enemies take +30% damage for 1s. Stack: +15%.")
	damage_multiplier = func(target: Node, _base_damage: int, stack_count: int) -> float:
		if not is_instance_valid(target):
			return 1.0
		if not target.has_meta("recently_pulled_until_msec"):
			return 1.0
		var until: int = int(target.get_meta("recently_pulled_until_msec"))
		if Time.get_ticks_msec() > until:
			return 1.0
		var bonus: float = 0.30 + 0.15 * float(stack_count - 1)
		return 1.0 + bonus
