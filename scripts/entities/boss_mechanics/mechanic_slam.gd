extends "res://scripts/entities/boss_mechanic.gd"

# Telegraphed slam — small AoE around boss position. Universal dodge-out.

const RADIUS: float = 2.0
const DAMAGE: int = 25

func _init() -> void:
	unlock_phase = 1
	is_big = true
	cooldowns_by_phase = {1: 5.0, 2: 4.0, 3: 3.0}
	windup_duration = 0.6
	execution_duration = 0.0  # impact is instantaneous on execution start

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var center: Vector3 = _boss.global_position
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(center) <= RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(DAMAGE)
	ScreenShake.shake(0.05, 0.1)
