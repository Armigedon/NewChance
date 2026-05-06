extends ElderAbility
class_name ElderAbilityWhiteBoneWall

const BoneWallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")
const WALL_OFFSET_M: float = 2.5
const WALL_LIFETIME: float = 3.0
const WALL_LENGTH: float = 4.0
const WALL_HP: int = 30

func _init() -> void:
	super._init("white")
	on_death = func(elder: Node) -> void:
		if not is_instance_valid(elder):
			return
		var players: Array = elder.get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		var player: Node = players[0]
		if not is_instance_valid(player):
			return
		# Offset 2.5m from the player along a random angle within ±45° of the
		# player→elder vector, so the wall blocks an evasive line near the player.
		var to_elder: Vector3 = elder.global_position - player.global_position
		to_elder.y = 0.0
		if to_elder.length() < 0.01:
			to_elder = Vector3.FORWARD
		to_elder = to_elder.normalized()
		var jitter: float = randf_range(-PI / 4.0, PI / 4.0)
		var dir: Vector3 = to_elder.rotated(Vector3.UP, jitter)
		var wall_pos: Vector3 = player.global_position + dir * WALL_OFFSET_M
		var wall: StaticBody3D = BoneWallScene.instantiate()
		var parent: Node = elder.get_parent()
		if parent == null:
			return
		parent.add_child(wall)
		wall.global_position = Vector3(wall_pos.x, 0.5, wall_pos.z)
		# Orient wall perpendicular to the dir vector so it blocks the line.
		wall.look_at(wall.global_position + Vector3(dir.z, 0, -dir.x), Vector3.UP)
		if wall.has_method("configure"):
			wall.configure(WALL_HP, WALL_LIFETIME, WALL_LENGTH)
