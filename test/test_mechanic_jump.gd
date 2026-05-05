extends GdUnitTestSuite

const JumpMechanic = preload("res://scripts/entities/boss_mechanics/mechanic_jump.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var jump: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	await get_tree().process_frame
	# Null the player ref so the boss does not move toward any stale player
	# nodes left in the scene from prior test suites.
	boss._player = null
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	# Clear position history and damage state so tests are fully isolated.
	boss._position_history.clear()
	boss._damage_in_window_msec = 0
	jump = JumpMechanic.new()
	boss._register_mechanic(jump)
	await get_tree().process_frame

func test_jump_does_not_trigger_when_boss_moving() -> void:
	boss._record_position_history(Vector3.ZERO)
	for i in range(60):
		boss.global_position = Vector3(i * 0.05, 0, 0)
		boss._record_position_history(boss.global_position)
		await get_tree().physics_frame
	boss._record_damage_taken(30)
	assert_bool(jump._should_trigger()).is_false()

func test_jump_triggers_when_stationary_and_taking_damage() -> void:
	boss.global_position = Vector3.ZERO
	for i in range(130):
		boss._record_position_history(Vector3.ZERO)
		await get_tree().physics_frame
	# Reset the gap in case stale effects fired the jump mid-loop — this test
	# specifically validates the stationary+damage condition, not the 3s gap.
	jump._last_jump_time_msec = -10000
	# Refresh position history so entries at ZERO are within the 2s window.
	for i in range(20):
		boss._record_position_history(Vector3.ZERO)
	boss._record_damage_taken(30)
	assert_bool(jump._should_trigger()).is_true()

func test_jump_min_3s_gap_between_jumps() -> void:
	jump._last_jump_time_msec = Time.get_ticks_msec()
	boss.global_position = Vector3.ZERO
	for i in range(130):
		boss._record_position_history(Vector3.ZERO)
		await get_tree().physics_frame
	boss._record_damage_taken(30)
	assert_bool(jump._should_trigger()).is_false()
