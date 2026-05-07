extends ElderModifier
class_name ElderModBlueGlacialPath

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const BASE_LIFETIME: float = 1.0
const LIFETIME_PER_STACK: float = 0.5
const TRAIL_RADIUS: float = 1.5
const TRAIL_TICK_DAMAGE: int = 3

# Glacial Path drops an ice patch at the caster's position when they cast.
# The patch reuses the cloud scene with base_color "blue" so DamagePipeline's
# native blue layer applies one chill stack per tick to enemies in range.
func _init() -> void:
	super._init("glacial_path", "blue", "Glacial Path", "Casting drops a chilling ice patch at your feet. Stack: +50% duration.")
	on_cast = func(caster: Node, _modifier_stack: Array, _base_color: String, stack_count: int) -> void:
		if not is_instance_valid(caster):
			return
		var parent: Node = caster.get_parent()
		if parent == null:
			return
		var lifetime: float = BASE_LIFETIME + LIFETIME_PER_STACK * float(stack_count - 1)
		var cloud: Node3D = CloudScene.instantiate()
		parent.add_child(cloud)
		cloud.global_position = caster.global_position
		cloud.configure(lifetime, TRAIL_RADIUS, TRAIL_TICK_DAMAGE, [], "blue")
