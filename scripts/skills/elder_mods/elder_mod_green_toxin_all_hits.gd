extends ElderModifier
class_name ElderModGreenToxinAllHits

# Toxin uses the existing burn DoT plumbing tagged with a different source.
# Future: separate poison state if/when it diverges from burn semantics.
func _init() -> void:
	super._init("toxin_all_hits", "green", "Toxin All Hits", "Every cast applies a 2s poison DoT. Repeats extend duration.")
	on_hit = func(target: Node, damage: int, _source_pos: Vector3, stack_count: int) -> void:
		if not is_instance_valid(target):
			return
		if target.has_method("apply_burn"):
			var duration: float = 2.0 + 1.0 * float(stack_count - 1)
			target.apply_burn(float(damage) * 0.10, duration)
