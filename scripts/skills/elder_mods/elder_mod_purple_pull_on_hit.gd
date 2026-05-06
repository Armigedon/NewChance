extends ElderModifier
class_name ElderModPurplePullOnHit

func _init() -> void:
	super._init("pull_on_hit", "purple", "Pull on Hit", "Every cast pulls the target 1m toward the caster. Stack: +1m.")
	on_hit = func(target: Node, _damage: int, source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_pull_toward"):
			# Tag for Crushing Mass timing.
			if target.has_method("set_meta"):
				target.set_meta("recently_pulled_until_msec", Time.get_ticks_msec() + 1000)
			var impulse: float = 1.0 + 1.0 * float(stack_count - 1)
			target.apply_pull_toward(source_pos, impulse)
