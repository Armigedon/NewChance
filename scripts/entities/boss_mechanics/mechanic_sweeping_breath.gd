extends "res://scripts/entities/boss_mechanic.gd"

const BreathConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const CONE_LENGTH: float = 7.0
const CONE_ANGLE_DEG: float = 75.0
const TICK_DAMAGE: int = 15
const SWEEP_TOTAL_DEG: float = 90.0
const CHILL_EXTEND_PER_STACK: float = 0.15

var _cone: Node3D = null
var _aim_dir: Vector3 = Vector3.FORWARD
var _sweep_dir_sign: float = 1.0
var _sweep_progress: float = 0.0
var _aim_locked_at_windup: Vector3 = Vector3.FORWARD  # the "center" aim direction
# Boss origin snapshot at execution start — see mechanic_static_breath.gd for why.
var _origin_snapshot: Vector3 = Vector3.ZERO

func _init() -> void:
	unlock_phase = 2
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 12.0, 3: 8.0}
	windup_duration = 0.8
	execution_duration = 2.0

func _on_windup_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	# Lock the center aim toward player; sweep arc spans ±SWEEP_TOTAL_DEG/2 from this.
	var players: Array = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		var p: Node = players[0]
		var to_p: Vector3 = p.global_position - _boss.global_position
		to_p.y = 0.0
		if to_p.length() > 0.01:
			_aim_dir = to_p.normalized()
	_aim_locked_at_windup = _aim_dir
	_sweep_dir_sign = 1.0 if randf() < 0.5 else -1.0
	_sweep_progress = 0.0

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_origin_snapshot = _boss.global_position
	# Start cone aimed at -half_arc * sign (so the sweep ends at +half_arc * sign).
	var start_aim: Vector3 = _aim_locked_at_windup.rotated(Vector3.UP, deg_to_rad(SWEEP_TOTAL_DEG * 0.5 * -_sweep_dir_sign))
	_cone = BreathConeScene.instantiate()
	_boss.get_parent().add_child(_cone)
	_cone.configure(_boss.global_position, start_aim, CONE_LENGTH, CONE_ANGLE_DEG, execution_duration, TICK_DAMAGE)
	_cone.blocking_walls_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_wall(_origin_snapshot, target_pos)
	_cone.blocking_clouds_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_cloud(_origin_snapshot, target_pos)

func _on_execution_end() -> void:
	if _cone != null and is_instance_valid(_cone):
		_cone.queue_free()
	_cone = null

func cleanup() -> void:
	_on_execution_end()

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if is_in_execution() and _cone != null and is_instance_valid(_cone) and _boss != null:
		_sweep_progress = clampf(_sweep_progress + delta / execution_duration, 0.0, 1.0)
		# Linearly interpolate aim from -half_arc*sign to +half_arc*sign across [0, 1].
		# At p=0: offset = -45° * sign (start edge). At p=1: offset = +45° * sign (end edge).
		var current_offset_deg: float = SWEEP_TOTAL_DEG * (_sweep_progress - 0.5) * _sweep_dir_sign
		var live_aim: Vector3 = _aim_locked_at_windup.rotated(Vector3.UP, deg_to_rad(current_offset_deg))
		_cone.set_direction(live_aim)
		_cone.global_position = _boss.global_position

func on_chill_applied(stacks_added: int) -> void:
	if not is_in_windup():
		return
	if stacks_added <= 0:
		return
	extend_windup(CHILL_EXTEND_PER_STACK * float(stacks_added))

func on_pull_during_windup(pull_origin: Vector3, rotation_deg: float) -> void:
	if not is_in_windup():
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	var to_pull: Vector3 = pull_origin - _boss.global_position
	to_pull.y = 0.0
	if to_pull.length() < 0.01:
		return
	var aim_2d: Vector2 = Vector2(_aim_dir.x, _aim_dir.z)
	var pull_2d: Vector2 = Vector2(to_pull.x, to_pull.z).normalized()
	var cross_z: float = aim_2d.cross(pull_2d)
	if absf(cross_z) < 0.001:
		return  # parallel/anti-parallel: no meaningful side
	_aim_dir = _aim_dir.rotated(Vector3.UP, deg_to_rad(rotation_deg) * signf(cross_z))
	_aim_locked_at_windup = _aim_dir
