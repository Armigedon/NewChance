extends ElderModifier
class_name ElderModGoldStormCaller

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const BASE_CHANCE: float = 0.25
const CHANCE_PER_STACK: float = 0.10
const CHANCE_CAP: float = 0.65
const STRIKE_RANGE: float = 6.0
const STRIKE_DAMAGE_FRAC: float = 0.6  # of caster attack proxy

func _init() -> void:
	super._init("storm_caller", "gold", "Storm Caller", "25% chance on kill to call lightning on a random nearby enemy. Stack: +10% (cap 65%).")
	on_kill = func(target: Node, source_pos: Vector3, stack_count: int, caster: Node) -> void:
		if not is_instance_valid(target):
			return
		var chance: float = min(CHANCE_CAP, BASE_CHANCE + CHANCE_PER_STACK * float(stack_count - 1))
		if randf() >= chance:
			return
		var tree: SceneTree = target.get_tree()
		if tree == null:
			return
		# Pick a random enemy in range, excluding the dead target.
		var candidates: Array = []
		var range_sq: float = STRIKE_RANGE * STRIKE_RANGE
		for e in tree.get_nodes_in_group("enemy"):
			if e == target or not is_instance_valid(e):
				continue
			if "_is_dead" in e and bool(e.get("_is_dead")):
				continue
			if e.global_position.distance_squared_to(source_pos) <= range_sq:
				candidates.append(e)
		if candidates.is_empty():
			return
		var pick: Node = candidates[randi() % candidates.size()]
		# Damage scales off the dead target's attack_damage as a proxy for cast power.
		var base: int = int(target.get("attack_damage")) if "attack_damage" in target else 10
		var dmg: int = max(1, int(float(base) * STRIKE_DAMAGE_FRAC))
		DamagePipeline.apply(pick, dmg, [], "gold", pick.global_position, "storm", null, null, caster)
