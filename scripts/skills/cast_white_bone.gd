extends CastBase

const PROJECTILE_SPEED: float = 14.0

@export var direction: Vector3 = Vector3.FORWARD

var _hit_enemies: Array[Node] = []

func _ready() -> void:
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not (body in _hit_enemies):
		_hit_enemies.append(body)
		_on_hit_enemy(body)
