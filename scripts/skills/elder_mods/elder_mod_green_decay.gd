extends ElderModifier
class_name ElderModGreenDecay

const BASE_SLOW: float = 0.30
const SLOW_PER_STACK: float = 0.10
const SLOW_CAP: float = 0.70
const SLOW_DURATION: float = 1.5

# Decay slows poisoned enemies. Fires on hit; if the target has any poison
# applied (via apply_poison or _poison_remaining > 0), apply a slow.
func _init() -> void:
	super._init("decay", "green", "Decay", "Poisoned enemies move 30% slower. Stack: +10% (cap 70%).")
	on_hit = func(target: Node, _damage: int, _source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if not target.has_method("apply_slow"):
			return
		# Poison is currently routed through the burn DoT plumbing (see
		# elder_mod_green_toxin_all_hits). Welps expose `_burn_remaining`.
		var poisoned: bool = false
		if "_burn_remaining" in target:
			poisoned = float(target.get("_burn_remaining")) > 0.0
		if not poisoned:
			return
		var slow: float = min(SLOW_CAP, BASE_SLOW + SLOW_PER_STACK * float(stack_count - 1))
		target.apply_slow(slow, SLOW_DURATION)
