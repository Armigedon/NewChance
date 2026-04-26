extends GdUnitTestSuite

const SaveSystemScript = preload("res://scripts/core/save_system.gd")

const TEST_PATH: String = "user://test_save.tres"

func after_test() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("test_save.tres"):
		dir.remove("test_save.tres")

func test_save_round_trip_pyres() -> void:
	var data: Dictionary = {"pyres": {"red": 100, "blue": 50}}
	SaveSystemScript.save_to_path(TEST_PATH, data)
	var loaded: Dictionary = SaveSystemScript.load_from_path(TEST_PATH)
	assert_that(loaded.get("pyres", {})).is_equal({"red": 100, "blue": 50})

func test_load_missing_file_returns_empty() -> void:
	var loaded: Dictionary = SaveSystemScript.load_from_path("user://nonexistent.tres")
	assert_that(loaded).is_empty()

func test_save_round_trip_complex() -> void:
	var data: Dictionary = {
		"pyres": {"red": 50, "blue": 75},
		"cantrips": {"max_hp": 2, "sword_damage": 1},
		"hub_features_unlocked": 2,
		"sigil_equipped": "elder_drop_bonus",
	}
	SaveSystemScript.save_to_path(TEST_PATH, data)
	var loaded: Dictionary = SaveSystemScript.load_from_path(TEST_PATH)
	assert_that(loaded).is_equal(data)
