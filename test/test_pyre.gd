extends GdUnitTestSuite

const PyreScript = preload("res://scripts/interactables/pyre.gd")

var pyre: Node3D

func before_test() -> void:
	# autoloads are running; reset their state for isolation
	SoulEconomy._reset_state()
	pyre = auto_free(PyreScript.new())
	pyre.color = "red"
	add_child(pyre)
	# _ready runs

func test_pyre_reads_initial_fill_from_economy() -> void:
	SoulEconomy.add_to_carry("red", "minor", 50)
	SoulEconomy.deposit_to_pyres()
	pyre.refresh_visual()  # method called manually for test
	assert_that(pyre.fill_ratio).is_equal_approx(50.0 / 250.0, 0.001)

func test_pyre_responds_to_pyre_filled_signal() -> void:
	SoulEconomy.add_to_carry("red", "minor", 250)
	SoulEconomy.deposit_to_pyres()
	await get_tree().process_frame
	assert_that(pyre.is_fully_lit).is_true()
