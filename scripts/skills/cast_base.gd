extends Node3D
class_name CastBase

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")

@export var base_damage: int = 25
@export var lifetime: float = 3.0
@export var target_pos: Vector3 = Vector3.ZERO  # cursor position on floor; placed casts spawn here
var spawn_pos: Vector3 = Vector3.ZERO  # initial spawn position for projectile casts; set by caller before add_child

var modifier_stack: Array[String] = []
var base_color: String = ""
var same_color_count: int = 0
var size_multiplier: float = 1.0
var source_tag: String = ""  # debug instrument: identifies this cast in the damage meter log
# Marrow Pierce: how many additional enemies a projectile cast may pass through
# before being freed. Populated by configure() from the active skill's
# elder_modifier_stack_count("marrow_pierce"). Per-projectile.
var pierce_budget: int = 0
# Tracks enemies already hit by this cast so a piercing projectile doesn't
# re-damage the same enemy as it overlaps subsequent physics frames.
var _hit_set: Dictionary = {}

var _age: float = 0.0

func configure(skill: Skill) -> void:
	modifier_stack = skill.modifier_stack.duplicate()
	base_color = skill.base_color
	same_color_count = skill.modifier_count_for(skill.base_color)
	base_damage = int(base_damage * (1.0 + 1.5 * (1.0 - pow(0.7, same_color_count))))
	size_multiplier = 1.0 + 0.5 * (1.0 - pow(0.7, same_color_count))
	pierce_budget = skill.elder_modifier_stack_count("marrow_pierce")

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

# Hits a single enemy through the unified damage pipeline.
func _hit_target(target: Node, source_pos: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	# Pierce dedup: don't re-hit the same enemy as a piercing projectile passes
	# through it. Subclasses (e.g. cast_blue_ice_line) may track their own
	# hit set for primary-impact bookkeeping; this is the canonical guard.
	if _hit_set.has(target.get_instance_id()):
		return
	_hit_set[target.get_instance_id()] = true
	DamagePipeline.apply(target, base_damage, modifier_stack, base_color, source_pos, source_tag, null, _player_skill_system(), _player_node())

# Resolve the player's SkillSystem for elder modifier dispatch. Casts don't
# carry a caster reference, so look up the player by group. Returns null if
# unavailable (e.g., test contexts without a player).
func _player_skill_system() -> Node:
	var player: Node = _player_node()
	if player == null:
		return null
	if not player.has_node("SkillSystem"):
		return null
	return player.get_node("SkillSystem")

# Resolve the player node for use as DamagePipeline caster (Overcharge etc.).
func _player_node() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if player == null or not is_instance_valid(player):
		return null
	return player

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
