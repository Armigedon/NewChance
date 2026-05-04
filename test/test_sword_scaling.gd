extends GdUnitTestSuite

const SwordScene: PackedScene = preload("res://scenes/entities/sword.tscn")

var sword: Area3D

func before_test() -> void:
	sword = auto_free(SwordScene.instantiate())
	add_child(sword)
	await get_tree().process_frame

func test_sword_dmg_no_white_returns_base() -> void:
	sword.set_active_element("red", 0)
	assert_that(sword.scaled_damage()).is_equal(15)

func test_sword_dmg_white_base_n1_scales() -> void:
	# n = 0 modifiers + 1 (white base) = 1; mult = 1 + 1*(1 - 0.7^1) = 1.30; floor(15*1.30) = 19
	sword.set_active_element("white", 0)
	assert_that(sword.scaled_damage()).is_equal(19)

func test_sword_dmg_white_base_with_modifiers() -> void:
	# n = 4 + 1 = 5; mult = 1 + 1*(1 - 0.7^5) = 1.832; floor(15*1.832) = 27
	sword.set_active_element("white", 4)
	assert_that(sword.scaled_damage()).is_equal(27)

func test_sword_dmg_caps_at_2x() -> void:
	# Very high n approaches 2.0x -> floor(30) = 30
	sword.set_active_element("red", 100)
	assert_that(sword.scaled_damage()).is_equal(29)
