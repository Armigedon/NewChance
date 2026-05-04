extends GdUnitTestSuite

const SlamScript = preload("res://scripts/entities/boss_mechanics/mechanic_slam.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var slam: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(1.5, 0, 0)  # within 2m AoE
	await get_tree().process_frame
	# Clear auto-registered mechanics so this test controls the mechanic set.
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	slam = SlamScript.new()
	boss._register_mechanic(slam)
	# Arm a large initial cooldown so the scheduler doesn't auto-fire during setup.
	slam._cooldown_remaining = 99.0
	await get_tree().process_frame
	# Re-anchor positions after GdUnit4 setup frames may have drifted things.
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(1.5, 0, 0)

func test_slam_has_correct_timings() -> void:
	assert_float(slam.windup_duration).is_equal(0.6)
	assert_float(slam.execution_duration).is_equal_approx(0.0, 0.001)

func test_slam_unlocked_at_phase_1() -> void:
	assert_int(slam.unlock_phase).is_equal(1)

func test_slam_damages_player_in_aoe_on_execution() -> void:
	# Ensure positions are clean regardless of inter-test drift in the full suite.
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(1.5, 0, 0)
	await get_tree().physics_frame  # let positions settle
	var initial_hp: int = player.hp
	slam.trigger(1)
	# Advance through windup + execution by directly ticking the mechanic.
	# Using tick() avoids relying on boss _physics_process timing in the full suite.
	var ticked: float = 0.0
	while ticked < 1.0:
		slam.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_int(player.hp).is_less(initial_hp)

func test_slam_does_not_damage_player_outside_aoe() -> void:
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(5, 0, 0)  # well outside 2m
	await get_tree().physics_frame  # let positions settle
	var initial_hp: int = player.hp
	slam.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.0:
		slam.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_int(player.hp).is_equal(initial_hp)
