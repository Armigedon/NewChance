extends Node3D
class_name CastBase

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

@export var base_damage: int = 25
@export var lifetime: float = 3.0

var modifier_stack: Array[String] = []
var base_color: String = ""
var same_color_count: int = 0
var size_multiplier: float = 1.0

var _age: float = 0.0

func configure(skill: Skill) -> void:
	modifier_stack = skill.modifier_stack.duplicate()
	base_color = skill.base_color
	same_color_count = skill.modifier_count_for(skill.base_color)
	base_damage = int(base_damage * (1.0 + 0.2 * same_color_count))
	size_multiplier = 1.0 + 0.2 * same_color_count

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

# Hits a single enemy through the unified damage pipeline.
func _hit_target(target: Node, source_pos: Vector3) -> void:
	DamagePipeline.apply(target, base_damage, modifier_stack, base_color, source_pos)

# Damages all enemies in a sphere around center; called by AoE casts.
func _damage_aoe(center: Vector3, radius: float) -> void:
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if "_is_dead" in e and e._is_dead:
			continue
		if e.global_position.distance_to(center) <= radius:
			_hit_target(e, center)

# Knockback helper used by some casts.
func _knockback_force_for(enemy: Node) -> float:
	if not "tier" in enemy:
		return 2.0
	match enemy.tier:
		"welp": return 5.5
		"dragon": return 4.0
		"elder": return 4.0
		_: return 5.5
