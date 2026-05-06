extends ElderAbility
class_name ElderAbilityGoldChainOnHit

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const CHAIN_RANGE: float = 4.0
const CHAIN_DAMAGE_FRAC: float = 0.5

func _init() -> void:
	super._init("gold")
	on_attack = func(elder: Node, _target: Node) -> void:
		if not is_instance_valid(elder):
			return
		var nearest: Node = DamagePipeline.find_chain_target(elder, {elder.get_instance_id(): true}, CHAIN_RANGE)
		if nearest == null or not nearest.has_method("take_damage"):
			return
		var dmg: int = int(float(elder.attack_damage) * CHAIN_DAMAGE_FRAC) if "attack_damage" in elder else 5
		nearest.take_damage(max(1, dmg))
