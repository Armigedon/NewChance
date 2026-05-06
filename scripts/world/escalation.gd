extends Node

const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
const HEAT_BUILD_PER_SEC: float = 5.0
const HEAT_DECAY_PER_SEC: float = 2.0
const HEAT_CAP: float = 100.0
const TIME_ALARM_FULL_SECONDS: float = 300.0  # 5 minutes

var _heat: Dictionary = {}
var _player_in_corner: String = ""
var _player_upstairs: bool = false
var _upstairs_time: float = 0.0
# Phase 9: legacy field. The setter (set_in_run_elder_count) was removed when
# elder souls became modifier drafts (no longer ramp difficulty). Field stays
# at 0 for the lifetime of the run; enemy_hp_factor / spawn_rate_factor / reset
# still reference it as 0, leaving their formulas intact for future use.
var _in_run_elders: int = 0

func _ready() -> void:
	reset()

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	for color in COLORS:
		var h: float = _heat[color]
		if color == _player_in_corner:
			h = min(HEAT_CAP, h + HEAT_BUILD_PER_SEC * delta)
		else:
			h = max(0.0, h - HEAT_DECAY_PER_SEC * delta)
		_heat[color] = h
	if _player_upstairs:
		_upstairs_time += delta

func corner_heat(color: String) -> float:
	return _heat.get(color, 0.0)

func current_corner() -> String:
	return _player_in_corner

func set_player_in_corner(color: String) -> void:
	_player_in_corner = color

func set_player_upstairs(value: bool) -> void:
	_player_upstairs = value
	if not value:
		_upstairs_time = 0.0

func spawn_rate_factor(heat: float) -> float:
	var heat_factor: float = 1.0 + (heat / HEAT_CAP) * 2.0
	var elder_factor: float = 1.0 + 0.12 * float(_in_run_elders)
	return heat_factor * elder_factor

func enemy_hp_factor() -> float:
	return 1.0 + 0.08 * float(_in_run_elders)

func roll_tier(heat: float) -> String:
	if heat < 30.0:
		return "welp"
	if heat < 70.0:
		return "dragon" if randf() < 0.25 else "welp"
	var r: float = randf()
	if r < 0.15:
		return "elder"
	if r < 0.50:
		return "dragon"
	return "welp"

func time_alarm_factor() -> float:
	return min(1.0, _upstairs_time / TIME_ALARM_FULL_SECONDS)

func reset() -> void:
	_heat.clear()
	for color in COLORS:
		_heat[color] = 0.0
	_player_in_corner = ""
	_player_upstairs = false
	_upstairs_time = 0.0
	_in_run_elders = 0
