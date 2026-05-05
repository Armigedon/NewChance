extends StaticBody3D

const NATIVE_HP: int = 30
const NATIVE_LIFETIME: float = 1.5
const NATIVE_LENGTH: float = 4.0

var hp: int = NATIVE_HP
var lifetime: float = NATIVE_LIFETIME
var length: float = NATIVE_LENGTH
var _age: float = 0.0
var spawn_time_msec: int = 0

signal wall_broken

func _ready() -> void:
	spawn_time_msec = Time.get_ticks_msec()
	add_to_group("bone_wall")

func configure(p_hp: int, p_lifetime: float, p_length: float) -> void:
	hp = p_hp
	lifetime = p_lifetime
	length = p_length
	var mesh: MeshInstance3D = $Mesh as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3(length / NATIVE_LENGTH, 1.0, 1.0)
	var shape: CollisionShape3D = $CollisionShape3D
	if shape != null and shape.shape is BoxShape3D:
		var s: BoxShape3D = shape.shape.duplicate() as BoxShape3D
		s.size = Vector3(length, 1.5, 0.4)
		shape.shape = s

func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	if hp == 0:
		wall_broken.emit()
		queue_free()

func blocks_segment(from: Vector3, to: Vector3) -> bool:
	# Project everything onto the XZ plane to match the breath cone's flat
	# top-down treatment. The cone's `_in_cone` ignores Y; the wall block check
	# does the same so that gravity-induced Y drift on the player or boss does
	# not let breath sneak past a wall that visually obstructs the line.
	var flat_from: Vector3 = Vector3(from.x, 0.0, from.z)
	var flat_to: Vector3 = Vector3(to.x, 0.0, to.z)
	var wall_pos: Vector3 = global_position
	wall_pos.y = 0.0
	var wall_axis: Vector3 = global_transform.basis.x
	wall_axis.y = 0.0
	wall_axis = wall_axis.normalized()
	var wall_normal: Vector3 = global_transform.basis.z
	wall_normal.y = 0.0
	var nlen: float = wall_normal.length()
	if nlen < 0.0001:
		return false  # wall is edge-on; cannot determine sides
	wall_normal /= nlen
	var segment_dir: Vector3 = flat_to - flat_from
	if segment_dir.length() < 0.001:
		return false
	var d_from: float = (flat_from - wall_pos).dot(wall_normal)
	var d_to: float = (flat_to - wall_pos).dot(wall_normal)
	if (d_from >= 0 and d_to >= 0) or (d_from <= 0 and d_to <= 0):
		return false
	var denom: float = d_from - d_to
	if absf(denom) < 0.0001:
		return false
	var t: float = d_from / denom
	var hit: Vector3 = flat_from + segment_dir * t
	var along: float = (hit - wall_pos).dot(wall_axis)
	return absf(along) <= length * 0.5
