extends "res://scripts/entities/boss_mechanic.gd"

const SLAM_DAMAGE: int = 80
const SLAM_RADIUS: float = 3.0
const RED_BURN_PREP_MULT: float = 1.5

var _target_pos: Vector3 = Vector3.ZERO

func _init() -> void:
	unlock_phase = 3
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 999.0, 3: 18.0}
	windup_duration = 2.0
	execution_duration = 0.4

func _on_windup_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var p: Node = _boss.get("_player")
	if p == null or not is_instance_valid(p):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		p = players[0]
	_target_pos = p.global_position
	if _boss.has_method("_bump_shared_cooldown"):
		_boss._bump_shared_cooldown()

func _on_execution_start() -> void:
	if _wall_absorbs_landing():
		ScreenShake.shake(0.15, 0.3)
		return
	var t_flat: Vector2 = Vector2(_target_pos.x, _target_pos.z)
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		var p_flat: Vector2 = Vector2(p.global_position.x, p.global_position.z)
		if p_flat.distance_to(t_flat) <= SLAM_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(SLAM_DAMAGE)
	ScreenShake.shake(0.15, 0.3)

func _wall_absorbs_landing() -> bool:
	var t_flat: Vector2 = Vector2(_target_pos.x, _target_pos.z)
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		var w_flat: Vector2 = Vector2(w.global_position.x, w.global_position.z)
		if w_flat.distance_to(t_flat) <= SLAM_RADIUS:
			if w.has_method("take_damage"):
				w.take_damage(SLAM_DAMAGE)
			return true
	return false

func is_in_prep() -> bool:
	return is_in_windup()

func burn_damage_multiplier() -> float:
	return RED_BURN_PREP_MULT
