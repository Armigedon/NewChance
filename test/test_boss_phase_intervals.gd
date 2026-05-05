extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame

func test_phase_1_whelp_summon_interval() -> void:
	boss._phase = 1
	assert_float(boss._interval_for_phase()).is_equal(4.0)

func test_phase_2_whelp_summon_interval() -> void:
	boss._phase = 2
	assert_float(boss._interval_for_phase()).is_equal(2.5)

func test_phase_3_whelp_summon_interval() -> void:
	boss._phase = 3
	assert_float(boss._interval_for_phase()).is_equal(1.5)

func test_dragon_track_phase_2_interval() -> void:
	boss._phase = 2
	assert_float(boss._dragon_interval_for_phase()).is_equal(12.0)

func test_dragon_track_phase_3_interval() -> void:
	boss._phase = 3
	assert_float(boss._dragon_interval_for_phase()).is_equal(8.0)

func test_dragon_track_phase_1_does_not_summon() -> void:
	boss._phase = 1
	# Phase 1: dragon track inactive (returns 0 or negative to indicate no-summon)
	assert_float(boss._dragon_interval_for_phase()).is_equal(0.0)
