# GdUnit generated TestSuite
extends GdUnitTestSuite

const WelpScene: PackedScene = preload("res://scenes/entities/welp.tscn")

var welp: CharacterBody3D

func before_test() -> void:
	welp = auto_free(WelpScene.instantiate())
	add_child(welp)
	await get_tree().process_frame

func test_apply_burn_sets_state() -> void:
	welp.apply_burn(10.0, 2.0)
	assert_that(welp._burn_dps).is_equal(10.0)
	assert_that(welp._burn_remaining).is_equal(2.0)

func test_burn_ticks_damage_over_time() -> void:
	welp.hp = 100
	welp.apply_burn(20.0, 1.0)  # 20 dps for 1 sec → 20 dmg total
	var initial_hp: int = welp.hp
	# Simulate 1 second via repeated ticks
	for i in range(60):
		welp._tick_status_effects(1.0 / 60.0)
	var hp_lost: int = initial_hp - welp.hp
	assert_that(hp_lost).is_greater_equal(15)  # allow rounding
	assert_that(hp_lost).is_less_equal(25)

func test_burn_expires_after_duration() -> void:
	welp.apply_burn(5.0, 0.5)
	for i in range(60):
		welp._tick_status_effects(1.0 / 60.0)
	assert_that(welp._burn_remaining).is_equal(0.0)

func test_apply_burn_takes_max_of_concurrent() -> void:
	welp.apply_burn(10.0, 2.0)
	welp.apply_burn(5.0, 5.0)  # higher duration
	assert_that(welp._burn_dps).is_equal(10.0)  # higher dps wins
	assert_that(welp._burn_remaining).is_equal(5.0)  # higher duration wins

func test_apply_chill_increments_stacks() -> void:
	welp.apply_chill(2)
	assert_that(welp._chill_stacks).is_equal(2)
	welp.apply_chill(1)
	assert_that(welp._chill_stacks).is_equal(3)

func test_chill_at_5_stacks_freezes() -> void:
	welp.apply_chill(5)
	assert_that(welp.is_frozen()).is_true()
	assert_that(welp._chill_stacks).is_equal(0)  # reset on freeze
	assert_that(welp._frozen_remaining).is_greater(0.0)

func test_freeze_expires_after_duration() -> void:
	welp.apply_chill(5)
	for i in range(120):
		welp._tick_status_effects(1.0 / 60.0)  # 2 seconds
	assert_that(welp.is_frozen()).is_false()

func test_apply_stun_sets_remaining() -> void:
	welp.apply_stun(0.5)
	assert_that(welp.is_stunned()).is_true()

func test_stun_expires() -> void:
	welp.apply_stun(0.1)
	for i in range(20):
		welp._tick_status_effects(1.0 / 60.0)
	assert_that(welp.is_stunned()).is_false()

func test_apply_slow_reduces_effective_speed() -> void:
	welp.apply_slow(0.5, 1.0)
	# Effective speed multiplier
	assert_that(welp._slow_pct).is_equal(0.5)
	assert_that(welp._slow_remaining).is_equal(1.0)

func test_apply_pull_toward_adds_knockback_velocity() -> void:
	welp.global_position = Vector3(5, 0, 0)
	var prev_kb: Vector3 = welp._knockback_velocity
	welp.apply_pull_toward(Vector3.ZERO, 2.0)
	# Pull toward (0,0,0) from (5,0,0) = -X direction × 2.0
	assert_that(welp._knockback_velocity.x).is_less(prev_kb.x)
