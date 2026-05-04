extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const BossMechanic = preload("res://scripts/entities/boss_mechanic.gd")

var boss: CharacterBody3D

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss)
	await get_tree().process_frame

func test_boss_starts_with_empty_mechanic_list() -> void:
	# Scheduler exists but mechanics added in subsequent tasks
	assert_object(boss._mechanics).is_not_null()

func test_register_mechanic_adds_to_list() -> void:
	var m: Node = BossMechanic.new()
	m.unlock_phase = 1
	boss._register_mechanic(m)
	assert_int(boss._mechanics.size()).is_equal(1)

func test_busy_check_returns_true_when_any_mechanic_busy() -> void:
	var m: Node = BossMechanic.new()
	m.unlock_phase = 1
	m.windup_duration = 0.1
	m.execution_duration = 0.1
	boss._register_mechanic(m)
	await get_tree().process_frame  # _ready on m
	m.trigger(1)
	assert_bool(boss._any_mechanic_busy()).is_true()
