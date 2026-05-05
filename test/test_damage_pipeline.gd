extends GdUnitTestSuite

const DamagePipeline = preload("res://scripts/skills/damage_pipeline.gd")
const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp_a: CharacterBody3D
var welp_b: CharacterBody3D
var welp_c: CharacterBody3D

func before_test() -> void:
	welp_a = auto_free(WelpScene.instantiate())
	welp_b = auto_free(WelpScene.instantiate())
	welp_c = auto_free(WelpScene.instantiate())
	add_child(welp_a); welp_a.global_position = Vector3.ZERO
	add_child(welp_b); welp_b.global_position = Vector3(2, 0, 0)
	add_child(welp_c); welp_c.global_position = Vector3(3, 0, 0)
	await get_tree().process_frame

func test_apply_deals_base_damage() -> void:
	var initial_hp: int = welp_a.hp
	DamagePipeline.apply(welp_a, 25, [], "red", Vector3.ZERO)
	assert_that(welp_a.hp).is_equal(initial_hp - 25)

func test_red_base_applies_native_burn() -> void:
	DamagePipeline.apply(welp_a, 25, [], "red", Vector3.ZERO)
	assert_that(welp_a._burn_remaining).is_greater(0.0)
	assert_that(welp_a._burn_dps).is_greater(0.0)

func test_red_base_burn_duration_is_3_seconds() -> void:
	# Red base, 0 red modifiers: 3.0s native + 0s extension
	DamagePipeline.apply(welp_a, 25, [], "red", Vector3.ZERO)
	assert_that(welp_a._burn_remaining).is_equal_approx(3.0, 0.01)

func test_red_modifiers_extend_burn_diminishing() -> void:
	# Red base + 2 red modifiers: 3.0s + 5.0 * (1 - 0.6^2) = 3.0 + 3.2 = 6.2s
	DamagePipeline.apply(welp_a, 25, ["red", "red"], "red", Vector3.ZERO)
	assert_that(welp_a._burn_remaining).is_equal_approx(6.2, 0.01)

func test_red_modifier_on_non_red_base_applies_burn() -> void:
	# Blue base + 1 red modifier: 0s native + 5.0 * (1 - 0.6^1) = 2.0s
	DamagePipeline.apply(welp_a, 25, ["red"], "blue", Vector3.ZERO)
	assert_that(welp_a._burn_remaining).is_equal_approx(2.0, 0.01)

func test_blue_base_applies_chill() -> void:
	DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
	assert_that(welp_a._chill_stacks).is_equal(1)

func test_multiple_blue_modifiers_stack_chill() -> void:
	# Red base + 3 blue modifiers → 1 native red (no chill native) + 3 chill from modifiers
	DamagePipeline.apply(welp_a, 25, ["blue", "blue", "blue"], "red", Vector3.ZERO)
	assert_that(welp_a._chill_stacks).is_equal(3)

func test_gold_base_applies_native_stun() -> void:
	DamagePipeline.apply(welp_a, 25, [], "gold", Vector3.ZERO)
	assert_that(welp_a.is_stunned()).is_true()

func test_gold_modifier_chains_to_nearest() -> void:
	# Red base + 1 gold modifier: hits welp_a, chains once to welp_b (closer than welp_c)
	var hp_a: int = welp_a.hp
	var hp_b: int = welp_b.hp
	var hp_c: int = welp_c.hp
	DamagePipeline.apply(welp_a, 25, ["gold"], "red", Vector3.ZERO)
	assert_that(welp_a.hp).is_equal(hp_a - 25)
	assert_that(welp_b.hp).is_equal(hp_b - 25)  # chained
	assert_that(welp_c.hp).is_equal(hp_c)  # not chained, only 1 jump budget

func test_chain_does_not_double_hit_same_target() -> void:
	# Even with 5 gold modifiers, welp_a should only take 25 once (the primary hit)
	var hp_a: int = welp_a.hp
	DamagePipeline.apply(welp_a, 25, ["gold", "gold", "gold", "gold", "gold"], "red", Vector3.ZERO)
	assert_that(welp_a.hp).is_equal(hp_a - 25)

func test_chain_propagates_layers() -> void:
	# Red base + 1 gold modifier: chain target also gets burn (from red base layer)
	DamagePipeline.apply(welp_a, 25, ["gold"], "red", Vector3.ZERO)
	assert_that(welp_b._burn_remaining).is_greater(0.0)

func test_purple_modifier_pulls_target_on_hit() -> void:
	var prev_kb: Vector3 = welp_a._knockback_velocity
	DamagePipeline.apply(welp_a, 25, ["purple"], "red", Vector3(2, 0, 0))
	# Pull toward source (2, 0, 0) from welp_a (0, 0, 0): +X direction
	assert_that(welp_a._knockback_velocity.x).is_greater(prev_kb.x)

func test_purple_base_applies_native_pull() -> void:
	var prev_kb: Vector3 = welp_a._knockback_velocity
	DamagePipeline.apply(welp_a, 25, [], "purple", Vector3(2, 0, 0))
	assert_that(welp_a._knockback_velocity.x).is_greater(prev_kb.x)

func test_pipeline_handles_multiple_sequential_targets() -> void:
	# Smoke test for AoE-style usage: multiple pipeline.apply calls in a row
	# damage all targets independently. Does NOT test _damage_aoe's radius
	# filter — that's tested implicitly by per-cast integration tests.
	welp_a.global_position = Vector3(0, 0, 0)
	welp_b.global_position = Vector3(1.5, 0, 0)
	welp_c.global_position = Vector3(3.0, 0, 0)
	var hp_a: int = welp_a.hp
	var hp_b: int = welp_b.hp
	var hp_c: int = welp_c.hp
	for e in [welp_a, welp_b]:
		DamagePipeline.apply(e, 25, [], "red", Vector3.ZERO)
	assert_that(welp_a.hp).is_equal(hp_a - 25)
	assert_that(welp_b.hp).is_equal(hp_b - 25)
	assert_that(welp_c.hp).is_equal(hp_c)

func test_ice_line_native_chill() -> void:
	DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
	assert_that(welp_a._chill_stacks).is_equal(1)
	DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
	DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
	DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
	DamagePipeline.apply(welp_a, 25, [], "blue", Vector3.ZERO)
	# 5 chill stacks → freeze
	assert_that(welp_a.is_frozen()).is_true()
