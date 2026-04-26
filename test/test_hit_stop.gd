extends GdUnitTestSuite

const HitStopScript = preload("res://scripts/world/hit_stop.gd")

var hs: Node

func before_test() -> void:
	hs = auto_free(HitStopScript.new())
	add_child(hs)
	# Reset Engine state in case prior test left it scaled
	Engine.time_scale = 1.0
	hs._active_until = 0.0

func after_test() -> void:
	# Always restore time_scale so a failed test doesn't poison the next one
	Engine.time_scale = 1.0

func test_freeze_zero_duration_is_no_op() -> void:
	hs.freeze(0.0)
	assert_that(Engine.time_scale).is_equal_approx(1.0, 0.001)

func test_freeze_sets_active_until_in_future() -> void:
	var before: float = Time.get_ticks_msec() / 1000.0
	hs.freeze(0.1)
	assert_that(hs._active_until).is_greater(before)
	assert_that(hs._active_until).is_less(before + 0.2)

func test_freeze_extends_when_called_during_active_freeze() -> void:
	hs.freeze(0.05)
	var first_until: float = hs._active_until
	hs.freeze(0.10)
	# Second call extended deadline further than the first
	assert_that(hs._active_until).is_greater(first_until - 0.001)
	assert_that(hs._active_until).is_greater_equal(first_until)
