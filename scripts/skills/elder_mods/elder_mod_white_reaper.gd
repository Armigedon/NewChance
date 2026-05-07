extends ElderModifier
class_name ElderModWhiteReaper

const HEAL_PCT_PER_STACK: float = 0.02

# Reaper heals the player on kill. Spec narrows this to sword kills, but the
# on_kill hook doesn't currently receive source_tag, so v1 fires on any kill
# whose pipeline call passed `caster` (cast paths and sword paths both do).
func _init() -> void:
	super._init("reaper", "white", "Reaper", "Kills restore 2% HP. Stack: +2% per copy.")
	on_kill = func(_target: Node, _source_pos: Vector3, stack_count: int, caster: Node) -> void:
		if caster == null or not is_instance_valid(caster):
			return
		# Caster here is the sword's player_node() which forwards to the player.
		# The Player node has hp / max_hp; restore HEAL_PCT_PER_STACK * stack of max_hp.
		if not ("hp" in caster and "max_hp" in caster):
			return
		var heal_frac: float = HEAL_PCT_PER_STACK * float(stack_count)
		var heal_amount: int = max(1, int(float(caster.get("max_hp")) * heal_frac))
		var new_hp: int = min(int(caster.get("max_hp")), int(caster.get("hp")) + heal_amount)
		caster.set("hp", new_hp)
		if caster.has_signal("hp_changed"):
			caster.emit_signal("hp_changed", new_hp)
