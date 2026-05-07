extends ElderModifier
class_name ElderModGreenLingeringMist

# Lingering Mist is a passive multiplier read at cloud spawn time.
# Implementation: damage_pipeline.fire_impact_spawners queries the active wand
# for "lingering_mist" stack count and scales the cloud's lifetime parameter.
# +50% per stack (lifetime = BASE * (1 + 0.5 * stack)).
const LIFETIME_BONUS_PER_STACK: float = 0.5

func _init() -> void:
	super._init("lingering_mist", "green", "Lingering Mist", "Green clouds last 50% longer. Stack: +50% per copy.")

static func lifetime_multiplier(stack_count: int) -> float:
	return 1.0 + LIFETIME_BONUS_PER_STACK * float(stack_count)
