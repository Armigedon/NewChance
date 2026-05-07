extends ElderModifier
class_name ElderModGoldResonance

# Resonance is a passive multiplier read in damage_pipeline's chain recursion:
# each successive jump gets +25% damage per stack. The pipeline computes
#   chain_damage = effective_damage * (1.0 + 0.25 * stack * jump_count)
# directly. This class exists to register the modifier id and metadata.
func _init() -> void:
	super._init("resonance", "gold", "Resonance", "Chains amplify per jump (+25% per jump). Stack: +25% per copy.")
