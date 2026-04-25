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

func test_pyre_fill_changed_emits_with_new_fill() -> void:
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", 7)
	econ.deposit_to_pyres()
	await assert_signal(econ).is_emitted("pyre_fill_changed", ["red", 7])

func test_pyre_fill_changed_not_emitted_when_no_carry_to_deposit() -> void:
	var monitor := monitor_signals(econ)
	econ.deposit_to_pyres()  # no carry, nothing to deposit
	await assert_signal(econ).is_not_emitted("pyre_fill_changed")

func test_carry_changed_emits_with_new_count() -> void:
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", 3)
	await assert_signal(econ).is_emitted("carry_changed", ["red", "minor", 3])

func test_carry_changed_emits_on_clear() -> void:
	econ.add_to_carry("red", "minor", 5)
	var monitor := monitor_signals(econ)
	econ.clear_carry()
	await assert_signal(econ).is_emitted("carry_changed", ["red", "minor", 0])

func test_elder_soul_alone_advances_pyre_by_10() -> void:
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	assert_that(econ.pyre_fill("red")).is_equal(10)

func test_deposit_mixes_minor_and_elder_correctly() -> void:
	econ.add_to_carry("red", "minor", 7)
	econ.add_to_carry("red", "elder", 2)
	econ.deposit_to_pyres()
	# 7 minor (1 each) + 2 elder (10 each) = 7 + 20 = 27
	assert_that(econ.pyre_fill("red")).is_equal(27)

func test_deposit_does_not_overflow_with_elder_at_cap() -> void:
	econ.add_to_carry("red", "minor", 245)
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	# 245 + 10 = 255, clamped to 250
	assert_that(econ.pyre_fill("red")).is_equal(250)
