extends ElderAbility
class_name ElderAbilityBlueChillAura

const AURA_RADIUS: float = 3.0
const AURA_TICK_INTERVAL: float = 1.0

func _init() -> void:
	super._init("blue")
	# State per elder is held in node meta — multiple blue elders can each track
	# their own aura tick independently.
	on_alive_tick = func(elder: Node, delta: float) -> void:
		if not is_instance_valid(elder):
			return
		var timer: float = float(elder.get_meta("blue_aura_timer", 0.0))
		timer += delta
		if timer < AURA_TICK_INTERVAL:
			elder.set_meta("blue_aura_timer", timer)
			return
		elder.set_meta("blue_aura_timer", 0.0)
		var players: Array = elder.get_tree().get_nodes_in_group("player")
		for p in players:
			if not is_instance_valid(p):
				continue
			var d: float = p.global_position.distance_to(elder.global_position)
			if d <= AURA_RADIUS and p.has_method("apply_chill"):
				p.apply_chill(1)
