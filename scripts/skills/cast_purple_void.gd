extends CastBase

const EFFECT_WELL_SCENE: PackedScene = preload("res://scenes/effects/effect_gravity_well.tscn")
const NATIVE_LIFETIME: float = 2.0
const NATIVE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

# NOTE: This _ready() reads same_color_count, size_multiplier, base_damage,
# modifier_stack, and base_color — all populated by CastBase.configure().
# Player._try_cast must call configure() BEFORE add_child(), since _ready
# fires on add. If you reorder _try_cast, ensure configure() runs first.
func _ready() -> void:
	var well: Node3D = EFFECT_WELL_SCENE.instantiate()
	var lifetime_total: float = NATIVE_LIFETIME * size_multiplier
	var radius_total: float = NATIVE_RADIUS * size_multiplier
	var tick_dmg: int = max(1, int(float(base_damage) * DamagePipeline.CLOUD_TICK_FRAC))
	well.configure(lifetime_total, radius_total, tick_dmg, modifier_stack, base_color)
	get_parent().add_child(well)
	well.global_position = global_position
	# Fire green LINGER if a green modifier is in the stack (purple-base + green
	# modifier should spawn a cloud at the well placement position).
	DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
	queue_free()
