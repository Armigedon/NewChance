extends Area3D

@export var swing_interval: float = 0.4  # seconds per swing
@export var base_damage: int = 15

var _swing_cooldown: float = 0.0

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const PASSIVE_ARMOR_INTERVAL: float = 5.0

var _active_color: String = ""
var _white_count: int = 0  # white modifiers on the active skill (excludes implicit base-color +1)
var _passive_armor_timer: float = 0.0

func _ready() -> void:
	# Phase 10: route sword damage through MetaShop's Power stat (multiplicative),
	# consistent with how player HP, dash, and pyre cap are routed through MetaShop.
	base_damage = int(float(base_damage) * (1.0 + MetaShop.stat_value("power")))

func _process(delta: float) -> void:
	# Passive white WARD: armor stack every 5s while equipped to a white-base skill
	_passive_armor_timer += delta
	if _active_color == "white" and _passive_armor_timer >= PASSIVE_ARMOR_INTERVAL:
		_passive_armor_timer = 0.0
		var player: Node = get_tree().get_first_node_in_group("player")
		if player != null and player.has_method("apply_armor"):
			player.apply_armor(1, 5.0)
	if _swing_cooldown > 0.0:
		_swing_cooldown = max(0.0, _swing_cooldown - delta)
		return
	var enemies: Array = get_overlapping_bodies().filter(_is_enemy)
	if enemies.size() == 0:
		return
	for enemy in enemies:
		if not enemy.has_method("take_damage"):
			continue
		# Sword applies base damage AND the active skill's base color's native
		# layer (no modifier stack). DamagePipeline with empty stack handles this.
		DamagePipeline.apply(enemy, scaled_damage(), [], _active_color, global_position, "sword", null, _player_skill_system(), _player_node())
		if enemy.has_method("apply_knockback"):
			var dir: Vector3 = enemy.global_position - global_position
			var force: float = _knockback_force_for(enemy)
			enemy.apply_knockback(dir, force)
	_swing_cooldown = swing_interval

func _is_enemy(body: Node) -> bool:
	return body.is_in_group("enemy")

func _knockback_force_for(enemy: Node) -> float:
	# Boss has no "tier" property; treat as boss → 1.5
	if not "tier" in enemy:
		return 1.5
	match enemy.tier:
		"welp": return 4.0
		"dragon": return 3.0
		"elder": return 3.0
		_: return 4.0

@onready var _blade_mesh: MeshInstance3D = $Blade if has_node("Blade") else null

const COLOR_TINTS: Dictionary = {
	"": Color(0.55, 0.5, 0.42, 1),
	"red": Color(1, 0.3, 0.1, 1),
	"blue": Color(0.4, 0.7, 1, 1),
	"green": Color(0.3, 0.85, 0.3, 1),
	"purple": Color(0.6, 0.3, 0.8, 1),
	"gold": Color(1, 0.9, 0.3, 1),
	"white": Color(0.95, 0.95, 0.9, 1),
}

func set_active_element(color: String, white_modifier_count: int = 0) -> void:
	# Reset passive armor timer only when color actually changes. Modifier
	# pickups on the active skill also call this (via active_skill_changed),
	# and we don't want to delay the next passive armor stack on every pickup.
	var color_changed: bool = (color != _active_color)
	_active_color = color
	_white_count = white_modifier_count
	if color_changed:
		_passive_armor_timer = 0.0
	if _blade_mesh == null:
		return
	var mat: StandardMaterial3D = _blade_mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	var tint: Color = COLOR_TINTS.get(color, COLOR_TINTS[""])
	mat.albedo_color = tint
	mat.emission_enabled = (color != "")
	mat.emission = tint
	mat.emission_energy_multiplier = 2.0 if color != "" else 0.0

const WHITE_DECAY: float = 0.7
const WHITE_ASYMPTOTE_MULT: float = 2.0  # asymptote of 2.0× base damage

func scaled_damage() -> int:
	var n: int = _white_count + (1 if _active_color == "white" else 0)
	# 2.0 - 0.7^n is mathematically equivalent to 1.0 + 1.0*(1.0 - 0.7^n).
	# See spec §5 — diminishing-returns curve, asymptote 2× base.
	return int(base_damage * (WHITE_ASYMPTOTE_MULT - pow(WHITE_DECAY, n)))

# Resolve the player's SkillSystem so elder modifier hooks fire on sword hits.
# Sword is parented to the player but we look up via group for resilience to
# scene-graph changes.
func _player_skill_system() -> Node:
	var player: Node = _player_node()
	if player == null:
		return null
	if not player.has_node("SkillSystem"):
		return null
	return player.get_node("SkillSystem")

# Resolve the player node for DamagePipeline caster (Overcharge etc.).
func _player_node() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if player == null or not is_instance_valid(player):
		return null
	return player
