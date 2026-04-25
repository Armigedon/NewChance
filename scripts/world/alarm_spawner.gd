extends Node3D

# Spawns "alarm welps" near the staircase as time_alarm_factor ramps up.
# Welps with color="alarm" drop nothing (welp.gd's _drop_souls handles this).

const WELP_SCENE: PackedScene = preload("res://scenes/entities/welp.tscn")

@export var max_alive: int = 6
@export var spawn_radius: float = 3.0
@export var base_interval: float = 8.0  # at full alarm; effective interval scales down with factor

var _timer: float = 0.0
var _alive_count: int = 0

func _process(delta: float) -> void:
	var f: float = Escalation.time_alarm_factor()
	if f < 0.2:  # don't spawn alarm welps until 20% of full alarm
		_timer = 0.0
		return
	_timer += delta
	# 8s at f=0.2 → ~3.6s at f=0.5 → 2s at f=1.0
	var interval: float = base_interval / (0.5 + f * 3.0)
	if _timer >= interval and _alive_count < max_alive:
		_timer = 0.0
		_spawn()

func _spawn() -> void:
	var welp: CharacterBody3D = WELP_SCENE.instantiate()
	welp.color = "alarm"  # welp.gd._drop_souls returns early for "alarm" color → no drops
	var angle: float = randf() * TAU
	var spawn_pos: Vector3 = global_position + Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
	welp.died.connect(_on_died)
	get_parent().add_child(welp)
	welp.global_position = spawn_pos
	# Recolor mesh dark/alarm-tinted so the player can tell it's not a normal red welp
	var mesh: MeshInstance3D = welp.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if mat != null:
			mat = mat.duplicate() as StandardMaterial3D
			mesh.material_override = mat
			mat.albedo_color = Color(0.15, 0.15, 0.18, 1)
	_alive_count += 1

func _on_died(_welp: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
