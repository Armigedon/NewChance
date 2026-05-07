extends Node

const HEAT_BUILD_PER_SEC: float = 5.0
const HEAT_DECAY_PER_SEC: float = 2.0
const HEAT_CAP: float = 100.0
const TIME_ALARM_FULL_SECONDS: float = 300.0  # 5 minutes
const DRAGON_FLOOR_S: float = 20.0
const ELDER_FLOOR_S: float = 45.0

var _heat: Dictionary = {}
var _player_in_corner: String = ""
var _player_upstairs: bool = false
var _upstairs_time: float = 0.0
var _last_dragon_spawn_msec: int = -1
var _last_elder_spawn_msec: int = -1

func _ready() -> void:
	reset()

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	for color in Palette.ALL:
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
	return 1.0 + (heat / HEAT_CAP) * 2.0

func enemy_hp_factor() -> float:
	return 1.0

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

func record_tier_spawn(tier: String) -> void:
	var now: int = Time.get_ticks_msec()
	if tier == "dragon":
		_last_dragon_spawn_msec = now
	elif tier == "elder":
		_last_elder_spawn_msec = now

func can_spawn_tier(tier: String) -> bool:
	var now: int = Time.get_ticks_msec()
	if tier == "dragon":
		return _last_dragon_spawn_msec < 0 or now - _last_dragon_spawn_msec >= int(DRAGON_FLOOR_S * 1000.0)
	if tier == "elder":
		return _last_elder_spawn_msec < 0 or now - _last_elder_spawn_msec >= int(ELDER_FLOOR_S * 1000.0)
	return true  # welps and unknown tiers always spawnable

func time_alarm_factor() -> float:
	return min(1.0, _upstairs_time / TIME_ALARM_FULL_SECONDS)

func reset() -> void:
	_heat.clear()
	for color in Palette.ALL:
		_heat[color] = 0.0
	_player_in_corner = ""
	_player_upstairs = false
	_upstairs_time = 0.0
	_last_dragon_spawn_msec = -1
	_last_elder_spawn_msec = -1
