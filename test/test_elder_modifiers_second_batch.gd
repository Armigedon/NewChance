extends GdUnitTestSuite

# Behavioral tests for the 12 second-batch elder modifiers. Pattern matches
# test_elder_modifiers_first_batch.gd: spawn welps, fire the hook directly,
# assert side effects. Avoids depending on physics ticks where possible.

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp: CharacterBody3D

func before_test() -> void:
	for n in get_tree().get_nodes_in_group("damage_cloud"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("enemy"):
		n.queue_free()
	await get_tree().process_frame
	welp = auto_free(WelpScene.instantiate())
	welp.position = Vector3.ZERO
	add_child(welp)
	await get_tree().process_frame

# --- Red ---

func test_combust_on_kill_damages_nearby_enemies() -> void:
	var other: CharacterBody3D = auto_free(WelpScene.instantiate())
	other.position = Vector3(1.0, 0, 0)
	add_child(other)
	await get_tree().physics_frame
	var initial_hp: int = other.hp
	var m: ElderModifier = ElderRegistry.get_modifier("combust_on_kill")
	# Kill `welp` — fire the hook with welp as the target.
	m.on_kill.call(welp, welp.global_position, 1, null)
	await get_tree().process_frame
	assert_int(other.hp).is_less(initial_hp)

func test_red_mass_multiplier_at_full_hp_is_one() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("red_mass")
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_equal_approx(1.0, 0.01)

func test_red_mass_multiplier_at_half_hp() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("red_mass")
	welp.hp = welp.max_hp / 2
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	# Spec: 2x at 50% missing HP, rank 1.
	assert_float(mult).is_equal_approx(2.0, 0.05)

# --- Blue ---

func test_frostbite_no_bonus_above_threshold() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("frostbite")
	# welp at full HP — above 50% threshold.
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_equal_approx(1.0, 0.01)

func test_frostbite_bonus_below_threshold() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("frostbite")
	welp.hp = max(1, int(welp.max_hp * 0.4))  # 40% HP
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_equal_approx(1.25, 0.01)

func test_glacial_path_spawns_blue_cloud() -> void:
	for n in get_tree().get_nodes_in_group("damage_cloud"):
		n.queue_free()
	await get_tree().process_frame
	var m: ElderModifier = ElderRegistry.get_modifier("glacial_path")
	m.on_cast.call(welp, [], "blue", 1)
	await get_tree().process_frame
	var found_blue: bool = false
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		if c.get("base_color") == "blue":
			found_blue = true
			break
	assert_bool(found_blue).is_true()

# --- Green ---

func test_lingering_mist_lifetime_multiplier() -> void:
	# Static helper math: rank 1 → +50%, rank 2 → +100%.
	assert_float(ElderModGreenLingeringMist.lifetime_multiplier(1)).is_equal_approx(1.5, 0.01)
	assert_float(ElderModGreenLingeringMist.lifetime_multiplier(2)).is_equal_approx(2.0, 0.01)

func test_decay_does_nothing_to_unpoisoned_target() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("decay")
	var prev_slow: float = float(welp.get("_slow_pct"))
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_float(float(welp.get("_slow_pct"))).is_equal_approx(prev_slow, 0.001)

func test_decay_slows_poisoned_target() -> void:
	# Poison routes through apply_burn (see toxin_all_hits).
	welp.apply_burn(2.0, 2.0)
	var m: ElderModifier = ElderRegistry.get_modifier("decay")
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	# Decay rank 1 = 30% slow.
	assert_float(float(welp.get("_slow_pct"))).is_greater_equal(0.30)

# --- Purple ---

func test_singularity_spawns_well_at_trigger_threshold() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("singularity")
	var initial_children: int = get_child_count()
	# Fire 4 times at rank 1 — trigger_at = max(2, 5-1) = 4. First 3 are no-ops.
	for i in range(3):
		m.on_cast.call(welp, [], "purple", 1)
	assert_int(get_child_count()).is_equal(initial_children)
	m.on_cast.call(welp, [], "purple", 1)
	# Singularity adds the well as a child of caster.get_parent() == self in test.
	assert_int(get_child_count()).is_greater(initial_children)

func test_slipstream_multiplier_static() -> void:
	# Static helper math: rank 1 → +20%, rank 2 → +30%.
	assert_float(ElderModPurpleSlipstream.speed_multiplier(1)).is_equal_approx(1.20, 0.01)
	assert_float(ElderModPurpleSlipstream.speed_multiplier(2)).is_equal_approx(1.30, 0.01)

# --- Gold ---

func test_resonance_modifier_registered() -> void:
	# Resonance behavior lives in damage_pipeline's chain recursion (see apply()).
	# This test only verifies the modifier id is registered so it's draftable.
	var m: ElderModifier = ElderRegistry.get_modifier("resonance")
	assert_object(m).is_not_null()
	assert_str(m.color).is_equal("gold")

func test_storm_caller_strikes_other_enemy_when_proc_fires() -> void:
	var other: CharacterBody3D = auto_free(WelpScene.instantiate())
	other.position = Vector3(2.0, 0, 0)
	add_child(other)
	await get_tree().physics_frame
	var initial_hp: int = other.hp
	# Force the proc by calling on_kill repeatedly until damage occurs (max 50
	# attempts gives ~2e-7 chance of all-misses at base 25%).
	var m: ElderModifier = ElderRegistry.get_modifier("storm_caller")
	for i in range(50):
		m.on_kill.call(welp, welp.global_position, 1, null)
		if other.hp < initial_hp:
			break
	assert_int(other.hp).is_less(initial_hp)

# --- White ---

func test_calcify_size_multiplier() -> void:
	# Spec: 1.5x at rank 1, +25% per stack after.
	assert_float(ElderModWhiteCalcify.size_multiplier(1)).is_equal_approx(1.5, 0.01)
	assert_float(ElderModWhiteCalcify.size_multiplier(2)).is_equal_approx(1.75, 0.01)

func test_calcify_lifetime_multiplier() -> void:
	assert_float(ElderModWhiteCalcify.lifetime_multiplier(1)).is_equal_approx(1.5, 0.01)
	assert_float(ElderModWhiteCalcify.lifetime_multiplier(2)).is_equal_approx(1.75, 0.01)

func test_reaper_heals_caster_on_kill() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	# Damage the player so the heal has room to land.
	player.hp = player.max_hp / 2
	var hp_before: int = player.hp
	var m: ElderModifier = ElderRegistry.get_modifier("reaper")
	m.on_kill.call(welp, welp.global_position, 1, player)
	assert_int(player.hp).is_greater(hp_before)
