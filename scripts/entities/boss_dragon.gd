extends CharacterBody3D

const MAX_HP: int = 150  # FAST-TEST MODE — design value is 600. Lowered so phases are reachable in playtest.
const MOVE_SPEED: float = 2.0
const PHASE_2_HP_PCT: float = 0.66
const PHASE_3_HP_PCT: float = 0.33

const BOSS_WHELP_SCENE: PackedScene = preload("res://scenes/entities/boss_whelp.tscn")

@export var phase_1_summon_interval: float = 3.0
@export var phase_2_summon_interval: float = 2.0
@export var phase_3_summon_interval: float = 4.0
@export var contact_damage: int = 30
@export var contact_interval: float = 1.5

var hp: int = MAX_HP
var _player: Node = null
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _phase: int = 1
var _is_dead: bool = false

signal phase_changed(new_phase: int)
signal died

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	_find_player()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	if dist > 2.5:
		velocity.x = to_player.normalized().x * MOVE_SPEED
		velocity.z = to_player.normalized().z * MOVE_SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _contact_timer <= 0.0 and _player.has_method("take_damage"):
			_player.take_damage(contact_damage)
			_contact_timer = contact_interval
	if _contact_timer > 0.0:
		_contact_timer = max(0.0, _contact_timer - delta)
	_summon_timer += delta
	var interval: float = _interval_for_phase()
	if _summon_timer >= interval:
		_summon_timer = 0.0
		_summon_whelp()
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _interval_for_phase() -> float:
	match _phase:
		1: return phase_1_summon_interval
		2: return phase_2_summon_interval
		3: return phase_3_summon_interval
		_: return phase_1_summon_interval

func _summon_whelp() -> void:
	var whelp: CharacterBody3D = BOSS_WHELP_SCENE.instantiate()
	if _phase == 3 and "max_hp" in whelp:
		whelp.max_hp = 80
	var angle: float = randf() * TAU
	var spawn_pos: Vector3 = global_position + Vector3(cos(angle) * 5.0, 1.0, sin(angle) * 5.0)
	get_parent().add_child(whelp)
	whelp.global_position = spawn_pos

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		died.emit()
		BossFlow.boss_killed()
		queue_free()

func _check_phase_transition() -> void:
	var pct: float = float(hp) / float(MAX_HP)
	var new_phase: int = _phase
	if pct <= PHASE_3_HP_PCT:
		new_phase = 3
	elif pct <= PHASE_2_HP_PCT:
		new_phase = 2
	if new_phase != _phase:
		_phase = new_phase
		phase_changed.emit(_phase)
