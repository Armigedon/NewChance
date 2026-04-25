extends Node

enum Location { MAIN_HALL, UPSTAIRS }

enum Outcome { DESCENDED, DIED }

const MAIN_HALL_SCENE_PATH: String = "res://scenes/world/main_hall.tscn"
const UPSTAIRS_SCENE_PATH: String = "res://scenes/world/upstairs.tscn"

signal location_changed(new_location: Location)
signal run_ended(outcome: Outcome)

var current_location: Location = Location.MAIN_HALL

static func scene_path_for(location: Location) -> String:
	match location:
		Location.MAIN_HALL:
			return MAIN_HALL_SCENE_PATH
		Location.UPSTAIRS:
			return UPSTAIRS_SCENE_PATH
		_:
			return ""

func transition_to(location: Location) -> void:
	if location == current_location:
		return
	current_location = location
	location_changed.emit(location)
	var path: String = scene_path_for(location)
	if path != "":
		# deferred so signal handlers run before swap
		get_tree().call_deferred("change_scene_to_file", path)

func end_run(outcome: Outcome) -> void:
	if outcome == Outcome.DESCENDED:
		SoulEconomy.deposit_to_pyres()
	elif outcome == Outcome.DIED:
		SoulEconomy.clear_carry()
	run_ended.emit(outcome)
	transition_to(Location.MAIN_HALL)
