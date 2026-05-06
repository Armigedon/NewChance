extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp: CharacterBody3D

func before_test() -> void:
	for w in get_tree().get_nodes_in_group("enemy"):
		w.queue_free()
	await get_tree().process_frame
	welp = auto_free(WelpScene.instantiate())
	welp.tier = "welp"
	welp.color = "red"
	add_child(welp)
	welp.global_position = Vector3.ZERO

func test_ignite_all_hits_applies_burn_on_hit() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("ignite_all_hits")
	assert_object(m).is_not_null()
	assert_bool(not m.on_hit.is_null()).is_true()
	# Trigger the hook directly with stack_count=1.
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_float(welp._burn_remaining).is_greater(0.0)

func test_chill_all_hits_applies_chill_on_hit() -> void:
	var m: ElderModifier = ElderRegistry.get_modifier("chill_all_hits")
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_int(welp._chill_stacks).is_greater_equal(1)

func test_pull_on_hit_pulls_target() -> void:
	welp.global_position = Vector3(2, 0, 0)
	var m: ElderModifier = ElderRegistry.get_modifier("pull_on_hit")
	var prev_kb: Vector3 = welp._knockback_velocity
	m.on_hit.call(welp, 10, Vector3.ZERO, 1)
	assert_bool(welp._knockback_velocity != prev_kb).is_true()

func test_chain_on_hit_attempts_chain() -> void:
	# Chain modifier should signal chain budget bump; full chain integration
	# is in damage_pipeline (Task 9). Just verify the hook exists.
	var m: ElderModifier = ElderRegistry.get_modifier("chain_on_hit")
	assert_object(m).is_not_null()
	assert_bool(not m.on_hit.is_null()).is_true()

func test_brittle_returns_damage_multiplier_when_target_frozen() -> void:
	welp.apply_chill(5)  # freeze threshold
	var m: ElderModifier = ElderRegistry.get_modifier("brittle")
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_greater(1.5)  # +100% = 2.0x

func test_crushing_mass_returns_damage_multiplier_when_pulled() -> void:
	# Crushing Mass requires a tagged "recently pulled" state on the welp.
	# For the test, manually set the tag.
	welp.set_meta("recently_pulled_until_msec", Time.get_ticks_msec() + 1000)
	var m: ElderModifier = ElderRegistry.get_modifier("crushing_mass")
	var mult: float = m.damage_multiplier.call(welp, 10, 1)
	assert_float(mult).is_greater(1.2)

func test_marrow_pierce_modifier_exists() -> void:
	# Pierce affects projectile travel; verified separately in pipeline tests.
	var m: ElderModifier = ElderRegistry.get_modifier("marrow_pierce")
	assert_object(m).is_not_null()

func test_bone_shield_player_damaged_hook_absorbs() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var m: ElderModifier = ElderRegistry.get_modifier("bone_shield")
	player.set_meta("bone_shield_charges", 1)
	# When charges > 0, on_player_damaged should consume a charge and bypass damage.
	# The test verifies the hook decrements charges; the damage pipeline integration
	# (Task 9) actually reads the meta to short-circuit damage.
	m.on_player_damaged.call(player, 10, 1)
	assert_int(player.get_meta("bone_shield_charges", 0)).is_equal(0)
