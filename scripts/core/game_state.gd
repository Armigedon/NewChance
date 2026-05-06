extends Node

enum Location { MAIN_HALL, UPSTAIRS, COURTYARD }

enum Outcome { DESCENDED, DIED }

const MAIN_HALL_SCENE_PATH: String = "res://scenes/world/main_hall.tscn"
const UPSTAIRS_SCENE_PATH: String = "res://scenes/world/upstairs.tscn"
const COURTYARD_SCENE_PATH: String = "res://scenes/world/courtyard.tscn"

signal location_changed(new_location: Location)
signal run_ended(outcome: Outcome)

var current_location: Location = Location.MAIN_HALL

func _ready() -> void:
	# Defer load until all autoloads have finished _ready (autoload _ready
	# runs in registration order; deferring ensures SoulEconomy / MetaProgress
	# have initialized before we restore saved state into them).
	call_deferred("_load_save_state")

func _load_save_state() -> void:
	var save_data: Dictionary = SaveSystem.load_save()
	if save_data.has("meta"):
		MetaProgress.from_dict(save_data["meta"])
	if save_data.has("pyres"):
		for color in save_data["pyres"]:
			SoulEconomy.set_pyre_fill(color, int(save_data["pyres"][color]))
	# Phase 10: MetaShop currency + ranks + structural unlocks. Loaded BEFORE
	# migrate_to_meta_shop so legacy migration is a no-op when MetaShop already
	# has state (the _migrated flag in MetaProgress is itself preserved by the
	# legacy meta save data, but we also restore explicit MetaShop state here).
	if save_data.has("meta_shop"):
		MetaShop.from_dict(save_data["meta_shop"])
	# Phase 9: migrate legacy MetaProgress state into MetaShop (idempotent via _migrated flag).
	MetaProgress.migrate_to_meta_shop()

static func scene_path_for(location: Location) -> String:
	match location:
		Location.MAIN_HALL:
			return MAIN_HALL_SCENE_PATH
		Location.UPSTAIRS:
			return UPSTAIRS_SCENE_PATH
		Location.COURTYARD:
			return COURTYARD_SCENE_PATH
		_:
			push_error("scene_path_for: unknown location %s" % location)
			return ""

func transition_to(location: Location) -> void:
	current_location = location
	location_changed.emit(location)
	# Notify Escalation about upstairs presence (drives time-alarm)
	Escalation.set_player_upstairs(location == Location.UPSTAIRS)
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
	Escalation.reset()
	# Persist meta progress + pyre fills + MetaShop (currency, ranks, unlocks).
	var save_data: Dictionary = {
		"meta": MetaProgress.to_dict(),
		"pyres": _pyre_fills_dict(),
		"meta_shop": MetaShop.to_dict(),
	}
	SaveSystem.save(save_data)
	transition_to(Location.MAIN_HALL)

func _pyre_fills_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in SoulEconomy.COLORS:
		d[c] = SoulEconomy.pyre_fill(c)
	return d
