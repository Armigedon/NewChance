extends CharacterBody3D

const MAX_HP: int = 100
const MOVE_SPEED: float = 5.0

signal died
signal hp_changed(new_hp: int)

var hp: int = MAX_HP
var _is_dead: bool = false

func _physics_process(_delta: float) -> void:
	if _is_dead:
		return
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3 = Vector3(input_dir.x, 0, input_dir.y)
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	velocity.y -= 9.8 * _delta if not is_on_floor() else 0.0
	move_and_slide()

func take_damage(amount: int) -> void:
	if _is_dead:
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
