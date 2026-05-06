extends ElderAbility
class_name ElderAbilityRedFirePool

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const POOL_RADIUS: float = 2.5
const POOL_LIFETIME: float = 3.0
const POOL_TICK_DAMAGE: int = 5

func _init() -> void:
	super._init("red")
	on_death = func(elder: Node) -> void:
		if not is_instance_valid(elder):
			return
		var pool: Node3D = CloudScene.instantiate()
		var parent: Node = elder.get_parent()
		if parent == null:
			return
		parent.add_child(pool)
		pool.global_position = elder.global_position
		pool.configure(POOL_LIFETIME, POOL_RADIUS, POOL_TICK_DAMAGE, [], "red")
