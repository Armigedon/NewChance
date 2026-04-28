extends CastBase

const PROJECTILE_SPEED: float = 18.0

@export var direction: Vector3 = Vector3.FORWARD

var _hit_enemies: Array[Node] = []

func _ready() -> void:
	source_tag = "ice_line"
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true
	var mesh: MeshInstance3D = $Mesh as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3(size_multiplier, 1.0, size_multiplier)

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("enemy"):
		return
	if body in _hit_enemies:
		return
	var is_first_hit: bool = _hit_enemies.is_empty()
	_hit_enemies.append(body)
	_hit_target(body, global_position)
	# Fire spawner on first hit, at this position (always on-map). Pierce
	# continues for the remaining lifetime via CastBase._process.
	if is_first_hit:
		DamagePipeline.fire_impact_spawners(modifier_stack, base_color, global_position, get_parent(), base_damage)
	# Pierces — does NOT queue_free; lets lifetime expire via CastBase._process
