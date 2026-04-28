extends GdUnitTestSuite

const WelpScript = preload("res://scripts/entities/welp.gd")

var welp: CharacterBody3D

func before_test() -> void:
	welp = auto_free(CharacterBody3D.new())
	welp.set_script(WelpScript)
	add_child(welp)

func test_apply_knockback_zero_direction_is_noop() -> void:
	welp.apply_knockback(Vector3.ZERO, 5.0)
	assert_that(welp._knockback_velocity).is_equal(Vector3.ZERO)

func test_apply_knockback_sets_velocity_proportional_to_force() -> void:
	welp.apply_knockback(Vector3.RIGHT, 4.0)
	assert_that(welp._knockback_velocity.x).is_equal_approx(4.0, 0.001)
	assert_that(welp._knockback_velocity.y).is_equal_approx(0.0, 0.001)
	assert_that(welp._knockback_velocity.z).is_equal_approx(0.0, 0.001)

func test_apply_knockback_zeroes_y_component() -> void:
	# Even if the input direction has y, y component is dropped.
	welp.apply_knockback(Vector3(1, 1, 0), 4.0)
	assert_that(welp._knockback_velocity.y).is_equal_approx(0.0, 0.001)

func test_consecutive_knockbacks_accumulate() -> void:
	# Welp mass = 1.0, so effective force == force. Two 2.0 pushes → 4.0
	# (stays under KNOCKBACK_VELOCITY_MAX = 6.0 clamp).
	welp.apply_knockback(Vector3.RIGHT, 2.0)
	welp.apply_knockback(Vector3.RIGHT, 2.0)
	assert_that(welp._knockback_velocity.x).is_equal_approx(4.0, 0.001)
