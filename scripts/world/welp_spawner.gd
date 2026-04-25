extends Node3D

const WELP_SCENE: PackedScene = preload("res://scenes/entities/welp.tscn")
const WELP_BLUE_SCENE: PackedScene = preload("res://scenes/entities/welp_blue.tscn")

@export var spawn_interval: float = 1.0
@export var max_alive: int = 12
@export var spawn_radius: float = 12.0
# Welps must spawn at least this far from the player. Prevents pop-in directly on top.
@export var min_dist_from_player: float = 5.0

var _timer: float = 0.0
var _alive_count: int = 0

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= spawn_interval and _alive_count < max_alive:
		_timer = 0.0
		_spawn_welp()

func _spawn_welp() -> void:
	var scene: PackedScene = WELP_SCENE if randf() < 0.5 else WELP_BLUE_SCENE
	var welp: CharacterBody3D = scene.instantiate()
	welp.global_position = _pick_spawn_position()
	welp.died.connect(_on_welp_died)
	get_parent().add_child(welp)
	_alive_count += 1

func _pick_spawn_position() -> Vector3:
	var player_pos: Vector3 = _get_player_pos()
	# Try several angles; return the first that lands far enough from the player.
	for i in range(8):
		var angle: float = randf() * TAU
		var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
		var pos: Vector3 = global_position + offset
		if player_pos == Vector3.INF:
			return pos
		if pos.distance_to(player_pos) >= min_dist_from_player:
			return pos
	# Fallback after 8 misses: spawn on the spawner-side of the player (opposite from where they
	# stand relative to the spawner) so we don't pop in on top of them.
	if player_pos == Vector3.INF:
		return global_position + Vector3(spawn_radius, 1.0, 0)
	var away_dir: Vector3 = (global_position - player_pos)
	away_dir.y = 0.0
	if away_dir.length() < 0.001:
		away_dir = Vector3.FORWARD
	return global_position + away_dir.normalized() * spawn_radius + Vector3(0, 1.0, 0)

func _get_player_pos() -> Vector3:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return Vector3.INF
	return players[0].global_position

func _on_welp_died(_welp: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
