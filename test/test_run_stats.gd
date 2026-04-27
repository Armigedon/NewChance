extends GdUnitTestSuite

const RunStatsScript = preload("res://scripts/core/run_stats.gd")

var rs: Node

func before_test() -> void:
	rs = auto_free(RunStatsScript.new())
	add_child(rs)

func test_starts_with_zero_kills() -> void:
	assert_that(rs.enemies_slain).is_equal(0)

func test_starts_with_empty_damage_source() -> void:
	assert_that(rs.last_damage_source_name).is_equal("")

func test_record_kill_increments() -> void:
	rs.record_kill()
	rs.record_kill()
	assert_that(rs.enemies_slain).is_equal(2)

func test_record_damage_from_sets_name() -> void:
	rs.record_damage_from("red welp")
	assert_that(rs.last_damage_source_name).is_equal("red welp")

func test_reset_zeroes_state() -> void:
	rs.record_kill()
	rs.record_kill()
	rs.record_damage_from("blue dragon")
	rs.reset_run()
	assert_that(rs.enemies_slain).is_equal(0)
	assert_that(rs.last_damage_source_name).is_equal("")

func test_reset_captures_start_time() -> void:
	var before: int = Time.get_ticks_msec()
	rs.reset_run()
	assert_that(rs.run_start_time_ms).is_greater_equal(before)
	assert_that(rs.run_start_time_ms).is_less(before + 100)

func test_elapsed_seconds_grows_after_reset() -> void:
	rs.reset_run()
	# Small busy-wait so elapsed is measurably nonzero.
	var deadline: int = Time.get_ticks_msec() + 20
	while Time.get_ticks_msec() < deadline:
		pass
	assert_that(rs.elapsed_seconds()).is_greater(0.01)
