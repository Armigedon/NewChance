class_name DamagePipeline

# Single dispatch point for all damage events. Cast hits, AoE, cloud ticks,
# chain jumps, sword swings — every damage application funnels through apply().
#
# Composition rule: every damage event runs through the base color's native
# layer plus every modifier's layer. Spawners (green LINGER, white WARD) are
# fired separately at cast or impact time via fire_*_spawners.

# --- Layer constants (per-event effects) ---
const CHAIN_RANGE: float = 4.0  # max distance for next chain hop
const BURN_DPS_FRAC: float = 0.25  # burn damage = 25% of cast damage per second
const NATIVE_BURN_DURATION: float = 3.0
const MODIFIER_BURN_DURATION: float = 1.5
const NATIVE_STUN_DURATION: float = 0.5
const NATIVE_PULL_IMPULSE: float = 1.5
const MODIFIER_PULL_IMPULSE: float = 0.8

# --- Spawner constants (cloud LINGER, armor WARD) ---
const SPAWNER_CLOUD_SCENE: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")
const SPAWNER_CLOUD_BASE_LIFETIME: float = 3.0
const SPAWNER_CLOUD_BASE_RADIUS: float = 2.0
const ARMOR_DURATION: float = 5.0

class ChainState extends RefCounted:
	var budget: int = 0
	var hit_set: Dictionary = {}  # instance_id -> true; targets already damaged by this cast's chain

static func apply(target: Node, damage: int, modifier_stack: Array, base_color: String, source_pos: Vector3, chain_state: ChainState = null) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return

	if chain_state == null:
		chain_state = ChainState.new()
		chain_state.budget = _count(modifier_stack, "gold")

	target.take_damage(damage)
	if target.has_method("flash_hit"):
		target.flash_hit()
	ScreenShake.shake(0.02, 0.04)
	chain_state.hit_set[target.get_instance_id()] = true

	# Burn (red): diminishing-returns curve. Red base contributes 3s native;
	# each red modifier extends asymptotically toward +5s via 5.0 * (1 - 0.6^n).
	# Caps at 8s for red base / 5s for cross-color (red modifier on non-red base).
	var red_modifier_count: int = _count(modifier_stack, "red")
	var burn_base: float = 3.0 if base_color == "red" else 0.0
	var burn_bonus: float = 5.0 * (1.0 - pow(0.6, red_modifier_count))
	var total_burn_duration: float = burn_base + burn_bonus
	if total_burn_duration > 0.0 and target.has_method("apply_burn"):
		target.apply_burn(float(damage) * BURN_DPS_FRAC, total_burn_duration)

	_apply_native_layer(target, base_color, damage, source_pos)
	for color in modifier_stack:
		_apply_modifier_layer(target, color, damage, source_pos)

	if chain_state.budget > 0:
		var next: Node = _find_chain_target(target, chain_state.hit_set, CHAIN_RANGE)
		if next != null:
			chain_state.budget -= 1
			apply(next, damage, modifier_stack, base_color, source_pos, chain_state)

static func _apply_native_layer(target: Node, color: String, damage: int, source_pos: Vector3) -> void:
	match color:
		# red: handled additively in apply()
		"blue":
			if target.has_method("apply_chill"):
				target.apply_chill(1)
		"purple":
			if target.has_method("apply_pull_toward"):
				target.apply_pull_toward(source_pos, NATIVE_PULL_IMPULSE)
		"gold":
			if target.has_method("apply_stun"):
				target.apply_stun(NATIVE_STUN_DURATION)
		# green: cast IS the cloud, no per-hit native effect
		# white: cast IS the wall, no damage path

static func _apply_modifier_layer(target: Node, color: String, damage: int, source_pos: Vector3) -> void:
	match color:
		# red: handled additively in apply() (not per-modifier here)
		"blue":
			if target.has_method("apply_chill"):
				target.apply_chill(1)
		"purple":
			if target.has_method("apply_pull_toward"):
				target.apply_pull_toward(source_pos, MODIFIER_PULL_IMPULSE)
		"gold":
			pass  # chain handled in apply()
		"green":
			pass  # spawner — handled in fire_impact_spawners
		"white":
			pass  # player-side — handled in fire_cast_spawners

static func _find_chain_target(prev_target: Node, hit_set: Dictionary, radius: float) -> Node:
	if not is_instance_valid(prev_target):
		return null
	var tree: SceneTree = prev_target.get_tree()
	if tree == null:
		return null
	var enemies: Array = tree.get_nodes_in_group("enemy")
	var best: Node = null
	var best_dist: float = radius
	var origin: Vector3 = prev_target.global_position
	for e in enemies:
		if e == prev_target:
			continue
		if e.get_instance_id() in hit_set:
			continue
		if not is_instance_valid(e):
			continue
		if "_is_dead" in e and e._is_dead:
			continue
		var d: float = e.global_position.distance_to(origin)
		if d < best_dist:
			best = e
			best_dist = d
	return best

static func _count(stack: Array, color: String) -> int:
	var n: int = 0
	for c in stack:
		if c == color:
			n += 1
	return n

# Fired at cast initiation (player._try_cast). Handles white WARD.
static func fire_cast_spawners(skill: Skill, caster: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	if not caster.has_method("apply_armor"):
		return
	var white_count: int = _count(skill.modifier_stack, "white")
	if skill.base_color == "white":
		white_count += 1  # white-base also grants the WARD layer natively
	if white_count > 0:
		caster.apply_armor(white_count, ARMOR_DURATION)

# Fired when a non-spawner cast resolves its primary impact. Handles green LINGER.
# Pass `cast_node` as `world_root_for_spawn` (clouds are added under the cast's parent).
static func fire_impact_spawners(modifier_stack: Array, base_color: String, impact_pos: Vector3, world: Node, base_damage: int) -> void:
	if base_color == "green":
		return  # green-base IS the cloud; don't double-spawn from modifier rule
	var green_count: int = _count(modifier_stack, "green")
	if green_count <= 0:
		return
	if world == null or not is_instance_valid(world):
		return
	var cloud: Node3D = SPAWNER_CLOUD_SCENE.instantiate()
	# Cross-color green modifier: no native lifetime, asymptotic +3s extension
	var lifetime: float = 3.0 * (1.0 - pow(0.5, green_count))
	var tick_dmg: int = max(1, int(float(base_damage) * BURN_DPS_FRAC))
	cloud.configure(lifetime, SPAWNER_CLOUD_BASE_RADIUS, tick_dmg, modifier_stack, base_color)
	world.add_child(cloud)
	cloud.global_position = impact_pos
