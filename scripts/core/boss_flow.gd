extends Node

enum State { IDLE, PENDING, ACTIVE, WON, LOST }

signal state_changed(new_state: State)

var state: State = State.IDLE

func trigger_boss() -> void:
	if state == State.WON:
		return
	_set_state(State.PENDING)

func enter_arena() -> void:
	if state == State.PENDING:
		_set_state(State.ACTIVE)

func boss_killed() -> void:
	if state == State.ACTIVE:
		_set_state(State.WON)

func player_died_in_boss() -> void:
	if state == State.ACTIVE or state == State.PENDING:
		_set_state(State.LOST)

func reset() -> void:
	if state != State.WON:
		_set_state(State.IDLE)

func is_active() -> bool:
	return state == State.PENDING or state == State.ACTIVE

func has_won() -> bool:
	return state == State.WON

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)
