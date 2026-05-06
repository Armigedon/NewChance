extends ElderAbility
class_name ElderAbilityGreenPoisonTrail

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const TRAIL_DROP_DISTANCE: float = 1.5
const TRAIL_LIFETIME: float = 2.0
const TRAIL_RADIUS: float = 1.5
const TRAIL_TICK_DAMAGE: int = 3

func _init() -> void:
	super._init("green")
	on_alive_tick = func(elder: Node, _delta: float) -> void:
		if not is_instance_valid(elder):
			return
		# Anchor the first tick's position; subsequent ticks measure from it.
		# Without the explicit has_meta check the default would always be the
		# current position, so dist is always 0 and no cloud ever drops.
		if not elder.has_meta("green_trail_last_pos"):
			elder.set_meta("green_trail_last_pos", elder.global_position)
			return
		var last_pos: Vector3 = elder.get_meta("green_trail_last_pos")
		var dist: float = elder.global_position.distance_to(last_pos)
		if dist < TRAIL_DROP_DISTANCE:
			return
		elder.set_meta("green_trail_last_pos", elder.global_position)
		var cloud: Node3D = CloudScene.instantiate()
		var parent: Node = elder.get_parent()
		if parent == null:
			return
		parent.add_child(cloud)
		cloud.global_position = elder.global_position
		cloud.configure(TRAIL_LIFETIME, TRAIL_RADIUS, TRAIL_TICK_DAMAGE, [], "green")
