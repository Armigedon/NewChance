extends CharacterBody3D

@export var max_hp: int = 30

@export var move_speed: float = 3.6
@export var attack_damage: int = 10
@export var attack_interval: float = 2.0
@export var attack_range: float = 1.0

const SOUL_PICKUP_SCENE: PackedScene = preload("res://scenes/interactables/soul_pickup.tscn")

@export var color: String = "red"
@export var tier: String = "welp"

const KNOCKBACK_DECAY: float = 12.0  # m/s² — knockback impulse decay rate

signal died(welp: Node, color: String)

var hp: int = max_hp
var _attack_cooldown: float = 0.0
var _player: Node = null
var _is_dead: bool = false
var _knockback_velocity: Vector3 = Vector3.ZERO

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
	# Apply knockback impulse on top of tracking velocity, then decay it.
	if _knockback_velocity.length() > 0.01:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _attack_player() -> void:
	if _player != null and _player.has_method("take_damage"):
		_player.take_damage(attack_damage)

func flash_hit(duration: float = 0.12) -> void:
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mesh.material_override = mat
	var original: Color = mat.albedo_color
	mat.albedo_color = Color(1, 1, 1, 1)
	var tw: Tween = create_tween()
	tw.tween_property(mat, "albedo_color", original, duration)

func apply_knockback(direction: Vector3, force: float) -> void:
	direction.y = 0.0
	if direction.length() < 0.001:
		return
	_knockback_velocity += direction.normalized() * force

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
	# Boss-summoned whelps also drop nothing
	if color == "alarm" or color == "boss":
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
	var pickup_pos: Vector3 = global_position + offset
	get_parent().add_child(pickup)
	pickup.global_position = pickup_pos

func _random_offset() -> Vector3:
	return Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
