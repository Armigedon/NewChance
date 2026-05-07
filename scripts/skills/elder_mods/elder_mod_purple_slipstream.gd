extends ElderModifier
class_name ElderModPurpleSlipstream

# Slipstream is a passive: when moving toward an enemy, the player gains a
# movement speed multiplier. Implementation: player.gd queries the active
# wand for slipstream stack count each physics frame and adjusts move_speed
# via this multiplier.
const BASE_BONUS: float = 0.20
const BONUS_PER_STACK: float = 0.10

func _init() -> void:
	super._init("slipstream", "purple", "Slipstream", "Moving toward enemies grants +20% speed. Stack: +10% per copy.")

static func speed_multiplier(stack_count: int) -> float:
	return 1.0 + BASE_BONUS + BONUS_PER_STACK * float(stack_count - 1)
