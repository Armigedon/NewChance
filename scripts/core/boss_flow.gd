extends Node

enum State { IDLE, PENDING, ACTIVE, WON, LOST }

signal state_changed(new_state: State)

var state: State = State.IDLE

# Snapshot of player's SkillSystem.to_dict() taken at boss-trigger descent.
# New player instances (across main_hall ↔ courtyard scene swaps during boss
# flow) restore from this in their _ready. Cleared on player death in boss
# or on next normal extraction.
var retained_skills: Dictionary = {}

func set_retained_skills(d: Dictionary) -> void:
	retained_skills = d.duplicate(true)

func clear_retained_skills() -> void:
	retained_skills.clear()

func trigger_boss() -> void:
	if state == State.WON:
		return
	_set_state(State.PENDING)

func enter_arena() -> void:
	if state == State.PENDING:
		_set_state(State.ACTIVE)

func boss_killed() -> void:
	# Defensive: accept either ACTIVE or PENDING in case the gate trigger that
	# was supposed to flip PENDING→ACTIVE never fired (e.g., player took a
	# different path into the arena).
	if state == State.ACTIVE or state == State.PENDING:
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
