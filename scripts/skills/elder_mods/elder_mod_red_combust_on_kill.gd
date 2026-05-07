extends ElderModifier
class_name ElderModRedCombustOnKill

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const BASE_RADIUS: float = 2.0
const RADIUS_PER_STACK: float = 0.5  # +25% per stack on a 2m base
const DAMAGE_FRAC: float = 0.5

func _init() -> void:
	super._init("combust_on_kill", "red", "Combust on Kill", "Kills explode for 50% weapon damage in 2m. Stack: +25% radius.")
	on_kill = func(target: Node, source_pos: Vector3, stack_count: int, caster: Node) -> void:
		if not is_instance_valid(target):
			return
		var tree: SceneTree = target.get_tree()
		if tree == null:
			return
		var radius: float = BASE_RADIUS + RADIUS_PER_STACK * float(stack_count - 1)
		var radius_sq: float = radius * radius
		var explosion_damage: int = max(1, int(float(target.get("attack_damage") if "attack_damage" in target else 10) * DAMAGE_FRAC))
		# AOE around the corpse — skip the killed target itself.
		for e in tree.get_nodes_in_group("enemy"):
			if e == target or not is_instance_valid(e):
				continue
			if e.global_position.distance_squared_to(source_pos) > radius_sq:
				continue
			DamagePipeline.apply(e, explosion_damage, [], "red", source_pos, "combust", null, null, caster)
