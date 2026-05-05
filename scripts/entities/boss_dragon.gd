extends CharacterBody3D

const Vfx = preload("res://scripts/effects/vfx.gd")
const MechanicSlam = preload("res://scripts/entities/boss_mechanics/mechanic_slam.gd")
const MechanicStaticBreath = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const MechanicMark = preload("res://scripts/entities/boss_mechanics/mechanic_mark.gd")
const MechanicJump = preload("res://scripts/entities/boss_mechanics/mechanic_jump.gd")
const MechanicSweepingBreath = preload("res://scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd")
const MechanicArmorWings = preload("res://scripts/entities/boss_mechanics/mechanic_armor_wings.gd")

const MAX_HP_TEST: int = 150
const MAX_HP_SHIP: int = 3000
static var MAX_HP: int = MAX_HP_TEST if Debug.FAST_TEST else MAX_HP_SHIP
const MOVE_SPEED: float = 2.0
const PHASE_2_HP_PCT: float = 0.66
const PHASE_3_HP_PCT: float = 0.33
const IDLE_TAUNT_INTERVAL: float = 18.0
const TAUNT_COOLDOWN_SECONDS: float = 5.0
const KNOCKBACK_DECAY: float = 12.0
const KNOCKBACK_VELOCITY_MAX: float = 6.0  # m/s — prevents off-screen yeets
const CONE_REDIRECT_PER_PULL_DEG: float = 15.0

const WALL_CONTACT_DAMAGE_PER_SECOND: int = 10
const WALL_CONTACT_SLOW_PCT: float = 0.3

const POSITION_HISTORY_WINDOW: float = 2.0
const POSITION_HISTORY_INTERVAL: float = 0.1

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
var _mechanics: Array[Node] = []
var _idle_taunt_timer: float = 0.0
var _taunt_cooldown: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _flash_resting_albedo: Color = Color(0, 0, 0, 0)
var _flash_tween: Tween = null

# --- Position-history + damage tracking (Task 16) ---
var _position_history: Array = []  # [{time_msec: int, pos: Vector3}, ...]
var _damage_in_window_msec: int = 0  # last time damage was taken (msec)
var _position_history_timer: float = 0.0

# --- Status effect state (Phase 9) ---
const FREEZE_THRESHOLD: int = 5
const FREEZE_DURATION: float = 1.5
const SLOW_PER_CHILL_STACK: float = 0.15

var _wall_contact_residuals: Dictionary = {}  # instance_id -> fractional dmg accumulator

var _burn_dps: float = 0.0
var _burn_remaining: float = 0.0
var _burn_residual: float = 0.0  # Accumulator for fractional DoT damage (residual integer-accumulator pattern, mirrors Task 2)
var _chill_stacks: int = 0
var _frozen_remaining: float = 0.0
var _slow_pct: float = 0.0
var _slow_remaining: float = 0.0
var _stun_remaining: float = 0.0

# Damage rate cap — bosses cap incoming DPS to prevent DoT/cloud-spam melts.
# 15 dmg per 0.5s = 30 dps theoretical ceiling. Combined with 3000 HP this targets
# ~2 minutes against the heaviest single-skill stack (heavy build measured ~26 actual dps).
const DMG_CAP_PER_TICK: int = 15
const DMG_TICK_INTERVAL: float = 0.5

var _dmg_taken_this_tick: int = 0
var _dmg_tick_remaining: float = DMG_TICK_INTERVAL

signal phase_changed(new_phase: int)
signal died

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 2
	collision_mask = collision_mask | 8  # also block on bone walls (layer 4)
	DamageMeter.start_for_target(self)
	_find_player()
	_register_mechanic(MechanicSlam.new())
	_register_mechanic(MechanicStaticBreath.new())
	_register_mechanic(MechanicMark.new())
	_register_mechanic(MechanicJump.new())
	_register_mechanic(MechanicSweepingBreath.new())
	_register_mechanic(MechanicArmorWings.new())

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_tick_status_effects(delta)
	if _is_dead:
		return  # burn DoT may have killed us mid-tick; skip the rest of this frame
	_tick_mechanics(delta)
	# Position history sampling for jump-trigger detection (Task 16)
	_position_history_timer += delta
	if _position_history_timer >= POSITION_HISTORY_INTERVAL:
		_position_history_timer = 0.0
		_record_position_history(global_position)
	# Damage rate cap tick — reset the per-tick counter when interval elapses
	_dmg_tick_remaining -= delta
	if _dmg_tick_remaining <= 0.0:
		_dmg_taken_this_tick = 0
		_dmg_tick_remaining = DMG_TICK_INTERVAL
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
	_apply_wall_contact_damage(delta)
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
	var prior_stacks: int = _chill_stacks
	_chill_stacks = mini(_chill_stacks + stacks, FREEZE_THRESHOLD - 1)
	var added: int = _chill_stacks - prior_stacks
	apply_slow(SLOW_PER_CHILL_STACK * float(_chill_stacks), 1.0)
	for m in _mechanics:
		if not m.has_method("on_chill_applied"):
			continue
		m.on_chill_applied(added)

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
	# Forward to any breath mechanic in windup for cone redirect.
	# Mechanics self-filter via is_in_windup(); mutual exclusivity ensures
	# at most one breath-style mechanic is in windup at a time.
	for m in _mechanics:
		if not m.has_method("on_pull_during_windup"):
			continue
		m.on_pull_during_windup(target_pos, CONE_REDIRECT_PER_PULL_DEG)
	var effective_impulse: float = impulse / _mass()
	_knockback_velocity += dir.normalized() * effective_impulse
	_clamp_knockback_velocity()

func _mass() -> float:
	return 5.0  # boss is heavy

func _clamp_knockback_velocity() -> void:
	if _knockback_velocity.length() > KNOCKBACK_VELOCITY_MAX:
		_knockback_velocity = _knockback_velocity.normalized() * KNOCKBACK_VELOCITY_MAX

func _apply_wall_contact_damage(delta: float) -> void:
	# NOTE(spec §4): spec describes a 30-damage one-shot break + 1s slow burst.
	# Plan opted for a 10 dmg/sec bleed + persistent slow while in contact. The
	# bleed approach gives finer-grained interaction with breath-blocked wall
	# damage but is mechanically softer than the spec implies. Defer reconciliation
	# to Task 27 / spec amendment.
	# TODO(Task 27): wall slow currently multiplies post-knockback velocity, so it
	# stacks multiplicatively with chill (4-stack chill + wall = 0.28× base, not
	# 0.10× base as additive composition would imply).
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	var slowed: bool = false
	var boss_flat: Vector2 = Vector2(global_position.x, global_position.z)
	var seen_ids: Dictionary = {}
	for w in walls:
		if not is_instance_valid(w):
			continue
		var wall_flat: Vector2 = Vector2(w.global_position.x, w.global_position.z)
		if boss_flat.distance_to(wall_flat) <= 1.0:
			# Per-wall residual so multi-wall contact damages each at the configured
			# rate independently (instead of all walls sharing one fractional bucket).
			var wid: int = w.get_instance_id()
			seen_ids[wid] = true
			var residual: float = _wall_contact_residuals.get(wid, 0.0)
			residual += float(WALL_CONTACT_DAMAGE_PER_SECOND) * delta
			var integer_dmg: int = int(residual)
			if integer_dmg > 0:
				residual -= float(integer_dmg)
				if w.has_method("take_damage"):
					w.take_damage(integer_dmg)
			_wall_contact_residuals[wid] = residual
			slowed = true
	# Drop residuals for walls no longer in contact so they don't accumulate forever.
	for wid in _wall_contact_residuals.keys():
		if not seen_ids.has(wid):
			_wall_contact_residuals.erase(wid)
	if slowed:
		velocity.x *= (1.0 - WALL_CONTACT_SLOW_PCT)
		velocity.z *= (1.0 - WALL_CONTACT_SLOW_PCT)

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
				var hp_before: int = hp
				take_damage_with_source(burn_dmg, "burn")  # burn pierces armor wings (Task 20)
				DamageMeter.record(self, burn_dmg, hp_before - hp, "burn")
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

# --- Mechanic registry + per-frame scheduler ---

func _record_position_history(pos: Vector3) -> void:
	var now_msec: int = Time.get_ticks_msec()
	_position_history.append({"time_msec": now_msec, "pos": pos})
	var cutoff_msec: int = now_msec - int(POSITION_HISTORY_WINDOW * 1000.0)
	while not _position_history.is_empty() and _position_history[0].time_msec < cutoff_msec:
		_position_history.pop_front()

func _record_damage_taken(_amt: int) -> void:
	_damage_in_window_msec = Time.get_ticks_msec()

func position_change_in_window() -> float:
	if _position_history.size() < 2:
		return 0.0
	var first: Vector3 = _position_history[0].pos
	var last: Vector3 = _position_history[-1].pos
	return first.distance_to(last)

func damage_taken_within(window_seconds: float) -> bool:
	var cutoff_msec: int = Time.get_ticks_msec() - int(window_seconds * 1000.0)
	return _damage_in_window_msec >= cutoff_msec

func _register_mechanic(m: Node) -> void:
	add_child(m)
	_mechanics.append(m)

func _any_mechanic_busy() -> bool:
	for m in _mechanics:
		if m.is_busy() and m.is_big:
			return true
	return false

func _tick_mechanics(delta: float) -> void:
	var phase: int = _phase
	for m in _mechanics:
		m.tick(delta, phase)
	if _any_mechanic_busy():
		return
	# Pick one ready big mechanic to fire — non-big mechanics (e.g. triggered jump)
	# self-trigger via their own tick() and are intentionally excluded here.
	var ready: Array[Node] = []
	for m in _mechanics:
		if m.is_big and m.is_ready(phase):
			ready.append(m)
	if ready.is_empty():
		return
	# Random selection from ready set
	var pick: Node = ready[randi() % ready.size()]
	pick.trigger(phase)

func display_name() -> String:
	return "the dragon"

func take_damage(amount: int) -> void:
	take_damage_with_source(amount, "")

func take_damage_with_source(amount: int, source_tag: String) -> void:
	if _is_dead:
		return
	# Apply armor wings reduction unless the source is "burn" (red burn pierces wings).
	if source_tag != "burn":
		var reduction: float = _armor_wings_reduction()
		if reduction > 0.0:
			amount = int(float(amount) * (1.0 - reduction))
	# Cap damage taken per DMG_TICK_INTERVAL (default: 30 dmg per 0.5s = 60 dps).
	# Excess damage is lost — the boss is "resisting" beyond the cap.
	var allowed: int = max(0, DMG_CAP_PER_TICK - _dmg_taken_this_tick)
	var actual: int = min(amount, allowed)
	_dmg_taken_this_tick += actual
	hp = max(0, hp - actual)
	if actual > 0:
		_record_damage_taken(actual)
	_check_phase_transition()
	if hp == 0:
		_is_dead = true
		DamageMeter.dump_log()
		DamageMeter.stop()
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

func _armor_wings_reduction() -> float:
	for m in _mechanics:
		if m.has_method("current_reduction_pct"):
			var r: float = m.current_reduction_pct()
			if r > 0.0:
				return r
	return 0.0

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
