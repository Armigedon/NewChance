extends CastBase

const PROJECTILE_SPEED: float = 10.0

@export var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	var area: Area3D = $HitArea
	area.body_entered.connect(_on_body_entered)
	area.monitoring = true

func _physics_process(delta: float) -> void:
	global_position += direction.normalized() * PROJECTILE_SPEED * delta

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		_on_hit_enemy(body)
		queue_free()
