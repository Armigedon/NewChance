extends CastBase

const NATIVE_STRIKE_RADIUS: float = 1.5
const VFX_LIFETIME: float = 0.2  # how long the bolt visual stays before despawn

@export var direction: Vector3 = Vector3.FORWARD  # unused; kept for player.gd compat

# NOTE: This _ready() reads same_color_count, size_multiplier, base_damage,
# modifier_stack, and base_color — all populated by CastBase.configure().
# Player._try_cast must call configure() BEFORE add_child(), since _ready
# fires on add. If you reorder _try_cast, ensure configure() runs first.
func _ready() -> void:
	source_tag = "lightning"
	# Reposition strike to cursor target (was previously at player+aim_dir*1m)
	global_position = Vector3(target_pos.x, 0.5, target_pos.z)
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
	if area != null:
		for body in area.get_overlapping_bodies():
			if not body.is_in_group("enemy"):
				continue
			_hit_target(body, global_position)
	# Fire spawners at the strike location regardless of whether enemies were
	# hit — green LINGER drops a cloud where the cast resolved, not where
	# damage landed. Matches cast_purple_void's unconditional behavior.
	DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage, _player_skill_system())
	# Despawn after brief VFX
	await get_tree().create_timer(VFX_LIFETIME).timeout
	queue_free()
