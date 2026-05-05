extends "res://scripts/entities/boss_mechanic.gd"

const MarkScene: PackedScene = preload("res://scenes/effects/effect_mark_zone.tscn")
const RADIUS: float = 2.0
const DELAY: float = 2.5
const DAMAGE: int = 30

# Tracked so cleanup() can free a still-pending mark when the boss dies before
# the delayed strike would land.
var _pending_mark: Node3D = null

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
	mark_zone.wall_absorb_check = func(pos: Vector3, r: float, dmg: int) -> bool:
		return _wall_absorbs_at(pos, r, dmg)
	_pending_mark = mark_zone
	mark_zone.tree_exited.connect(func(): _pending_mark = null)

func cleanup() -> void:
	# Boss died — cancel any pending mark so it doesn't strike from the grave.
	if _pending_mark != null and is_instance_valid(_pending_mark):
		_pending_mark.queue_free()
	_pending_mark = null

func _wall_absorbs_at(pos: Vector3, radius: float, dmg: int) -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.global_position.distance_to(pos) <= radius:
			if w.has_method("take_damage"):
				w.take_damage(dmg)
			return true
	return false
