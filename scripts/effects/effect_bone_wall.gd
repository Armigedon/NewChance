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
	# Treat the wall as a thin plane at its position with its X-axis as the
	# length direction and Z-axis as the facing normal. Returns true if the
	# segment from→to crosses the wall plane within the wall's length.
	var wall_pos: Vector3 = global_position
	var wall_axis: Vector3 = global_transform.basis.x.normalized()
	var wall_normal: Vector3 = global_transform.basis.z.normalized()
	var segment_dir: Vector3 = to - from
	var seg_len: float = segment_dir.length()
	if seg_len < 0.001:
		return false
	var d_from: float = (from - wall_pos).dot(wall_normal)
	var d_to: float = (to - wall_pos).dot(wall_normal)
	if (d_from >= 0 and d_to >= 0) or (d_from <= 0 and d_to <= 0):
		return false
	var t: float = d_from / (d_from - d_to)
	var hit: Vector3 = from + segment_dir * t
	var along: float = (hit - wall_pos).dot(wall_axis)
	var half_length: float = length * 0.5
	return absf(along) <= half_length
