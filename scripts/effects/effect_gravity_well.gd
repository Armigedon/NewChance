extends Node3D

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

const TICK_INTERVAL: float = 0.5
const PULL_FORCE_PER_FRAME: float = 0.05  # constant velocity-add toward center per physics frame

@export var lifetime: float = 2.0
@export var radius: float = 2.0
@export var tick_damage: int = 6

var modifier_stack: Array = []
var base_color: String = ""

var _age: float = 0.0
var _tick_timer: float = 0.0

func configure(p_lifetime: float, p_radius: float, p_tick_damage: int, p_modifier_stack: Array, p_base_color: String) -> void:
	lifetime = p_lifetime
	radius = p_radius
	tick_damage = p_tick_damage
	modifier_stack = p_modifier_stack.duplicate()
	base_color = p_base_color
	var shape: CollisionShape3D = $HitArea/CollisionShape3D
	if shape != null and shape.shape is SphereShape3D:
		var s: SphereShape3D = shape.shape.duplicate() as SphereShape3D
		s.radius = radius
		shape.shape = s

func _process(delta: float) -> void:
	_age += delta
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_tick_enemies()
	if _age >= lifetime:
		queue_free()

func _physics_process(_delta: float) -> void:
	var area: Area3D = $HitArea
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		if not body.is_in_group("enemy"):
			continue
		if body.has_method("apply_pull_toward"):
			body.apply_pull_toward(global_position, PULL_FORCE_PER_FRAME)

func _tick_enemies() -> void:
	var area: Area3D = $HitArea
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		if not body.is_in_group("enemy"):
			continue
		# Player-side effect — pass the player's SkillSystem so elder modifier
		# hooks fire on each tick.
		DamagePipeline.apply(body, tick_damage, modifier_stack, base_color, global_position, "void_well", null, _player_skill_system(), _player_node())

func _player_skill_system() -> Node:
	var player: Node = _player_node()
	if player == null:
		return null
	if not player.has_node("SkillSystem"):
		return null
	return player.get_node("SkillSystem")

func _player_node() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if player == null or not is_instance_valid(player):
		return null
	return player
