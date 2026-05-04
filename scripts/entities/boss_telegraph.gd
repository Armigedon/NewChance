extends RefCounted
class_name BossTelegraph

# Per-mechanic timing state machine. Each mechanic owns one of these and
# drives it via tick(delta). Signals fire at state transitions so the
# mechanic can wire windup/execution/end behaviors.

enum State { IDLE, WINDUP, EXECUTION }

signal windup_started
signal execution_started
signal execution_ended

var state: int = State.IDLE
var windup_duration: float = 0.0
var execution_duration: float = 0.0
var _timer: float = 0.0

func start_windup() -> void:
	state = State.WINDUP
	_timer = windup_duration
	windup_started.emit()

func tick(delta: float) -> void:
	if state == State.IDLE:
		return
	_timer -= delta
	if _timer <= 0.0:
		if state == State.WINDUP:
			state = State.EXECUTION
			_timer = execution_duration
			execution_started.emit()
		else:  # EXECUTION
			state = State.IDLE
			_timer = 0.0
			execution_ended.emit()

func is_busy() -> bool:
	return state != State.IDLE

func extend_windup(extra: float) -> void:
	# Used by blue chill to delay the windup. Only valid during WINDUP.
	if state != State.WINDUP:
		return
	_timer += extra
