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

func test_pyre_caps_at_PYRE_CAP() -> void:
	econ.add_to_carry("red", "minor", SoulEconomyScript.PYRE_CAP * 2)
	econ.deposit_to_pyres()
	assert_that(econ.pyre_fill("red")).is_equal(SoulEconomyScript.PYRE_CAP)

func test_clear_carry_zeroes_pool() -> void:
	econ.add_to_carry("red", "minor", 5)
	econ.clear_carry()
	assert_that(econ.carry_count("red", "minor")).is_equal(0)

func test_pyre_filled_signal_at_100_percent() -> void:
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", SoulEconomyScript.PYRE_CAP)
	econ.deposit_to_pyres()
	await assert_signal(econ).is_emitted("pyre_filled", ["red"])

func test_pyre_filled_signal_only_once() -> void:
	econ.add_to_carry("red", "minor", SoulEconomyScript.PYRE_CAP)
	econ.deposit_to_pyres()
	var monitor := monitor_signals(econ)
	econ.add_to_carry("red", "minor", 1)
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

func test_elder_soul_alone_advances_pyre_by_elder_value() -> void:
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	# pyre advances by SOUL_VALUES["elder"] (clamped at PYRE_CAP)
	var expected: int = min(SoulEconomyScript.SOUL_VALUES["elder"], SoulEconomyScript.PYRE_CAP)
	assert_that(econ.pyre_fill("red")).is_equal(expected)

func test_deposit_mixes_minor_and_elder_correctly() -> void:
	econ.add_to_carry("red", "minor", 1)
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	# 1 minor + 1 elder = 1 + SOUL_VALUES["elder"] (clamped to PYRE_CAP)
	var expected: int = min(1 + SoulEconomyScript.SOUL_VALUES["elder"], SoulEconomyScript.PYRE_CAP)
	assert_that(econ.pyre_fill("red")).is_equal(expected)

func test_deposit_does_not_overflow_with_elder_at_cap() -> void:
	# Push pyre near cap, then add an elder; should clamp to PYRE_CAP exactly.
	var near_cap: int = SoulEconomyScript.PYRE_CAP - 2
	econ.add_to_carry("red", "minor", near_cap)
	econ.add_to_carry("red", "elder", 1)
	econ.deposit_to_pyres()
	assert_that(econ.pyre_fill("red")).is_equal(SoulEconomyScript.PYRE_CAP)

func test_deposit_credits_minor_souls_to_meta_shop() -> void:
	MetaShop.reset_for_test()
	SoulEconomy.add_to_carry("red", "minor", 5)
	SoulEconomy.add_to_carry("blue", "minor", 3)
	SoulEconomy.deposit_to_pyres()
	assert_int(MetaShop.minor_souls()).is_equal(8)

func test_deposit_credits_elder_currency_to_meta_shop() -> void:
	MetaShop.reset_for_test()
	SoulEconomy.add_to_carry("purple", "elder", 2)
	SoulEconomy.deposit_to_pyres()
	assert_int(MetaShop.elder_currency()).is_equal(2)
