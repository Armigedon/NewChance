extends Node3D

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

const TICK_INTERVAL: float = 0.5  # ticks per second = 2

@export var lifetime: float = 3.0
@export var radius: float = 2.0
@export var tick_damage: int = 6  # 25% of cast base damage default

func _ready() -> void:
	add_to_group("damage_cloud")

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
		# Clouds outlive their originating cast and may be spawned boss-side too,
		# so we don't pass a SkillSystem here. Elder modifier dispatch is a no-op
		# for cloud ticks per Task 8 of the soul/skill economy redesign.
		DamagePipeline.apply(body, tick_damage, modifier_stack, base_color, global_position, "cloud", null, null)

func blocks_segment(from: Vector3, to: Vector3) -> bool:
	# Project to XZ plane to match the breath cone's flat top-down treatment.
	var flat_from: Vector3 = Vector3(from.x, 0.0, from.z)
	var flat_to: Vector3 = Vector3(to.x, 0.0, to.z)
	var center: Vector3 = Vector3(global_position.x, 0.0, global_position.z)
	var seg: Vector3 = flat_to - flat_from
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 0.0001:
		return flat_from.distance_to(center) <= radius
	var t: float = clampf((center - flat_from).dot(seg) / seg_len_sq, 0.0, 1.0)
	var closest: Vector3 = flat_from + seg * t
	return closest.distance_to(center) <= radius
