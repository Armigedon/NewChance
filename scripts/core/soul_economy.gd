extends Node

const PYRE_CAP: int = 250
const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
const SOUL_VALUES: Dictionary = {
	"minor": 1,
	"elder": 10,
}

signal pyre_filled(color: String)
signal pyre_fill_changed(color: String, new_fill: int)

var _carry: Dictionary = {}     # { color: { tier: count } }
var _pyres: Dictionary = {}     # { color: int (0..PYRE_CAP) }
var _filled_pyres: Dictionary = {}  # { color: bool } — track which already emitted filled signal

func _ready() -> void:
	reset_meta()

func reset_run() -> void:
	# Clears in-run state only (carry pool). Pyre fills + filled flags persist.
	clear_carry()

func reset_meta() -> void:
	# Clears all state including pyres. New-game / test isolation use only.
	_carry.clear()
	_pyres.clear()
	_filled_pyres.clear()
	for color in COLORS:
		_carry[color] = {"minor": 0, "elder": 0}
		_pyres[color] = 0
		_filled_pyres[color] = false

func add_to_carry(color: String, tier: String, count: int) -> void:
	assert(color in COLORS, "unknown color: %s" % color)
	assert(tier in SOUL_VALUES, "unknown tier: %s" % tier)
	_carry[color][tier] += count

func carry_count(color: String, tier: String) -> int:
	return _carry[color][tier]

func pyre_fill(color: String) -> int:
	return _pyres[color]

func clear_carry() -> void:
	for color in COLORS:
		_carry[color] = {"minor": 0, "elder": 0}

func deposit_to_pyres() -> void:
	for color in COLORS:
		var fill_units: int = (
			_carry[color]["minor"] * SOUL_VALUES["minor"]
			+ _carry[color]["elder"] * SOUL_VALUES["elder"]
		)
		if fill_units == 0:
			continue
		var old_fill: int = _pyres[color]
		var new_fill: int = min(_pyres[color] + fill_units, PYRE_CAP)
		var was_full: bool = _filled_pyres[color]
		_pyres[color] = new_fill
		if new_fill != old_fill:
			pyre_fill_changed.emit(color, new_fill)
		if new_fill >= PYRE_CAP and not was_full:
			_filled_pyres[color] = true
			pyre_filled.emit(color)
	clear_carry()

func has_any_carry() -> bool:
	for color in COLORS:
		if _carry[color]["minor"] > 0 or _carry[color]["elder"] > 0:
			return true
	return false
