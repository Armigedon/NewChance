extends Node3D

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

const TICK_INTERVAL: float = 0.5  # ticks per second = 2

@export var lifetime: float = 3.0
@export var radius: float = 2.0
@export var tick_damage: int = 6  # 25% of cast base damage default

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
	var mesh: MeshInstance3D = $Mesh as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE * (radius / 2.0)
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

func _tick_enemies() -> void:
	var area: Area3D = $HitArea
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		if not body.is_in_group("enemy"):
			continue
		DamagePipeline.apply(body, tick_damage, modifier_stack, base_color, global_position, "cloud")
