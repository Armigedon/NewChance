extends "res://scripts/entities/boss_mechanic.gd"

const BreathConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const CONE_LENGTH: float = 12.0  # was 7.0; subsystem C bump
const CONE_ANGLE_DEG: float = 100.0  # was 75.0; subsystem C bump
const TICK_DAMAGE: int = 10
const CHILL_EXTEND_PER_STACK: float = 0.15

var _cone: Node3D = null
var _aim_dir: Vector3 = Vector3.FORWARD
# Boss origin snapshot at execution start — wall-block segments use this fixed
# point so the boss walking past a wall mid-cone doesn't change which walls
# block the line of fire. Cone visual still tracks the boss's mouth in tick().
var _origin_snapshot: Vector3 = Vector3.ZERO

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
	_origin_snapshot = _boss.global_position
	_cone = BreathConeScene.instantiate()
	_boss.get_parent().add_child(_cone)
	_cone.configure(_boss.global_position, _aim_dir, CONE_LENGTH, CONE_ANGLE_DEG, execution_duration, TICK_DAMAGE)
	# Wall + cloud block checks use the snapshotted origin (not live boss pos) so
	# the wall-block interaction stays anchored to where the dragon's mouth was
	# when the cone fired — otherwise walking past a wall mid-cone toggles block.
	_cone.blocking_walls_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_wall(_origin_snapshot, target_pos)
	_cone.blocking_clouds_check = func(target_pos: Vector3) -> bool:
		return _segment_blocked_by_cloud(_origin_snapshot, target_pos)

func _on_execution_end() -> void:
	if _cone != null and is_instance_valid(_cone):
		_cone.queue_free()
	_cone = null

func cleanup() -> void:
	# Boss died mid-execution — kill the cone so it stops ticking damage.
	_on_execution_end()

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

func on_pull_during_windup(pull_origin: Vector3, rotation_deg: float) -> void:
	if not is_in_windup():
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	var to_pull: Vector3 = pull_origin - _boss.global_position
	to_pull.y = 0.0
	if to_pull.length() < 0.01:
		return
	# Rotate aim toward the pull origin's side. Cross sign tells us which way.
	# When the pull is parallel or anti-parallel to aim (cross_z near zero) there's
	# no meaningful "side", so no rotation is applied — pulling from directly in
	# front of or behind the cone is a wash.
	var aim_2d: Vector2 = Vector2(_aim_dir.x, _aim_dir.z)
	var pull_2d: Vector2 = Vector2(to_pull.x, to_pull.z).normalized()
	var cross_z: float = aim_2d.cross(pull_2d)
	if absf(cross_z) < 0.001:
		return
	set_aim(_aim_dir.rotated(Vector3.UP, deg_to_rad(rotation_deg) * signf(cross_z)))

func on_chill_applied(stacks_added: int) -> void:
	if not is_in_windup():
		return
	if stacks_added <= 0:
		return
	extend_windup(CHILL_EXTEND_PER_STACK * float(stacks_added))
