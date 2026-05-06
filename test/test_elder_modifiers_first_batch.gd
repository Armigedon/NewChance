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

func test_ignite_all_hits_via_pipeline() -> void:
	# Set up: a player with active red wand carrying ignite_all_hits.
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.start_default_wand("red")
	ss.apply_elder_modifier("ignite_all_hits")
	# Drive a damage event through the pipeline.
	var enemy: CharacterBody3D = auto_free(WelpScene.instantiate())
	enemy.tier = "welp"
	enemy.color = "red"
	add_child(enemy)
	enemy.global_position = Vector3.ZERO
	await get_tree().process_frame
	const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
	DamagePipeline.apply(enemy, 10, ["red"], "red", Vector3.ZERO, "test_cast", null, ss)
	# Burn from native red layer + ignite_all_hits.
	assert_float(enemy._burn_remaining).is_greater(0.0)

func test_chain_on_hit_increases_budget() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.start_default_wand("gold")
	ss.apply_elder_modifier("chain_on_hit")
	# Spawn 3 enemies in a line; expect chain to hit at least 1 extra past the primary.
	var primary: CharacterBody3D = auto_free(WelpScene.instantiate())
	primary.tier = "welp"
	primary.color = "gold"
	add_child(primary)
	primary.global_position = Vector3.ZERO
	var secondary: CharacterBody3D = auto_free(WelpScene.instantiate())
	secondary.tier = "welp"
	secondary.color = "gold"
	add_child(secondary)
	secondary.global_position = Vector3(2, 0, 0)
	await get_tree().process_frame
	const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
	var initial_secondary_hp: int = secondary.hp
	DamagePipeline.apply(primary, 10, ["gold"], "gold", Vector3.ZERO, "test_cast", null, ss)
	# Secondary should be hit by chain.
	assert_int(secondary.hp).is_less(initial_secondary_hp)

# --- Production-path tests (final-review fixes) -----------------------------
# These tests drive the actual production code paths (player.take_damage,
# DamagePipeline.apply with caster, cast configure) rather than calling
# Callables directly. They guard against regressions where the hooks pass
# unit tests but never fire in the real damage pipeline.

func test_overcharge_doubles_damage_via_pipeline_after_third_cast() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	# Player._ready already started a default wand; clear so we can pick gold.
	ss.clear()
	ss.start_default_wand("gold")
	ss.apply_elder_modifier("overcharge")
	var enemy: CharacterBody3D = auto_free(WelpScene.instantiate())
	enemy.tier = "welp"
	enemy.color = "gold"
	add_child(enemy)
	enemy.global_position = Vector3.ZERO
	await get_tree().process_frame
	# Simulate 3 casts via the on_cast hook (production _try_cast iterates these).
	for i in range(3):
		var skill: Skill = ss.active_skill()
		for mid in skill.elder_modifier_stacks.keys():
			var em: ElderModifier = ElderRegistry.get_modifier(mid)
			if em.on_cast.is_null():
				continue
			em.on_cast.call(player, skill.modifier_stack, skill.base_color, skill.elder_modifier_stack_count(mid))
	# Now overcharge_active should be true.
	assert_bool(bool(player.get_meta("overcharge_active", false))).is_true()
	# Drive damage through pipeline; expect the flag to be cleared after the hit
	# (pipeline reads + consumes overcharge_active).
	const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
	var initial_hp: int = enemy.hp
	DamagePipeline.apply(enemy, 10, ["gold"], "gold", Vector3.ZERO, "test_cast", null, ss, player)
	# Verify damage landed and overcharge flag was cleared.
	assert_int(enemy.hp).is_less(initial_hp)
	assert_bool(bool(player.get_meta("overcharge_active", false))).is_false()

func test_bone_shield_absorbs_via_take_damage_in_production() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.clear()
	ss.start_default_wand("white")
	ss.apply_elder_modifier("bone_shield")
	# Charges should seed to 1 on apply (via elder_modifier_applied signal).
	assert_int(int(player.get_meta("bone_shield_charges", 0))).is_equal(1)
	var hp_before: int = player.hp
	player.take_damage(10)
	# First hit absorbed, no HP loss.
	assert_int(player.hp).is_equal(hp_before)
	assert_int(int(player.get_meta("bone_shield_charges", 0))).is_equal(0)
	# Second hit lands.
	player.take_damage(10)
	assert_int(player.hp).is_equal(hp_before - 10)

func test_marrow_pierce_pierces_one_enemy() -> void:
	var player: CharacterBody3D = auto_free(load("res://scenes/entities/player.tscn").instantiate())
	add_child(player)
	await get_tree().process_frame
	var ss: SkillSystem = player.get_node("SkillSystem")
	ss.clear()
	ss.start_default_wand("white")
	ss.apply_elder_modifier("marrow_pierce")
	# Verify the active skill has the modifier so cast scenes can read it.
	assert_int(ss.active_skill().elder_modifier_stack_count("marrow_pierce")).is_equal(1)
	# Cast scene's pierce_budget population happens in cast_base.gd::configure(skill).
	# We instantiate a fireball, configure it, and check.
	const Fireball = preload("res://scenes/skills/cast_red_fireball.tscn")
	var cast = auto_free(Fireball.instantiate())
	cast.spawn_pos = Vector3(0, 0.5, 0)
	cast.configure(ss.active_skill())
	add_child(cast)
	# After configure, pierce_budget should be 1.
	assert_int(cast.pierce_budget).is_equal(1)
