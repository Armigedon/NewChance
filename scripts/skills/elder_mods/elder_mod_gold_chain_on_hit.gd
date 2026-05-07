extends ElderModifier
class_name ElderModGoldChainOnHit

# Behavior lives in damage_pipeline: it reads
# active_skill.elder_modifier_stack_count("chain_on_hit") to grow the chain
# budget. This class only registers the modifier id/metadata.
func _init() -> void:
	super._init("chain_on_hit", "gold", "Chain on Hit", "Casts chain to 1 nearby enemy. Stack: +1 chain target.")
