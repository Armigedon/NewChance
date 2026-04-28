extends CastBase

const EFFECT_WALL_SCENE: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")
const NATIVE_HP: int = 30
const NATIVE_LIFETIME: float = 1.5  # base; lifetime caps at 3s via diminishing returns
const NATIVE_LENGTH: float = 4.0

@export var direction: Vector3 = Vector3.FORWARD

# NOTE: This _ready() reads same_color_count, size_multiplier, base_damage,
# modifier_stack, and base_color — all populated by CastBase.configure().
# Player._try_cast must call configure() BEFORE add_child(), since _ready
# fires on add. If you reorder _try_cast, ensure configure() runs first.
func _ready() -> void:
	# Place wall perpendicular to player→cursor line. We use the cast's `direction`
	# (set by player._try_cast = aim_dir) as the player→cursor axis; wall axis is
	# the cross product on Y to keep it level.
	var perp: Vector3 = Vector3(-direction.z, 0.0, direction.x).normalized()
	var wall: StaticBody3D = EFFECT_WALL_SCENE.instantiate()
	var hp_total: int = NATIVE_HP  # flat HP — no scaling per playtest balance
	var lifetime_total: float = 1.5 + 1.5 * (1.0 - pow(0.5, same_color_count))
	var length_total: float = NATIVE_LENGTH * size_multiplier
	wall.configure(hp_total, lifetime_total, length_total)
	get_parent().add_child(wall)
	wall.global_position = Vector3(target_pos.x, 0.5, target_pos.z)
	# Orient the wall: its X-axis (length) aligns with `perp`
	if perp.length() > 0.001:
		wall.look_at(wall.global_position + perp, Vector3.UP)
		wall.rotate_object_local(Vector3.UP, PI / 2.0)
	# Fire green LINGER if a green modifier is in the stack (white-base + green
	# modifier should spawn a cloud at the wall placement position).
	DamagePipeline.fire_impact_spawners(modifier_stack, base_color, wall.global_position, get_parent(), base_damage)
	queue_free()
