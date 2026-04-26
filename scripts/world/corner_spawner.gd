extends Node3D

const WELP_SCENES: Dictionary = {
	"red": preload("res://scenes/entities/welp.tscn"),
	"blue": preload("res://scenes/entities/welp_blue.tscn"),
	"green": preload("res://scenes/entities/welp_green.tscn"),
	"purple": preload("res://scenes/entities/welp_purple.tscn"),
	"gold": preload("res://scenes/entities/welp_gold.tscn"),
	"white": preload("res://scenes/entities/welp_white.tscn"),
}
const DRAGON_SCENE: PackedScene = preload("res://scenes/entities/dragon.tscn")
const ELDER_DRAGON_SCENE: PackedScene = preload("res://scenes/entities/elder_dragon.tscn")

const COLOR_ALBEDO: Dictionary = {
	"red": Color(0.5, 0.1, 0.1, 1),
	"blue": Color(0.2, 0.4, 0.85, 1),
	"green": Color(0.2, 0.6, 0.2, 1),
	"purple": Color(0.4, 0.2, 0.6, 1),
	"gold": Color(0.8, 0.7, 0.2, 1),
	"white": Color(0.8, 0.8, 0.78, 1),
}

@export var color: String = "red"
@export var base_spawn_interval: float = 3.0  # at heat 0
@export var max_alive: int = 4
@export var spawn_radius: float = 4.0
@export var min_dist_from_player: float = 5.0

var _timer: float = 0.0
var _alive_count: int = 0

func _process(delta: float) -> void:
	var heat: float = Escalation.corner_heat(color)
	var effective_interval: float = base_spawn_interval / Escalation.spawn_rate_factor(heat)
	_timer += delta
	if _timer >= effective_interval and _alive_count < max_alive:
		_timer = 0.0
		_spawn()

func _spawn() -> void:
	var heat: float = Escalation.corner_heat(color)
	var tier: String = Escalation.roll_tier(heat)
	var scene: PackedScene = _scene_for_tier(tier)
	if scene == null:
		return
	var enemy = scene.instantiate()
	if "max_hp" in enemy:
		enemy.max_hp = int(enemy.max_hp * Escalation.enemy_hp_factor())
	if tier in ["dragon", "elder"]:
		enemy.color = color
		_apply_color_tint(enemy, color)
	var spawn_pos: Vector3 = _pick_spawn_position()
	enemy.died.connect(_on_died)
	get_parent().add_child(enemy)
	enemy.global_position = spawn_pos
	_alive_count += 1

func _scene_for_tier(tier: String) -> PackedScene:
	match tier:
		"welp": return WELP_SCENES.get(color, null)
		"dragon": return DRAGON_SCENE
		"elder": return ELDER_DRAGON_SCENE
		_: return null

func _apply_color_tint(enemy: Node, c: String) -> void:
	var mesh: MeshInstance3D = enemy.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat = mat.duplicate() as StandardMaterial3D
	mesh.material_override = mat
	mat.albedo_color = COLOR_ALBEDO.get(c, COLOR_ALBEDO["red"])

func _pick_spawn_position() -> Vector3:
	var player_pos: Vector3 = _get_player_pos()
	for i in range(8):
		var angle: float = randf() * TAU
		var offset: Vector3 = Vector3(cos(angle) * spawn_radius, 1.0, sin(angle) * spawn_radius)
		var pos: Vector3 = global_position + offset
		if player_pos == Vector3.INF:
			return pos
		if pos.distance_to(player_pos) >= min_dist_from_player:
			return pos
	if player_pos == Vector3.INF:
		return global_position + Vector3(spawn_radius, 1.0, 0)
	var away: Vector3 = (global_position - player_pos)
	away.y = 0.0
	if away.length() < 0.001:
		away = Vector3.FORWARD
	return global_position + away.normalized() * spawn_radius + Vector3(0, 1.0, 0)

func _get_player_pos() -> Vector3:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return Vector3.INF
	return players[0].global_position

func _on_died(_enemy: Node, _color: String) -> void:
	_alive_count = max(0, _alive_count - 1)
