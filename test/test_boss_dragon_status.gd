extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame

func test_apply_burn_sets_state() -> void:
	boss.apply_burn(10.0, 2.0)
	assert_that(boss._burn_dps).is_equal(10.0)
	assert_that(boss._burn_remaining).is_equal(2.0)

func test_burn_ticks_damage() -> void:
	var initial_hp: int = boss.hp
	boss.apply_burn(20.0, 1.0)
	for i in range(60):
		boss._tick_status_effects(1.0 / 60.0)
	assert_that(initial_hp - boss.hp).is_greater_equal(15)

func test_chill_does_not_freeze_boss() -> void:
	# Boss is CC-immune; chill stacks accumulate but cap below freeze threshold
	boss.apply_chill(5)
	assert_that(boss.is_frozen()).is_false()
	assert_that(boss._chill_stacks).is_less(5)

func test_stun_does_not_apply_to_boss() -> void:
	# Boss is CC-immune to stun
	boss.apply_stun(0.5)
	assert_that(boss.is_stunned()).is_false()

func test_pull_does_not_drag_boss() -> void:
	# Boss is CC-immune (Spec §3): purple pull's intended interaction is the
	# cone-redirect / charge-deflect side effects; the raw movement impulse
	# is suppressed for the boss so a gravity well placed under it can't
	# slow-drag the boss out of position.
	boss.global_position = Vector3(5, 0, 0)
	var prior_kb: Vector3 = boss._knockback_velocity
	boss.apply_pull_toward(Vector3.ZERO, 2.0)
	assert_that(boss._knockback_velocity).is_equal(prior_kb)
