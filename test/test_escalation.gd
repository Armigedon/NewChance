extends GdUnitTestSuite

const EscalationScript = preload("res://scripts/world/escalation.gd")

var esc: Node

func before_test() -> void:
	esc = auto_free(EscalationScript.new())
	add_child(esc)
	# Disable autorun process so tests control time via tick()
	esc.set_process(false)

func test_heat_starts_at_zero() -> void:
	assert_that(esc.corner_heat("red")).is_equal(0.0)

func test_heat_ramps_up_when_in_corner() -> void:
	esc.set_player_in_corner("red")
	esc.tick(1.0)
	assert_that(esc.corner_heat("red")).is_equal_approx(5.0, 0.01)

func test_heat_decays_when_player_leaves_corner() -> void:
	esc.set_player_in_corner("red")
	esc.tick(10.0)
	esc.set_player_in_corner("")
	esc.tick(5.0)
	assert_that(esc.corner_heat("red")).is_equal_approx(40.0, 0.01)

func test_heat_capped_at_100() -> void:
	esc.set_player_in_corner("red")
	esc.tick(60.0)
	assert_that(esc.corner_heat("red")).is_equal(100.0)

func test_heat_floor_at_zero() -> void:
	esc.tick(10.0)
	assert_that(esc.corner_heat("red")).is_equal(0.0)

func test_spawn_rate_factor_scales_with_heat() -> void:
	assert_that(esc.spawn_rate_factor(0.0)).is_equal_approx(1.0, 0.01)
	assert_that(esc.spawn_rate_factor(50.0)).is_equal_approx(2.0, 0.01)
	assert_that(esc.spawn_rate_factor(100.0)).is_equal_approx(3.0, 0.01)

func test_tier_roll_low_heat_only_welps() -> void:
	for i in range(20):
		assert_that(esc.roll_tier(20.0)).is_equal("welp")

func test_tier_roll_mid_heat_includes_dragons() -> void:
	var has_dragon: bool = false
	var has_welp: bool = false
	for i in range(50):
		var t: String = esc.roll_tier(50.0)
		if t == "dragon":
			has_dragon = true
		elif t == "welp":
			has_welp = true
	assert_that(has_dragon).is_true()
	assert_that(has_welp).is_true()

func test_tier_roll_high_heat_includes_elders() -> void:
	var has_elder: bool = false
	for i in range(80):
		if esc.roll_tier(85.0) == "elder":
			has_elder = true
			break
	assert_that(has_elder).is_true()

func test_time_alarm_starts_at_zero() -> void:
	assert_that(esc.time_alarm_factor()).is_equal_approx(0.0, 0.01)

func test_time_alarm_ramps_with_upstairs_time() -> void:
	esc.set_player_upstairs(true)
	esc.tick(150.0)
	assert_that(esc.time_alarm_factor()).is_greater(0.0)
	assert_that(esc.time_alarm_factor()).is_less(1.0)

func test_time_alarm_reaches_full_after_5_minutes() -> void:
	esc.set_player_upstairs(true)
	esc.tick(300.0)
	assert_that(esc.time_alarm_factor()).is_equal_approx(1.0, 0.05)

func test_time_alarm_resets_on_leaving_upstairs() -> void:
	esc.set_player_upstairs(true)
	esc.tick(180.0)
	esc.set_player_upstairs(false)
	assert_that(esc.time_alarm_factor()).is_equal_approx(0.0, 0.01)

func test_reset_clears_all_state() -> void:
	esc.set_player_in_corner("red")
	esc.tick(10.0)
	esc.set_player_upstairs(true)
	esc.tick(60.0)
	esc.reset()
	assert_that(esc.corner_heat("red")).is_equal(0.0)
	assert_that(esc.time_alarm_factor()).is_equal(0.0)

func test_current_corner_getter() -> void:
	assert_that(esc.current_corner()).is_equal("")
	esc.set_player_in_corner("blue")
	assert_that(esc.current_corner()).is_equal("blue")
