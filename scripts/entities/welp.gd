extends CharacterBody3D

@export var max_hp: int = 30

@export var move_speed: float = 3.6
@export var attack_damage: int = 10
@export var attack_interval: float = 2.0
@export var attack_range: float = 1.0

const SOUL_PICKUP_SCENE: PackedScene = preload("res://scenes/interactables/soul_pickup.tscn")

@export var color: String = "red"
@export var tier: String = "welp"

signal died(welp: Node, color: String)

var hp: int = max_hp
var _attack_cooldown: float = 0.0
var _player: Node = null
var _is_dead: bool = false

func _ready() -> void:
	hp = max_hp
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
	if distance > attack_range:
		velocity.x = to_player.normalized().x * move_speed
		velocity.z = to_player.normalized().z * move_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_cooldown <= 0.0:
			_attack_player()
			_attack_cooldown = attack_interval
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
		_player.take_damage(attack_damage)

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	if hp == 0:
		_is_dead = true
		_drop_souls()
		died.emit(self, color)
		queue_free()

func _drop_souls() -> void:
	# Special "alarm" welps drop nothing (used by time-alarm spawner in T8)
	if color == "alarm":
		return
	# welp: 1 minor; dragon: 2-3 minor; elder: 1 elder + 2-3 minor
	var minor_count: int = 1 if tier == "welp" else (2 + (1 if randf() < 0.5 else 0))
	for i in range(minor_count):
		_spawn_pickup("minor", _random_offset())
	if tier == "elder":
		_spawn_pickup("elder", _random_offset())

func _spawn_pickup(pickup_tier: String, offset: Vector3) -> void:
	var pickup: Area3D = SOUL_PICKUP_SCENE.instantiate()
	pickup.color = color
	pickup.tier = pickup_tier
	pickup.global_position = global_position + offset
	get_parent().add_child(pickup)

func _random_offset() -> Vector3:
	return Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
