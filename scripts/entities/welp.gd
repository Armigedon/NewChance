extends CharacterBody3D

const MAX_HP: int = 30
const MOVE_SPEED: float = 3.0
const ATTACK_DAMAGE: int = 10
const ATTACK_INTERVAL: float = 1.5
const ATTACK_RANGE: float = 1.5

@export var color: String = "red"

signal died(welp: Node, color: String)

var hp: int = MAX_HP
var _attack_cooldown: float = 0.0
var _player: Node = null
var _is_dead: bool = false

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2  # match Sword mask
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
	var distance: float = to_player.length()
	if distance > ATTACK_RANGE:
		velocity.x = to_player.normalized().x * MOVE_SPEED
		velocity.z = to_player.normalized().z * MOVE_SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_cooldown <= 0.0:
			_attack_player()
			_attack_cooldown = ATTACK_INTERVAL
	if _attack_cooldown > 0.0:
		_attack_cooldown = max(0.0, _attack_cooldown - delta)
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _attack_player() -> void:
	if _player != null and _player.has_method("take_damage"):
		_player.take_damage(ATTACK_DAMAGE)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	if hp == 0:
		_is_dead = true
		died.emit(self, color)
		queue_free()
