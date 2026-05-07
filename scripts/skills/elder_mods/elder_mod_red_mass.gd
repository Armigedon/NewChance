extends ElderModifier
class_name ElderModRedMass

# Damage scales with target's missing HP. Spec: up to 2x at 50% HP (rank 1),
# scaling to 3x / 4x at higher ranks. Implemented as: multiplier =
# 1.0 + missing_hp_frac * (rank * 2.0). At 50% missing this is 1.0 + 0.5 * 2 = 2.0
# (rank 1), 3.0 (rank 2), 4.0 (rank 3).
func _init() -> void:
	super._init("red_mass", "red", "Red Mass", "Damage scales with target's missing HP, up to 2x at 50%. Stack: +1x.")
	damage_multiplier = func(target: Node, _base_damage: int, stack_count: int) -> float:
		if not is_instance_valid(target):
			return 1.0
		if not ("hp" in target and "max_hp" in target):
			return 1.0
		var max_hp: float = float(target.get("max_hp"))
		if max_hp <= 0.0:
			return 1.0
		var hp: float = float(target.get("hp"))
		var missing_frac: float = clampf(1.0 - hp / max_hp, 0.0, 1.0)
		return 1.0 + missing_frac * (2.0 * float(stack_count))
