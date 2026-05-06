extends ElderModifier
class_name ElderModWhiteBoneShield

# Bone Shield: charges absorb the next N hits. Charges set on encounter start
# (per spec). For Phase 1 of plan, "encounter" = current run; reset on
# run_ended. Stack: +1 charge per copy.
func _init() -> void:
	super._init("bone_shield", "white", "Bone Shield", "First N hits per encounter are absorbed. Stack: +1 absorb.")
	on_player_damaged = func(player: Node, _amount: int, _stack_count: int) -> void:
		if not is_instance_valid(player):
			return
		var charges: int = int(player.get_meta("bone_shield_charges", 0))
		if charges <= 0:
			return
		player.set_meta("bone_shield_charges", charges - 1)
