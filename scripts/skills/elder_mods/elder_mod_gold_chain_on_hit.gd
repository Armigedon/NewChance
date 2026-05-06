extends ElderModifier
class_name ElderModGoldChainOnHit

# The chain itself runs in damage_pipeline.gd; this modifier just tags a
# bonus chain budget. Pipeline integration in Task 9 reads
# active_skill.elder_modifier_stack_count("chain_on_hit") and adds to
# ChainState.budget.
func _init() -> void:
	super._init("chain_on_hit", "gold", "Chain on Hit", "Casts chain to 1 nearby enemy. Stack: +1 chain target.")
	on_hit = func(_target: Node, _damage: int, _source_pos: Vector3, _stack_count: int) -> void:
		# No-op here — pipeline reads stack count for budget directly.
		pass
