extends Node3D

# Breath cone: damages the player while they're in the cone arc, ticking
# every TICK_INTERVAL seconds for tick_damage. Lifetime expires after the
# configured duration. Used by both static and sweeping breath.

const TICK_INTERVAL: float = 0.2

@export var length: float = 5.0
@export var cone_angle_deg: float = 60.0
@export var lifetime: float = 0.8
@export var tick_damage: int = 10

var direction: Vector3 = Vector3.FORWARD
var blocking_walls_check: Callable = Callable()  # optional: returns true if a wall blocks the segment to a position
var blocking_clouds_check: Callable = Callable()  # optional: returns true if a cloud blocks the segment

var _age: float = 0.0
var _tick_timer: float = 0.0

func configure(origin: Vector3, dir: Vector3, p_length: float, p_angle_deg: float, p_lifetime: float, p_tick_damage: int) -> void:
	global_position = origin
	direction = dir.normalized()
	length = p_length
	cone_angle_deg = p_angle_deg
	lifetime = p_lifetime
	tick_damage = p_tick_damage

func _process(delta: float) -> void:
	_age += delta
	_tick_timer += delta
	if _tick_timer >= TICK_INTERVAL:
		_tick_timer = 0.0
		_tick_targets()
	if _age >= lifetime:
		queue_free()

func _tick_targets() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p):
			continue
		if not _in_cone(p.global_position):
			continue
		# Color interaction hooks (optional callables wired by mechanic)
		if blocking_walls_check.is_valid() and blocking_walls_check.call(p.global_position):
			continue
		if blocking_clouds_check.is_valid() and blocking_clouds_check.call(p.global_position):
			continue
		if p.has_method("take_damage"):
			p.take_damage(tick_damage)

func _in_cone(target_pos: Vector3) -> bool:
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist > length or dist < 0.01:
		return false
	# Negate: direction stores a Godot 4 bearing (e.g. FORWARD = (0,0,-1)); the
	# actual arena-facing vector is the opposite sign (dragon at origin facing +Z
	# when dir=FORWARD). Callers pass the node's -basis.z facing convention.
	var dir_flat: Vector3 = -direction
	dir_flat.y = 0.0
	dir_flat = dir_flat.normalized()
	var to_target_norm: Vector3 = to_target.normalized()
	var angle: float = rad_to_deg(acos(clampf(dir_flat.dot(to_target_norm), -1.0, 1.0)))
	return angle <= cone_angle_deg / 2.0

func set_direction(dir: Vector3) -> void:
	direction = dir.normalized()
