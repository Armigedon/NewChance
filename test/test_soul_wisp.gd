extends GdUnitTestSuite

const SoulWispScript = preload("res://scripts/ui/soul_wisp.gd")

var wisp: Control

func before_test() -> void:
	wisp = auto_free(Control.new())
	wisp.set_script(SoulWispScript)
	add_child(wisp)

func test_default_count_is_zero() -> void:
	assert_that(wisp.count).is_equal(0)

func test_set_count_updates_value() -> void:
	wisp.set_count(5)
	assert_that(wisp.count).is_equal(5)

func test_set_count_zero_marks_dimmed() -> void:
	wisp.set_count(3)
	wisp.set_count(0)
	assert_that(wisp.is_dimmed()).is_true()

func test_set_count_positive_undims() -> void:
	wisp.set_count(0)
	wisp.set_count(2)
	assert_that(wisp.is_dimmed()).is_false()

func test_color_property_persists() -> void:
	wisp.color = Color(0.8, 0.2, 0.1, 1)
	assert_that(wisp.color).is_equal(Color(0.8, 0.2, 0.1, 1))

func test_is_elder_property_persists() -> void:
	wisp.is_elder = true
	assert_that(wisp.is_elder).is_true()
