extends StaticBody3D

const NATIVE_HP: int = 100
const NATIVE_LIFETIME: float = 4.0
const NATIVE_LENGTH: float = 4.0

var hp: int = NATIVE_HP
var lifetime: float = NATIVE_LIFETIME
var length: float = NATIVE_LENGTH
var _age: float = 0.0

signal wall_broken

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
