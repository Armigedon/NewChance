extends CharacterBody3D

const Vfx = preload("res://scripts/effects/vfx.gd")

const MAX_HP_TEST: int = 150
const MAX_HP_SHIP: int = 500
static var MAX_HP: int = MAX_HP_TEST if Debug.FAST_TEST else MAX_HP_SHIP
const MOVE_SPEED: float = 2.0
const PHASE_2_HP_PCT: float = 0.66
const PHASE_3_HP_PCT: float = 0.33
const IDLE_TAUNT_INTERVAL: float = 18.0
const TAUNT_COOLDOWN_SECONDS: float = 5.0
const KNOCKBACK_DECAY: float = 12.0
const KNOCKBACK_VELOCITY_MAX: float = 6.0  # m/s — prevents off-screen yeets

const BOSS_WHELP_SCENE: PackedScene = preload("res://scenes/entities/boss_whelp.tscn")

@export var phase_1_summon_interval: float = 3.0
@export var phase_2_summon_interval: float = 2.0
@export var phase_3_summon_interval: float = 4.0
@export var contact_damage: int = 30
@export var contact_interval: float = 1.5

var hp: int = MAX_HP
var _player: Node = null
var _summon_timer: float = 0.0
var _contact_timer: float = 0.0
var _phase: int = 1
var _is_dead: bool = false
var _idle_taunt_timer: float = 0.0
var _taunt_cooldown: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _flash_resting_albedo: Color = Color(0, 0, 0, 0)
var _flash_tween: Tween = null

# --- Status effect state (Phase 9) ---
const FREEZE_THRESHOLD: int = 5
const FREEZE_DURATION: float = 1.5
const SLOW_PER_CHILL_STACK: float = 0.15

var _burn_dps: float = 0.0
var _burn_remaining: float = 0.0
var _burn_residual: float = 0.0  # Accumulator for fractional DoT damage (residual integer-accumulator pattern, mirrors Task 2)
var _chill_stacks: int = 0
var _frozen_remaining: float = 0.0
var _slow_pct: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0

signal phase_changed(new_phase: int)
signal died

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = collision_mask | 8  # also block on bone walls (layer 4)
	_find_player()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_tick_status_effects(delta)
	if _is_dead:
		return
	_advance_taunt_timers(delta)
	if _should_fire_idle_taunt():
		_show_taunt("boss_idle")
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return
	# Frozen or stunned: skip movement, contact attacks, and summons (early return).
	if is_frozen() or is_stunned():
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 9.8 * delta if not is_on_floor() else 0.0
		move_and_slide()
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	var effective_speed: float = MOVE_SPEED * (1.0 - _slow_pct)
	if dist > 2.5:
		velocity.x = to_player.normalized().x * effective_speed
		velocity.z = to_player.normalized().z * effective_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _contact_timer <= 0.0 and _player.has_method("take_damage"):
			# Only record damage source if the hit will actually land (not i-framed).
			if not (_player.has_method("is_invincible") and _player.is_invincible()):
				RunStats.record_damage_from(display_name())
			_player.take_damage(contact_damage)
			_contact_timer = contact_interval
	if _contact_timer > 0.0:
		_contact_timer = max(0.0, _contact_timer - delta)
	_summon_timer += delta
	var interval: float = _interval_for_phase()
	if _summon_timer >= interval:
		_summon_timer = 0.0
		_summon_whelp()
	# Apply knockback impulse on top of tracking velocity, then decay.
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

func _interval_for_phase() -> float:
	match _phase:
		1: return phase_1_summon_interval
		2: return phase_2_summon_interval
		3: return phase_3_summon_interval
		_: return phase_1_summon_interval

func _summon_whelp() -> void:
	var whelp: CharacterBody3D = BOSS_WHELP_SCENE.instantiate()
	var angle: float = randf() * TAU
	var spawn_pos: Vector3 = global_position + Vector3(cos(angle) * 5.0, 1.0, sin(angle) * 5.0)
	get_parent().add_child(whelp)
	whelp.global_position = spawn_pos

func flash_hit(duration: float = 0.18) -> void:
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
	if _flash_resting_albedo.a == 0.0:
		_flash_resting_albedo = mat.albedo_color
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
	# Boss is immune to freeze. Chill stacks still drive slow (capped just
	# below freeze threshold so they never tip over).
	_chill_stacks = mini(_chill_stacks + stacks, FREEZE_THRESHOLD - 1)
	apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)

func apply_stun(_duration: float) -> void:
	# Boss is immune to stun. Hard CC is for trash mobs.
	pass

func apply_slow(pct: float, duration: float) -> void:
	_slow_pct = max(_slow_pct, pct)
	_slow_remaining = max(_slow_remaining, duration)

func apply_pull_toward(target_pos: Vector3, impulse: float) -> void:
	var dir: Vector3 = target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var effective_impulse: float = impulse / _mass()
	_knockback_velocity += dir.normalized() * effective_impulse
	_clamp_knockback_velocity()

func _mass() -> float:
	return 5.0  # boss is heavy

func _clamp_knockback_velocity() -> void:
	if _knockback_velocity.length() > KNOCKBACK_VELOCITY_MAX:
		_knockback_velocity = _knockback_velocity.normalized() * KNOCKBACK_VELOCITY_MAX

func is_frozen() -> bool:
	return _frozen_remaining > 0.0

func is_stunned() -> bool:
	return _stun_remaining > 0.0

func _tick_status_effects(delta: float) -> void:
	# Burn DoT — residual accumulator pattern (mirrors welp.gd Task 2 fix).
	# Floors per-frame would over-deal at high framerate; accumulate fractional
	# damage and apply integer chunks instead.
	if _burn_remaining > 0.0:
		_burn_residual += _burn_dps * delta
		var burn_dmg: int = int(_burn_residual)
		if burn_dmg > 0:
			_burn_residual -= float(burn_dmg)
			if not _is_dead:
				hp = max(0, hp - burn_dmg)
				if hp == 0:
					take_damage(0)  # trigger death path via hp==0 branch
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

func display_name() -> String:
	return "the dragon"

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	hp = max(0, hp - amount)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		died.emit()
		RunStats.record_kill()
		BossFlow.boss_killed()
		ScreenShake.shake(0.18, 0.4)
		Vfx.spawn_death_burst(global_position + Vector3(0, 1, 0), Color(0.6, 0.1, 0.1), get_parent())
		# Speak the dying necromancer's last word in the courtyard so the moment
		# of triumph happens here, not on the post-transition fade-in. Mark it
		# shown so main_hall's cutscene controller doesn't replay it.
		var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false) as CanvasLayer
		if banner != null and not BossFlow.has_shown_victory_line():
			banner.show_line("victory")
			BossFlow.mark_victory_line_shown()
		# Slow-mo: 1.0 → 0.15 over 150ms, hold 1.8s on the dying boss, → 1.0
		# over 400ms, then transition. Long hold gives the victory line time to
		# read and the death burst time to dissipate.
		var tw: Tween = create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_property(Engine, "time_scale", 0.15, 0.15)
		tw.tween_interval(1.8)
		tw.tween_property(Engine, "time_scale", 1.0, 0.4)
		tw.tween_callback(func():
			GameState.transition_to(GameState.Location.MAIN_HALL)
			queue_free()
		)

func _advance_taunt_timers(delta: float) -> void:
	_idle_taunt_timer += delta
	if _taunt_cooldown > 0.0:
		_taunt_cooldown = max(0.0, _taunt_cooldown - delta)

func _should_fire_idle_taunt() -> bool:
	return _idle_taunt_timer >= IDLE_TAUNT_INTERVAL and _taunt_cooldown <= 0.0

func _record_taunt_fired() -> void:
	_idle_taunt_timer = 0.0
	_taunt_cooldown = TAUNT_COOLDOWN_SECONDS

func _find_dialogue_banner() -> CanvasLayer:
	return get_tree().root.find_child("DialogueBanner", true, false) as CanvasLayer

func _show_taunt(category: String) -> void:
	# Always record the attempt so timers reset, even if the banner is missing.
	# Otherwise a missing banner would cause per-frame tree scans.
	_record_taunt_fired()
	var banner: CanvasLayer = _find_dialogue_banner()
	if banner == null:
		return
	if not banner.has_method("show_line"):
		return
	banner.show_line(category)

func _check_phase_transition() -> void:
	var pct: float = float(hp) / float(MAX_HP)
	var new_phase: int = _phase
	if pct <= PHASE_3_HP_PCT:
		new_phase = 3
	elif pct <= PHASE_2_HP_PCT:
		new_phase = 2
	if new_phase != _phase:
		_phase = new_phase
		phase_changed.emit(_phase)
		ScreenShake.shake(0.12, 0.3)
		# Suppress phase taunts on lethal blow — the victory line will follow.
		if hp > 0:
			if _phase == 2:
				_show_taunt("phase_2_taunt")
			elif _phase == 3:
				_show_taunt("phase_3_taunt")
