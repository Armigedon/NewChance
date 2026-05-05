extends Node3D

# Mark + delayed strike floor zone. Configures with radius, delay, damage.
# Strike lands at the position the mark was placed. Visual ring fills/grows
# during the delay; at delay end, damages players in radius and frees.

@export var radius: float = 2.0
@export var delay: float = 2.5
@export var damage: int = 30

var _age: float = 0.0
var _struck: bool = false

# Optional callable for wall-absorb interaction (Task 15). Returns true if a
# wall absorbed the strike (no player damage applied).
var wall_absorb_check: Callable = Callable()

func configure(p_radius: float, p_delay: float, p_damage: int) -> void:
	radius = p_radius
	delay = p_delay
	damage = p_damage
	add_to_group("mark_zone")
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE * (radius / 2.0)

func _process(delta: float) -> void:
	_age += delta
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null and mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = mesh.material_override
		mat.albedo_color.a = clampf(_age / delay, 0.2, 0.9)
	if _age >= delay and not _struck:
		_struck = true
		_strike()
		queue_free()

func _strike() -> void:
	if wall_absorb_check.is_valid() and wall_absorb_check.call(global_position, radius, damage):
		return
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(global_position) <= radius:
			if p.has_method("take_damage"):
				p.take_damage(damage)
	ScreenShake.shake(0.06, 0.12)
