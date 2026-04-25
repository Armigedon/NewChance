extends CharacterBody3D

const MAX_HP: int = 100
const MOVE_SPEED: float = 5.0
const DASH_DISTANCE: float = 4.0
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 2.0
const IFRAME_DURATION: float = 0.2

signal died
signal hp_changed(new_hp: int)

var hp: int = MAX_HP
var _is_dead: bool = false
var _dash_cooldown_remaining: float = 0.0
var _iframe_remaining: float = 0.0
var _dash_velocity: Vector3 = Vector3.ZERO
var _dash_time_remaining: float = 0.0

func _process(delta: float) -> void:
	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining = max(0.0, _dash_cooldown_remaining - delta)
	if _iframe_remaining > 0.0:
		_iframe_remaining = max(0.0, _iframe_remaining - delta)
	if _dash_time_remaining > 0.0:
		_dash_time_remaining = max(0.0, _dash_time_remaining - delta)
	if Input.is_action_just_pressed("dash"):
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var dash_dir: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
		if dash_dir.length() > 0.01:
			try_dash(dash_dir.normalized())

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _dash_time_remaining > 0.0:
		velocity.x = _dash_velocity.x
		velocity.z = _dash_velocity.z
	else:
		var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var direction: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func can_dash() -> bool:
	return _dash_cooldown_remaining <= 0.0 and not _is_dead

func try_dash(direction: Vector3) -> bool:
	if not can_dash():
		return false
	_dash_velocity = direction * (DASH_DISTANCE / DASH_DURATION)
	_dash_time_remaining = DASH_DURATION
	_dash_cooldown_remaining = DASH_COOLDOWN
	_iframe_remaining = IFRAME_DURATION
	return true

func is_invincible() -> bool:
	return _iframe_remaining > 0.0

func take_damage(amount: int) -> void:
	if _is_dead or is_invincible():
		return
	hp = max(0, hp - amount)
	hp_changed.emit(hp)
	if hp == 0:
		_is_dead = true
		died.emit()

func reset_run_state() -> void:
	hp = MAX_HP
	_is_dead = false
	hp_changed.emit(hp)
