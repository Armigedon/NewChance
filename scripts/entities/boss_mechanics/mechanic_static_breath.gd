extends "res://scripts/entities/boss_mechanic.gd"

const BreathConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const CONE_LENGTH: float = 5.0
const CONE_ANGLE_DEG: float = 60.0
const TICK_DAMAGE: int = 10
const CHILL_EXTEND_PER_STACK: float = 0.15

var _cone: Node3D = null
var _aim_dir: Vector3 = Vector3.FORWARD

func _init() -> void:
	unlock_phase = 1
	is_big = true
	cooldowns_by_phase = {1: 8.0, 2: 6.0, 3: 5.0}
	windup_duration = 1.0
	execution_duration = 0.8

func _on_windup_start() -> void:
	# Lock aim at telegraph start, toward nearest player
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_aim_dir = Vector3.FORWARD
		return
	var p: Node = players[0]
	var to_p: Vector3 = p.global_position - _boss.global_position
	to_p.y = 0.0
	if to_p.length() > 0.01:
		_aim_dir = to_p.normalized()

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_cone = BreathConeScene.instantiate()
	_boss.get_parent().add_child(_cone)
	_cone.configure(_boss.global_position, _aim_dir, CONE_LENGTH, CONE_ANGLE_DEG, execution_duration, TICK_DAMAGE)
	_cone.blocking_walls_check = func(target_pos: Vector3) -> bool:
		if not is_instance_valid(_boss):
			return false
		return _segment_blocked_by_wall(_boss.global_position, target_pos)
	_cone.blocking_clouds_check = func(target_pos: Vector3) -> bool:
		if not is_instance_valid(_boss):
			return false
		return _segment_blocked_by_cloud(_boss.global_position, target_pos)

func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
	var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
	for c in clouds:
		if not is_instance_valid(c):
			continue
		# Spec §4: only green clouds block breath; other colors pass through.
		if c.get("base_color") != "green":
			continue
		if c.has_method("blocks_segment") and c.blocks_segment(from, to):
			return true
	return false

func _segment_blocked_by_wall(from: Vector3, to: Vector3) -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.has_method("blocks_segment") and w.blocks_segment(from, to):
			if w.has_method("take_damage"):
				w.take_damage(1)
			return true
	return false

func _on_execution_end() -> void:
	if _cone != null and is_instance_valid(_cone):
		_cone.queue_free()
	_cone = null

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	# Track boss position so the cone stays anchored to the dragon's mouth
	# even if the boss continues moving during the 0.8s execution.
	if is_in_execution() and _cone != null and is_instance_valid(_cone) and _boss != null:
		_cone.global_position = _boss.global_position

func current_aim() -> Vector3:
	return _aim_dir

func set_aim(new_dir: Vector3) -> void:
	# For purple pull cone redirection. Updates aim during windup and re-aims live cone.
	new_dir.y = 0.0
	if new_dir.length() < 0.01:
		return
	_aim_dir = new_dir.normalized()
	if _cone != null and is_instance_valid(_cone):
		_cone.set_direction(_aim_dir)

func on_chill_applied(stacks_added: int) -> void:
	if not is_in_windup():
		return
	if stacks_added <= 0:
		return
	extend_windup(CHILL_EXTEND_PER_STACK * float(stacks_added))
