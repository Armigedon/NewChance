extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	breath._cooldown_remaining = 99.0
	await get_tree().process_frame

func test_pull_during_windup_rotates_cone_aim() -> void:
	breath.trigger(1)
	breath._aim_dir = Vector3.FORWARD
	# Pull origin is to the +X side of the boss; aim should rotate toward +X
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	var aim: Vector3 = breath.current_aim()
	var expected: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(15.0))
	assert_float(aim.x).is_equal_approx(expected.x, 0.01)
	assert_float(aim.z).is_equal_approx(expected.z, 0.01)

func test_pull_outside_windup_does_not_redirect() -> void:
	breath._aim_dir = Vector3.FORWARD
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	# No windup active; aim untouched
	assert_vector(breath.current_aim()).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.01)

func test_pull_to_left_rotates_negative() -> void:
	breath.trigger(1)
	breath._aim_dir = Vector3.FORWARD
	# Pull origin is to the -X side of the boss; aim should rotate toward -X
	boss.apply_pull_toward(Vector3(-2, 0, 1), 1.0)
	var aim: Vector3 = breath.current_aim()
	var expected: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-15.0))
	assert_float(aim.x).is_equal_approx(expected.x, 0.01)
	assert_float(aim.z).is_equal_approx(expected.z, 0.01)
