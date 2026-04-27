extends CastBase

const EFFECT_CLOUD_SCENE: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const NATIVE_LIFETIME: float = 3.0
const NATIVE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

# NOTE: This _ready() reads same_color_count, size_multiplier, base_damage,
# modifier_stack, and base_color — all populated by CastBase.configure().
# Player._try_cast must call configure() BEFORE add_child(), since _ready
# fires on add. If you reorder _try_cast, ensure configure() runs first.
func _ready() -> void:
	# Place cloud immediately at this cast's position; cast then frees itself.
	var cloud: Node3D = EFFECT_CLOUD_SCENE.instantiate()
	var lifetime_total: float = NATIVE_LIFETIME + 1.5 * float(same_color_count)
	var radius_total: float = NATIVE_RADIUS * size_multiplier
	var tick_dmg: int = max(1, int(float(base_damage) * DamagePipeline.BURN_DPS_FRAC))
	cloud.configure(lifetime_total, radius_total, tick_dmg, modifier_stack, base_color)
	get_parent().add_child(cloud)
	cloud.global_position = global_position
	queue_free()
