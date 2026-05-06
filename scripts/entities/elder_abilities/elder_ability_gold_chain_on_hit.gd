extends ElderAbility
class_name ElderAbilityGoldChainOnHit

const CHAIN_RANGE: float = 4.0
const CHAIN_DAMAGE_FRAC: float = 0.5

func _init() -> void:
	super._init("gold")
	on_attack = func(elder: Node, _target: Node) -> void:
		if not is_instance_valid(elder):
			return
		var nearest: Node = null
		var best_dist: float = CHAIN_RANGE
		for e in elder.get_tree().get_nodes_in_group("enemy"):
			if e == elder:
				continue
			if not is_instance_valid(e):
				continue
			if "_is_dead" in e and bool(e.get("_is_dead")):
				continue
			var d: float = e.global_position.distance_to(elder.global_position)
			if d < best_dist:
				nearest = e
				best_dist = d
		if nearest == null or not nearest.has_method("take_damage"):
			return
		var dmg: int = int(float(elder.attack_damage) * CHAIN_DAMAGE_FRAC) if "attack_damage" in elder else 5
		nearest.take_damage(max(1, dmg))
