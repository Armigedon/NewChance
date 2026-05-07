extends ElderModifier
class_name ElderModBlueFrostbite

const HP_THRESHOLD: float = 0.5
const BASE_BONUS: float = 0.25
const BONUS_PER_STACK: float = 0.10

func _init() -> void:
	super._init("frostbite", "blue", "Frostbite", "Enemies below 50% HP take +25% damage. Stack: +10%.")
	damage_multiplier = func(target: Node, _base_damage: int, stack_count: int) -> float:
		if not is_instance_valid(target):
			return 1.0
		if not ("hp" in target and "max_hp" in target):
			return 1.0
		var max_hp: float = float(target.get("max_hp"))
		if max_hp <= 0.0:
			return 1.0
		var hp_frac: float = float(target.get("hp")) / max_hp
		if hp_frac >= HP_THRESHOLD:
			return 1.0
		return 1.0 + BASE_BONUS + BONUS_PER_STACK * float(stack_count - 1)
