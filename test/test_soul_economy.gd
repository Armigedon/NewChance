extends GdUnitTestSuite

const SoulEconomyScript = preload("res://scripts/core/soul_economy.gd")

var econ: Node

func before_test() -> void:
	econ = auto_free(SoulEconomyScript.new())
	add_child(econ)

func test_carry_starts_empty() -> void:
	assert_that(econ.carry_count("red", "minor")).is_equal(0)

func test_pyre_starts_empty() -> void:
	assert_that(econ.pyre_fill("red")).is_equal(0)

func test_add_to_carry_increments_count() -> void:
	econ.add_to_carry("red", "minor", 3)
	assert_that(econ.carry_count("red", "minor")).is_equal(3)

func test_deposit_moves_carry_to_pyres_minor() -> void:
	econ.add_to_carry("red", "minor", 10)
	econ.deposit_to_pyres()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)
	assert_that(econ.pyre_fill("red")).is_equal(10)

func test_pyre_caps_at_250() -> void:
	econ.add_to_carry("red", "minor", 300)
	econ.deposit_to_pyres()
	assert_that(econ.pyre_fill("red")).is_equal(250)

func test_clear_carry_zeroes_pool() -> void:
	econ.add_to_carry("red", "minor", 5)
	econ.clear_carry()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)

func test_pyre_filled_signal_at_100_percent() -> void:
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", 250)
	econ.deposit_to_pyres()
	await assert_signal(econ).is_emitted("pyre_filled", ["red"])

func test_pyre_filled_signal_only_once() -> void:
	econ.add_to_carry("red", "minor", 250)
	econ.deposit_to_pyres()
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", 5)
	econ.deposit_to_pyres()
	await assert_signal(econ).is_not_emitted("pyre_filled")

func test_reset_run_clears_carry_keeps_pyres() -> void:
	econ.add_to_carry("red", "minor", 5)
	econ.deposit_to_pyres()
	econ.add_to_carry("red", "minor", 3)
	econ.reset_run()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)
	assert_that(econ.pyre_fill("red")).is_equal(5)

func test_reset_meta_clears_everything() -> void:
	econ.add_to_carry("red", "minor", 5)
	econ.deposit_to_pyres()
	econ.reset_meta()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)
	assert_that(econ.pyre_fill("red")).is_equal(0)
