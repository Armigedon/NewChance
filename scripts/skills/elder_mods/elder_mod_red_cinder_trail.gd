extends ElderModifier
class_name ElderModRedCinderTrail

# Cinder trail spawns trail nodes from player movement. Player movement code
# has to read this modifier's stack count off the active wand and emit trail
# segments. For the resource itself, on_cast just tags state on the player.
func _init() -> void:
	super._init("cinder_trail", "red", "Cinder Trail", "Moving leaves a fire trail that burns enemies. Repeats extend duration.")
	on_cast = func(caster: Node, _mod_stack: Array, _base_color: String, stack_count: int) -> void:
		if not is_instance_valid(caster):
			return
		caster.set_meta("cinder_trail_stack", stack_count)
