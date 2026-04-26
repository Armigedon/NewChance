extends Node3D
class_name CastBase

@export var base_damage: int = 25
@export var lifetime: float = 3.0

var modifier_stack: Array[String] = []
var _age: float = 0.0

func configure(skill: Skill) -> void:
	modifier_stack = skill.modifier_stack.duplicate()
	# Same-color minor souls deepen base damage by 30% per stack
	var same_color_count: int = skill.modifier_count_for(skill.base_color)
	base_damage = int(base_damage * (1.0 + 0.3 * same_color_count))

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

func _on_hit_enemy(enemy: Node) -> void:
	if not enemy.has_method("take_damage"):
		return
	enemy.take_damage(base_damage)
	for color in modifier_stack:
		_apply_modifier(enemy, color)
	# Visual feedback per skill hit.
	if enemy.has_method("flash_hit"):
		enemy.flash_hit()
	if enemy.has_method("apply_knockback"):
		var dir: Vector3 = enemy.global_position - global_position
		var force: float = _knockback_force_for(enemy)
		enemy.apply_knockback(dir, force)
	ScreenShake.shake(0.15, 0.10)

func _apply_modifier(enemy: Node, _color: String) -> void:
	# Phase 2 stub: each modifier adds 10% damage. Phase 3+ will add real elemental effects.
	if enemy.has_method("take_damage"):
		enemy.take_damage(int(base_damage * 0.1))

func _knockback_force_for(enemy: Node) -> float:
	# Boss has no "tier" property; treat as boss → 2.0
	if not "tier" in enemy:
		return 2.0
	match enemy.tier:
		"welp": return 5.5
		"dragon": return 4.0
		"elder": return 4.0
		_: return 5.5
