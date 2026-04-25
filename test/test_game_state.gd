# GdUnit generated TestSuite
extends GdUnitTestSuite

const GameStateScript = preload("res://scripts/core/game_state.gd")

var gs: Node

func before_test() -> void:
	gs = auto_free(GameStateScript.new())
	add_child(gs)

func test_default_location_is_main_hall() -> void:
	assert_that(gs.current_location).is_equal(GameStateScript.Location.MAIN_HALL)

func test_transition_changes_location() -> void:
	gs.transition_to(GameStateScript.Location.UPSTAIRS)
	assert_that(gs.current_location).is_equal(GameStateScript.Location.UPSTAIRS)

func test_transition_emits_signal() -> void:
	var monitor := monitor_signals(gs)
	gs.transition_to(GameStateScript.Location.UPSTAIRS)
	await assert_signal(gs).is_emitted("location_changed", [GameStateScript.Location.UPSTAIRS])

func test_main_hall_scene_path() -> void:
	assert_that(GameStateScript.MAIN_HALL_SCENE_PATH).is_equal("res://scenes/world/main_hall.tscn")

func test_upstairs_scene_path() -> void:
	assert_that(GameStateScript.UPSTAIRS_SCENE_PATH).is_equal("res://scenes/world/upstairs.tscn")

func test_scene_path_for_location_returns_main_hall() -> void:
	assert_that(GameStateScript.scene_path_for(GameStateScript.Location.MAIN_HALL)).is_equal(GameStateScript.MAIN_HALL_SCENE_PATH)

func test_scene_path_for_location_returns_upstairs() -> void:
	assert_that(GameStateScript.scene_path_for(GameStateScript.Location.UPSTAIRS)).is_equal(GameStateScript.UPSTAIRS_SCENE_PATH)

func test_end_run_descended_deposits_to_pyres() -> void:
	SoulEconomy.reset_meta()
	SoulEconomy.add_to_carry("red", "minor", 5)
	gs.end_run(GameStateScript.Outcome.DESCENDED)
	assert_that(SoulEconomy.pyre_fill("red")).is_equal(5)
	assert_that(SoulEconomy.carry_count("red", "minor")).is_equal(0)

func test_end_run_died_clears_carry_without_deposit() -> void:
	SoulEconomy.reset_meta()
	SoulEconomy.add_to_carry("red", "minor", 5)
	gs.end_run(GameStateScript.Outcome.DIED)
	assert_that(SoulEconomy.pyre_fill("red")).is_equal(0)
	assert_that(SoulEconomy.carry_count("red", "minor")).is_equal(0)

func test_end_run_emits_signal_with_outcome() -> void:
	var monitor := monitor_signals(gs)
	gs.end_run(GameStateScript.Outcome.DIED)
	await assert_signal(gs).is_emitted("run_ended", [GameStateScript.Outcome.DIED])
