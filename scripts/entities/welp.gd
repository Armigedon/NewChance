extends CharacterBody3D

const Vfx = preload("res://scripts/effects/vfx.gd")

@export var max_hp: int = 50

@export var move_speed: float = 3.6
@export var attack_damage: int = 10
@export var attack_interval: float = 2.0
@export var attack_range: float = 1.0

const SOUL_PICKUP_SCENE: PackedScene = preload("res://scenes/interactables/soul_pickup.tscn")

@export var color: String = "red"
@export var tier: String = "welp"

const KNOCKBACK_DECAY: float = 12.0  # m/s² — knockback impulse decay rate
const KNOCKBACK_VELOCITY_MAX: float = 6.0  # m/s — prevents off-screen yeets

# --- Status effect state (Phase 9) ---
const FREEZE_THRESHOLD: int = 5
const FREEZE_DURATION: float = 1.5
const SLOW_PER_CHILL_STACK: float = 0.15  # 15% slow per stack below freeze threshold

var _burn_dps: float = 0.0
var _burn_remaining: float = 0.0
var _burn_residual: float = 0.0  # accumulates fractional burn damage between integer applies
var _chill_stacks: int = 0
var _frozen_remaining: float = 0.0
var _slow_pct: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0

signal died(welp: Node, color: String)

var hp: int = max_hp
var _attack_cooldown: float = 0.0
var _player: Node = null
var _is_dead: bool = false
var _knockback_velocity: Vector3 = Vector3.ZERO
var _flash_resting_albedo: Color = Color(0, 0, 0, 0)  # sentinel: alpha 0 = "not yet captured"
var _flash_tween: Tween = null

func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	collision_layer = 2  # match Sword mask
	collision_mask = collision_mask | 8  # also block on bone walls (layer 4)
	_find_player()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_tick_status_effects(delta)
	if _is_dead:
		return  # burn DoT may have killed us mid-tick; skip the rest of this frame
	# Frozen or stunned enemies skip movement and attacks
	if is_frozen() or is_stunned():
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
		move_and_slide()
		return
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	var effective_speed: float = move_speed * (1.0 - _slow_pct)
	if distance > attack_range:
		velocity.x = to_player.normalized().x * effective_speed
		velocity.z = to_player.normalized().z * effective_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attack_cooldown <= 0.0:
			_attack_player()
			_attack_cooldown = attack_interval
	if _attack_cooldown > 0.0:
		_attack_cooldown = max(0.0, _attack_cooldown - delta)
	# Apply knockback impulse on top of tracking velocity, then decay it.
	if _knockback_velocity.length() > 0.01:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
	move_and_slide()

func _find_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]

func _attack_player() -> void:
	if _player == null or not _player.has_method("take_damage"):
		return
	# Skip recording if the player is i-framed — the hit won't actually land,
	# and we don't want a near-miss attacker to become the "killed by" name.
	if _player.has_method("is_invincible") and _player.is_invincible():
		return
	RunStats.record_damage_from(display_name())
	_player.take_damage(attack_damage)

func flash_hit(duration: float = 0.12) -> void:
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mat.resource_local_to_scene = true
		mesh.material_override = mat
	# Capture resting albedo on first flash so concurrent flashes always
	# return to the TRUE color (not a mid-flash white).
	if _flash_resting_albedo.a == 0.0:
		_flash_resting_albedo = mat.albedo_color
	# Kill any active tween so two near-simultaneous flashes don't fight.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	mat.albedo_color = Color(1, 1, 1, 1)
	_flash_tween = create_tween()
	_flash_tween.tween_property(mat, "albedo_color", _flash_resting_albedo, duration)

func apply_knockback(direction: Vector3, force: float) -> void:
	direction.y = 0.0
	if direction.length() < 0.001:
		return
	var effective_force: float = force / _mass()
	_knockback_velocity += direction.normalized() * effective_force
	_clamp_knockback_velocity()

# --- Status effect API (Phase 9) ---

func apply_burn(dps: float, duration: float) -> void:
	_burn_dps = max(_burn_dps, dps)
	_burn_remaining = max(_burn_remaining, duration)

func apply_chill(stacks: int) -> void:
	_chill_stacks += stacks
	if _chill_stacks >= FREEZE_THRESHOLD:
		_frozen_remaining = FREEZE_DURATION
		_chill_stacks = 0
	else:
		apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)

func apply_stun(duration: float) -> void:
	_stun_remaining = max(_stun_remaining, duration)

func apply_slow(pct: float, duration: float) -> void:
	_slow_pct = max(_slow_pct, pct)
	_slow_remaining = max(_slow_remaining, duration)

func apply_pull_toward(target_pos: Vector3, impulse: float, _source: Node = null) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var effective_impulse: float = impulse / _mass()
	_knockback_velocity += dir.normalized() * effective_impulse
	_clamp_knockback_velocity()

func is_frozen() -> bool:
	return _frozen_remaining > 0.0

func is_stunned() -> bool:
	return _stun_remaining > 0.0

func _tick_status_effects(delta: float) -> void:
	# Burn DoT — residual accumulator pattern (mirrors boss_dragon.gd Task 3 fix).
	# Floors per-frame would over-deal at high framerate; accumulate fractional
	# damage and apply integer chunks instead.
	if _burn_remaining > 0.0:
		_burn_residual += _burn_dps * delta
		var burn_dmg: int = int(_burn_residual)
		if burn_dmg > 0:
			_burn_residual -= float(burn_dmg)
			if not _is_dead:
				take_damage(burn_dmg)  # routes through normal damage path
		_burn_remaining = max(0.0, _burn_remaining - delta)
		if _burn_remaining == 0.0:
			_burn_residual = 0.0
	if _frozen_remaining > 0.0:
		_frozen_remaining = max(0.0, _frozen_remaining - delta)
	if _stun_remaining > 0.0:
		_stun_remaining = max(0.0, _stun_remaining - delta)
	if _slow_remaining > 0.0:
		_slow_remaining = max(0.0, _slow_remaining - delta)
		if _slow_remaining == 0.0:
			_slow_pct = 0.0

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	if hp == 0:
		_is_dead = true
		_drop_souls()
		RunStats.record_kill()
		HitStop.freeze(_hit_stop_duration())
		var burst_color: Color = Vfx.COLOR_ALBEDO.get(color, Color(0.5, 0.5, 0.5, 1))
		Vfx.spawn_death_burst(global_position + Vector3(0, 0.5, 0), burst_color, get_parent())
		died.emit(self, color)
		queue_free()

func display_name() -> String:
	# Used by run-end summary's "Killed by" line.
	if color == "alarm":
		return "an alarm welp"
	if color == "boss":
		return "a boss whelp"
	return "%s %s" % [color, tier]

func _hit_stop_duration() -> float:
	# Tier-tuned freeze duration for kill weight.
	match tier:
		"welp": return 0.05
		"dragon": return 0.08
		"elder": return 0.12
		_: return 0.05

func _mass() -> float:
	# Tier-aware mass for pull/knockback resistance.
	match tier:
		"welp": return 1.0
		"dragon": return 2.0
		"elder": return 3.0
		_: return 1.0  # alarm, boss-summoned, etc.

func _clamp_knockback_velocity() -> void:
	if _knockback_velocity.length() > KNOCKBACK_VELOCITY_MAX:
		_knockback_velocity = _knockback_velocity.normalized() * KNOCKBACK_VELOCITY_MAX

func _drop_souls() -> void:
	# Special "alarm" welps drop nothing (used by time-alarm spawner in T8)
	# Boss-summoned whelps also drop nothing
	if color == "alarm" or color == "boss":
		return
	# Phase 9 redesign (May 2026): tier-aware drop policy.
	# - welp: nothing (was 1 minor)
	# - dragon: 1-2 minor (was 2-3)
	# - elder: 1 elder, no minors (was 1 elder + 2-3 minor)
	# Phase 10 tuning (May 2026): first whelp kill of the run drops 1 minor
	# so the player can unlock their starting wand from sword-only. Subsequent
	# whelps drop nothing.
	if tier == "welp":
		if not RunStats.first_whelp_kill_completed:
			RunStats.mark_first_whelp_kill()
			_spawn_pickup("minor", _random_offset())
		return
	if tier == "dragon":
		var minor_count: int = 1 + (1 if randf() < 0.5 else 0)
		for i in range(minor_count):
			_spawn_pickup("minor", _random_offset())
		return
	if tier == "elder":
		_spawn_pickup("elder", _random_offset())
		return
	push_warning("welp._drop_souls: unhandled tier '%s' — dropping nothing" % tier)

func _spawn_pickup(pickup_tier: String, offset: Vector3) -> void:
	var pickup: Area3D = SOUL_PICKUP_SCENE.instantiate()
	pickup.color = color
	pickup.tier = pickup_tier
	var pickup_pos: Vector3 = global_position + offset
	get_parent().add_child(pickup)
	pickup.global_position = pickup_pos

func _random_offset() -> Vector3:
	return Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
