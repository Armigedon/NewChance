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

func test_two_pulls_compound_to_30_degrees() -> void:
	# Spec §4: cumulative redirect; two same-side pulls = 30° total.
	breath.trigger(1)
	breath._aim_dir = Vector3.FORWARD
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	var aim: Vector3 = breath.current_aim()
	var expected: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(30.0))
	assert_float(aim.x).is_equal_approx(expected.x, 0.01)
	assert_float(aim.z).is_equal_approx(expected.z, 0.01)

func test_pull_during_execution_does_not_redirect() -> void:
	# Spec §4: redirect only fires during windup. Execution-phase pulls are no-ops.
	breath.trigger(1)
	breath._aim_dir = Vector3.FORWARD
	# Drive past 1.0s windup into execution via direct ticks (deterministic).
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_bool(breath.is_in_execution()).is_true()
	var pre_aim: Vector3 = breath.current_aim()
	boss.apply_pull_toward(Vector3(2, 0, 1), 1.0)
	assert_vector(breath.current_aim()).is_equal_approx(pre_aim, Vector3.ONE * 0.001)
