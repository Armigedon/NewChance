extends Area3D

@export var swing_interval: float = 0.4  # seconds per swing
@export var base_damage: int = 15

signal hit_enemy(enemy: Node, damage: int)

var _swing_cooldown: float = 0.0

func _ready() -> void:
	base_damage += MetaProgress.cantrip_bonus("sword_damage")

func _process(delta: float) -> void:
	if _swing_cooldown > 0.0:
		_swing_cooldown = max(0.0, _swing_cooldown - delta)
		return
	var enemies: Array = get_overlapping_bodies().filter(_is_enemy)
	if enemies.size() == 0:
		return
	# Cleave: swing damages every enemy in range, not just the first.
	for enemy in enemies:
		if not enemy.has_method("take_damage"):
			continue
		enemy.take_damage(base_damage)
		hit_enemy.emit(enemy, base_damage)
		# Visual feedback per hit.
		if enemy.has_method("flash_hit"):
			enemy.flash_hit()
		if enemy.has_method("apply_knockback"):
			var dir: Vector3 = enemy.global_position - global_position
			var force: float = _knockback_force_for(enemy)
			enemy.apply_knockback(dir, force)
		ScreenShake.shake(0.10, 0.06)
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

func set_active_element(color: String) -> void:
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
