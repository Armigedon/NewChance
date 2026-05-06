extends CastBase

const PROJECTILE_SPEED: float = 12.0
const BASE_AOE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	source_tag = "fireball"
	global_position = spawn_pos
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true
	# Apply same-color size scaling to visual mesh
	var mesh: MeshInstance3D = $Mesh as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE * size_multiplier

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("enemy"):
		return
	# Marrow Pierce: skip enemies already hit so the AoE doesn't re-hit them
	# as the projectile passes through.
	if _hit_set.has(body.get_instance_id()):
		return
	var aoe_radius: float = BASE_AOE_RADIUS * size_multiplier
	_damage_aoe(global_position, aoe_radius)
	DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
	# Mark this enemy as hit. _damage_aoe also routes through _hit_target which
	# tracks the hit_set, but we ensure the body that triggered the impact is
	# tracked even if it's outside the AoE radius (shouldn't happen, but safe).
	_hit_set[body.get_instance_id()] = true
	if pierce_budget > 0:
		pierce_budget -= 1
		return
	queue_free()
