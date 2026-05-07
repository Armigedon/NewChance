extends ElderModifier
class_name ElderModPurpleSingularity

const WellScene: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")
const WELL_LIFETIME: float = 1.5
const WELL_RADIUS: float = 3.0

# Every Nth cast spawns a 3m gravity well at the cast target. Stack scales
# trigger frequency: rank 1 = every 4th, rank 2 = every 3rd, rank 3+ = every 2nd.
func _init() -> void:
	super._init("singularity", "purple", "Singularity", "Every 4th cast spawns a 3m pull field. Stack: every 3rd / every 2nd cast.")
	on_cast = func(caster: Node, _modifier_stack: Array, _base_color: String, stack_count: int) -> void:
		if not is_instance_valid(caster):
			return
		var trigger_at: int = max(2, 5 - stack_count)
		var counter: int = int(caster.get_meta("singularity_counter", 0)) + 1
		if counter < trigger_at:
			caster.set_meta("singularity_counter", counter)
			return
		caster.set_meta("singularity_counter", 0)
		var parent: Node = caster.get_parent()
		if parent == null:
			return
		var well: Node3D = WellScene.instantiate()
		parent.add_child(well)
		# Anchor at caster — the player's casts are aimed, but a self-centered
		# pull field is easier to telegraph and lines up with Slipstream/movement.
		well.global_position = caster.global_position
		if well.has_method("configure"):
			well.configure(WELL_LIFETIME, WELL_RADIUS, 0, [], "purple")
