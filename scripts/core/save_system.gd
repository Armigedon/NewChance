extends Node

const SAVE_PATH: String = "user://save.tres"
const SAVE_VERSION: int = 1

static func save_to_path(path: String, data: Dictionary) -> Error:
	var res := Resource.new()
	res.set_meta("version", SAVE_VERSION)
	res.set_meta("data", data.duplicate(true))
	return ResourceSaver.save(res, path)

static func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var res = load(path)
	if res == null:
		return {}
	return res.get_meta("data", {})

static func save(data: Dictionary) -> Error:
	return save_to_path(SAVE_PATH, data)

static func load_save() -> Dictionary:
	return load_from_path(SAVE_PATH)
