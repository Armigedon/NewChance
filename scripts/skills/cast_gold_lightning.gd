extends CastBase

const NATIVE_STRIKE_RADIUS: float = 1.5
const VFX_LIFETIME: float = 0.2  # how long the bolt visual stays before despawn

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

# NOTE: This _ready() reads same_color_count, size_multiplier, base_damage,
# modifier_stack, and base_color — all populated by CastBase.configure().
# Player._try_cast must call configure() BEFORE add_child(), since _ready
# fires on add. If you reorder _try_cast, ensure configure() runs first.
func _ready() -> void:
	var radius_total: float = NATIVE_STRIKE_RADIUS * size_multiplier
	# Resize HitArea collision
	var shape: CollisionShape3D = $HitArea/CollisionShape3D
	if shape != null and shape.shape is SphereShape3D:
		var s: SphereShape3D = shape.shape.duplicate() as SphereShape3D
		s.radius = radius_total
		shape.shape = s
	# Strike: deal damage immediately to all enemies in radius, then linger briefly for VFX
	await get_tree().process_frame  # let physics report overlaps
	var area: Area3D = $HitArea
	var hit: bool = false
	if area != null:
		for body in area.get_overlapping_bodies():
			if not body.is_in_group("enemy"):
				continue
			_hit_target(body, global_position)
			hit = true
	if hit:
		DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
	# Despawn after brief VFX
	await get_tree().create_timer(VFX_LIFETIME).timeout
	queue_free()
