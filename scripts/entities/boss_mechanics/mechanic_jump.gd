extends "res://scripts/entities/boss_mechanic.gd"

# Conditional jump: triggered (not cooldowned) when boss is stationary
# while taking damage. Counters DoT-park strategy.
# NOTE: TelegraphScript is inherited from boss_mechanic.gd — do not re-declare.

const STATIONARY_THRESHOLD_M: float = 1.0
const STATIONARY_WINDOW_S: float = 2.0
const MIN_GAP_S: float = 3.0
const MIN_HOP_DISTANCE: float = 4.0
const MAX_HOP_DISTANCE: float = 8.0
const LAND_DAMAGE: int = 15
const LAND_RADIUS: float = 1.0
# Arena bounds — matches the courtyard scene's floor cylinder (radius 18, centered
# at origin). Boss must land at least ARENA_MARGIN inside the edge so it isn't
# clipping the wall meshes.
const ARENA_CENTER: Vector3 = Vector3.ZERO
const ARENA_RADIUS: float = 18.0
const ARENA_MARGIN: float = 1.5
# Stay clear of bone walls so we don't teleport on top of one and clip its collider.
const WALL_AVOIDANCE_DISTANCE: float = 1.5
# Cap rejection sampling so a wall-cluttered arena can't infinite-loop.
const SAMPLE_RETRIES: int = 8
const RETRY_COOLDOWN_S: float = 0.5

var _last_jump_time_msec: int = -10000
var _jump_target: Vector3 = Vector3.ZERO

func _init() -> void:
	unlock_phase = 1
	is_big = false
	cooldowns_by_phase = {1: 0.5, 2: 0.5, 3: 0.5}
	windup_duration = 1.0
	execution_duration = 0.6

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if _telegraph.state == TelegraphScript.State.IDLE and _cooldown_remaining <= 0.0:
		if _should_trigger():
			trigger(current_phase)
		else:
			_cooldown_remaining = RETRY_COOLDOWN_S

func _should_trigger() -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	if Time.get_ticks_msec() - _last_jump_time_msec < int(MIN_GAP_S * 1000.0):
		return false
	if _boss.position_change_in_window() >= STATIONARY_THRESHOLD_M:
		return false
	if not _boss.damage_taken_within(STATIONARY_WINDOW_S):
		return false
	return true

func _on_windup_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_jump_target = _pick_jump_target()

func _pick_jump_target() -> Vector3:
	# Rejection-sample a target within the arena and clear of bone walls.
	# Falls through to the last candidate (clamped to arena) if all retries fail
	# rather than infinite-looping or returning an out-of-bounds position.
	var origin: Vector3 = _boss.global_position
	var candidate: Vector3 = origin
	for _i in range(SAMPLE_RETRIES):
		var angle: float = randf() * TAU
		var dist: float = randf_range(MIN_HOP_DISTANCE, MAX_HOP_DISTANCE)
		candidate = origin + Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		candidate = _clamp_to_arena(candidate)
		if not _overlaps_bone_wall(candidate):
			return candidate
	return _clamp_to_arena(candidate)

func _clamp_to_arena(pos: Vector3) -> Vector3:
	var max_dist: float = ARENA_RADIUS - ARENA_MARGIN
	var offset: Vector3 = pos - ARENA_CENTER
	offset.y = 0.0
	if offset.length() <= max_dist:
		return Vector3(pos.x, ARENA_CENTER.y, pos.z)
	var clamped: Vector3 = ARENA_CENTER + offset.normalized() * max_dist
	return Vector3(clamped.x, ARENA_CENTER.y, clamped.z)

func _overlaps_bone_wall(pos: Vector3) -> bool:
	var pos_flat: Vector2 = Vector2(pos.x, pos.z)
	for w in get_tree().get_nodes_in_group("bone_wall"):
		if not is_instance_valid(w):
			continue
		var w_flat: Vector2 = Vector2(w.global_position.x, w.global_position.z)
		if pos_flat.distance_to(w_flat) <= WALL_AVOIDANCE_DISTANCE:
			return true
	return false

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	# TODO(spec §3): cancel any in-progress big mechanic so its lingering effects
	# (breath cone, mark zone, etc.) don't keep ticking from the boss's old
	# position. Deferred — boss_telegraph needs a cancel() path that frees the
	# associated effect scene without firing _on_execution_end damage.
	_boss.global_position = _jump_target
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		# Flat XZ distance — consistent with mark/cone treatment.
		var p_flat: Vector2 = Vector2(p.global_position.x, p.global_position.z)
		var t_flat: Vector2 = Vector2(_jump_target.x, _jump_target.z)
		if p_flat.distance_to(t_flat) <= LAND_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(LAND_DAMAGE)
	_last_jump_time_msec = Time.get_ticks_msec()
	ScreenShake.shake(0.04, 0.1)
