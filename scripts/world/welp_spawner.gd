extends Node3D

const WELP_SCENE: PackedScene = preload("res://scenes/entities/welp.tscn")

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
	var welp: CharacterBody3D = WELP_SCENE.instantiate()
	var angle: float = randf() * TAU
	var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
	welp.global_position = global_position + offset
	welp.died.connect(_on_welp_died)
	get_parent().add_child(welp)
	_alive_count += 1

func _on_welp_died(_welp: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
