extends ElderModifier
class_name ElderModWhiteCalcify

# Calcify is a passive read at white-bone-wall cast time. cast_white_bone.gd
# multiplies the wall's length and lifetime by the values below.
const SIZE_BONUS_PER_STACK: float = 0.5
const LIFETIME_BONUS_PER_STACK: float = 0.5

func _init() -> void:
	super._init("calcify", "white", "Calcify", "Wall casts spawn 50% larger and 50% longer-lived. Stack: +25% per copy.")

static func size_multiplier(stack_count: int) -> float:
	# +50% at rank 1, +75% at rank 2, +100% at rank 3 (i.e. rank-1 baseline = 0.5,
	# each additional rank adds 0.25 — matches spec "Stack: +25% per copy").
	return 1.0 + SIZE_BONUS_PER_STACK + 0.25 * float(stack_count - 1)

static func lifetime_multiplier(stack_count: int) -> float:
	return 1.0 + LIFETIME_BONUS_PER_STACK + 0.25 * float(stack_count - 1)
