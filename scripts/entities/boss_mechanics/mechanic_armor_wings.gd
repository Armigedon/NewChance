extends "res://scripts/entities/boss_mechanic.gd"

const REDUCTION_START: float = 0.6

var _active_remaining: float = 0.0
var _active_total: float = 0.0

func _init() -> void:
	unlock_phase = 2
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 20.0, 3: 15.0}
	windup_duration = 0.5
	execution_duration = 4.0

func _on_execution_start() -> void:
	_active_remaining = execution_duration
	_active_total = execution_duration

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if _active_remaining > 0.0:
		_active_remaining = max(0.0, _active_remaining - delta)

func _on_execution_end() -> void:
	# Defensive: zero remaining so future _on_execution_end overrides can't leave
	# a stale residual that would let current_reduction_pct return > 0 after the
	# window has expired.
	_active_remaining = 0.0

func current_reduction_pct() -> float:
	if _active_remaining <= 0.0 or _active_total <= 0.0:
		return 0.0
	var t: float = _active_remaining / _active_total
	return REDUCTION_START * t

# is_active is reserved for Task 20 (red burn pierces wings), which will need to
# query "is wings active" without invoking the reduction-pct math path.
func is_active() -> bool:
	return _active_remaining > 0.0
