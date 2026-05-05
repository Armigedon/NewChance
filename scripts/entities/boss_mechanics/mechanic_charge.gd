extends "res://scripts/entities/boss_mechanic.gd"

const CHARGE_DAMAGE: int = 60
const CHARGE_HIT_RADIUS: float = 1.5
const CHARGE_BASE_VELOCITY: float = 12.0
const CHARGE_DISTANCE: float = 12.0

var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_origin: Vector3 = Vector3.ZERO
var _executed_distance: float = 0.0
var _hit_player_this_charge: bool = false
var _velocity_modifier: float = 1.0
var _walls_in_path: Array = []
var _stunned_remaining: float = 0.0

func _init() -> void:
	unlock_phase = 3
	is_big = true
	cooldowns_by_phase = {1: 999.0, 2: 999.0, 3: 12.0}
	windup_duration = 1.4
	execution_duration = 1.5

func _on_windup_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var p: Node = _boss.get("_player")
	if p == null or not is_instance_valid(p):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.is_empty():
			_charge_dir = Vector3.FORWARD
			return
		p = players[0]
	var to_p: Vector3 = p.global_position - _boss.global_position
	to_p.y = 0.0
	if to_p.length() > 0.01:
		_charge_dir = to_p.normalized()
	_velocity_modifier = 1.0
	_hit_player_this_charge = false

func _on_execution_start() -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	_charge_origin = _boss.global_position
	_executed_distance = 0.0
	_walls_in_path = []
	_stunned_remaining = 0.0

func tick(delta: float, current_phase: int) -> void:
	super.tick(delta, current_phase)
	if not is_in_execution():
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	if _stunned_remaining > 0.0:
		_stunned_remaining = max(0.0, _stunned_remaining - delta)
		return
	if _executed_distance >= CHARGE_DISTANCE:
		return
	var step: float = CHARGE_BASE_VELOCITY * _velocity_modifier * delta
	if _executed_distance + step > CHARGE_DISTANCE:
		step = CHARGE_DISTANCE - _executed_distance
	_executed_distance += step
	_boss.global_position += _charge_dir * step
	_check_wall_collisions()
	_check_player_hit()

func _check_wall_collisions() -> void:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	var boss_flat: Vector2 = Vector2(_boss.global_position.x, _boss.global_position.z)
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w in _walls_in_path:
			continue
		var wf: Vector2 = Vector2(w.global_position.x, w.global_position.z)
		if boss_flat.distance_to(wf) <= 1.0:
			_walls_in_path.append(w)
			if _walls_in_path.size() >= 2:
				_velocity_modifier = 0.0
				_stunned_remaining = 1.0
				for ww in _walls_in_path:
					if is_instance_valid(ww) and ww.has_method("take_damage"):
						ww.take_damage(100)
				_walls_in_path = []
			else:
				_velocity_modifier *= 0.5
				if w.has_method("take_damage"):
					w.take_damage(100)

func _check_player_hit() -> void:
	if _hit_player_this_charge:
		return
	# Prefer the boss's tracked _player to avoid stale group members in tests.
	var tracked: Node = _boss.get("_player") if _boss != null else null
	var candidates: Array = []
	if tracked != null and is_instance_valid(tracked):
		candidates = [tracked]
	else:
		candidates = get_tree().get_nodes_in_group("player")
	var boss_flat: Vector2 = Vector2(_boss.global_position.x, _boss.global_position.z)
	for p in candidates:
		if not is_instance_valid(p):
			continue
		var pf: Vector2 = Vector2(p.global_position.x, p.global_position.z)
		if boss_flat.distance_to(pf) <= CHARGE_HIT_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage(CHARGE_DAMAGE)
			_hit_player_this_charge = true
			ScreenShake.shake(0.1, 0.2)
			break

func on_chill_during_charge(stacks_added: int) -> void:
	if not is_in_execution():
		return
	_velocity_modifier *= max(0.0, 1.0 - 0.08 * float(stacks_added))

func on_pull_during_charge(pull_origin: Vector3, _magnitude: float) -> void:
	if not is_in_execution():
		return
	if _boss == null or not is_instance_valid(_boss):
		return
	var to_pull: Vector3 = pull_origin - _boss.global_position
	to_pull.y = 0.0
	if to_pull.length() < 0.01:
		return
	to_pull = to_pull.normalized()
	var perp: Vector3 = to_pull - to_pull.project(_charge_dir)
	if perp.length() > 0.01:
		_charge_dir = (_charge_dir + perp.normalized() * 0.3).normalized()
