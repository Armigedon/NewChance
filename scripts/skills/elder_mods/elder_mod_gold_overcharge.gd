extends ElderModifier
class_name ElderModGoldOvercharge

# Overcharge: every Nth cast deals double damage. Cycle via player meta counter.
func _init() -> void:
	super._init("overcharge", "gold", "Overcharge", "Every 3rd cast deals double damage. Stack: every 2nd / every cast.")
	on_cast = func(caster: Node, _mod_stack: Array, _base_color: String, stack_count: int) -> void:
		if not is_instance_valid(caster):
			return
		var counter: int = int(caster.get_meta("overcharge_counter", 0)) + 1
		caster.set_meta("overcharge_counter", counter)
		var trigger_at: int = max(1, 4 - stack_count)  # stack=1 → every 3rd; stack=2 → every 2nd; stack=3+ → every cast
		if counter >= trigger_at:
			caster.set_meta("overcharge_active", true)
			caster.set_meta("overcharge_counter", 0)
		else:
			caster.set_meta("overcharge_active", false)
	damage_multiplier = func(_target: Node, _base_damage: int, _stack_count: int) -> float:
		# Pipeline reads from caster meta; multiplier hook reads target side
		# is no-op for this modifier. Pipeline integration in Task 9.
		return 1.0
