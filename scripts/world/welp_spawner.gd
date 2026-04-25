extends Node3D

const WELP_SCENE: PackedScene = preload("res://scenes/entities/welp.tscn")
const WELP_BLUE_SCENE: PackedScene = preload("res://scenes/entities/welp_blue.tscn")

@export var spawn_interval: float = 1.0
@export var max_alive: int = 12
@export var spawn_radius: float = 12.0

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
	var angle: float = randf() * TAU
	var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
	welp.global_position = global_position + offset
	welp.died.connect(_on_welp_died)
	get_parent().add_child(welp)
	_alive_count += 1

func _on_welp_died(_welp: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
