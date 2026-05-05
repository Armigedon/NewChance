extends "res://scripts/entities/boss_mechanic.gd"

const MarkScene: PackedScene = preload("res://scenes/effects/effect_mark_zone.tscn")
const RADIUS: float = 2.0
const DELAY: float = 2.5
const DAMAGE: int = 30

func _init() -> void:
	unlock_phase = 1
	is_big = true
	cooldowns_by_phase = {1: 10.0, 2: 8.0, 3: 6.0}
	windup_duration = 0.05
	execution_duration = 0.0

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	# Prefer the boss's tracked player (_player) so the mechanic targets the
	# same character the boss is chasing. Fall back to group query if unset.
	var p: Node = _boss.get("_player")
	if p == null or not is_instance_valid(p):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		p = players[0]
	if not is_instance_valid(p):
		return
	var mark_zone: Node3D = MarkScene.instantiate()
	_boss.get_parent().add_child(mark_zone)
	mark_zone.global_position = p.global_position
	mark_zone.configure(RADIUS, DELAY, DAMAGE)
