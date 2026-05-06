extends ElderAbility
class_name ElderAbilityPurplePullOnHit

const PULL_IMPULSE: float = 1.0
const PULL_COOLDOWN_S: float = 1.5

func _init() -> void:
	super._init("purple")
	on_attack = func(elder: Node, target: Node) -> void:
		if not is_instance_valid(elder) or not is_instance_valid(target):
			return
		# Per-elder pull cooldown so successive pulls don't lock the player.
		var now_msec: int = Time.get_ticks_msec()
		var last_msec: int = int(elder.get_meta("purple_last_pull_msec", -10000))
		if now_msec - last_msec < int(PULL_COOLDOWN_S * 1000.0):
			return
		elder.set_meta("purple_last_pull_msec", now_msec)
		if target.has_method("apply_pull_toward"):
			target.apply_pull_toward(elder.global_position, PULL_IMPULSE)
