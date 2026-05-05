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
			_cooldown_remaining = 0.5

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
	# TODO(spec §4): validate target is in-arena and not overlapping a bone wall.
	# Deferred — needs an arena-boundary API; current code can land anywhere on
	# the XZ plane.
	var angle: float = randf() * TAU
	var dist: float = randf_range(MIN_HOP_DISTANCE, MAX_HOP_DISTANCE)
	_jump_target = _boss.global_position + Vector3(cos(angle) * dist, 0, sin(angle) * dist)

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
