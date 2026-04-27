extends CastBase

const PROJECTILE_SPEED: float = 12.0
const BASE_AOE_RADIUS: float = 2.0

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
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
	var aoe_radius: float = BASE_AOE_RADIUS * size_multiplier
	_damage_aoe(global_position, aoe_radius)
	queue_free()
