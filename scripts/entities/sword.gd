extends Area3D

@export var swing_interval: float = 0.4  # seconds per swing
@export var base_damage: int = 15

signal hit_enemy(enemy: Node, damage: int)

var _swing_cooldown: float = 0.0

func _process(delta: float) -> void:
	if _swing_cooldown > 0.0:
		_swing_cooldown = max(0.0, _swing_cooldown - delta)
		return
	var enemies: Array = get_overlapping_bodies().filter(_is_enemy)
	if enemies.size() == 0:
		return
	# Cleave: swing damages every enemy in range, not just the first.
	for enemy in enemies:
		if enemy.has_method("take_damage"):
			enemy.take_damage(base_damage)
		hit_enemy.emit(enemy, base_damage)
	_swing_cooldown = swing_interval

func _is_enemy(body: Node) -> bool:
	return body.is_in_group("enemy")
