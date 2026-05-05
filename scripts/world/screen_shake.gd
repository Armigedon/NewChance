extends Node

var _remaining: float = 0.0
var _intensity: float = 0.0
var _camera: Camera3D = null
var _resting_origin: Vector3 = Vector3.ZERO

func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining -= delta
	# is_instance_valid alone misses the case where the camera was removed from
	# the tree (e.g. scene transition) but not yet freed. Setting global_position
	# on a not-in-tree node errors at get_global_transform.
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		_remaining = 0.0
		_camera = null
		return
	if _remaining <= 0.0:
		_camera.global_position = _resting_origin
		_camera = null
		return
	var off: Vector3 = Vector3(
		randf_range(-_intensity, _intensity),
		randf_range(-_intensity, _intensity),
		0.0
	)
	_camera.global_position = _resting_origin + off

func shake(intensity: float = 0.3, duration: float = 0.15) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	if _camera != cam:
		if _camera != null and is_instance_valid(_camera):
			_camera.global_position = _resting_origin
		_camera = cam
		_resting_origin = cam.global_position
	if duration > _remaining:
		_remaining = duration
	_intensity = max(_intensity, intensity)
