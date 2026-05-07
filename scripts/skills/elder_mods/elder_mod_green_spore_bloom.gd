extends ElderModifier
class_name ElderModGreenSporeBloom

const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")

func _init() -> void:
	super._init("spore_bloom", "green", "Spore Bloom", "Kills release a 2m poison cloud. Stack: +1m radius.")
	on_kill = func(target: Node, source_pos: Vector3, stack_count: int, _caster: Node) -> void:
		if not is_instance_valid(target):
			return
		var radius: float = 2.0 + 1.0 * float(stack_count - 1)
		var cloud: Node3D = CloudScene.instantiate()
		var parent: Node = target.get_parent()
		if parent == null:
			return
		parent.add_child(cloud)
		cloud.global_position = source_pos
		cloud.configure(2.0, radius, 5, [], "green")
