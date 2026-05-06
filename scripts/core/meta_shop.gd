extends Node
# Autoload — meta-progression currency + purchase state.
# Replaces the auto-unlock paths in meta_progress.gd. Player drives spend.
#
# Two currency types:
#   - minor_souls: dropped by dragons, earned over many runs, used for stat ranks.
#   - elder_currency: dropped by elder pickups, used for structural unlocks.

const STAT_KEYS: Array[String] = ["vitality", "power", "cast_speed", "pyre_cap", "soul_magnetism"]
const STAT_MAX_RANK: int = 5
const STAT_RANK_COSTS: Array[int] = [5, 15, 50, 150, 400]

# Per-stat per-rank effect (rank_index 0..4 → effect at rank 1..5).
const STAT_VALUES: Dictionary = {
	"vitality": [0.10, 0.20, 0.35, 0.50, 0.75],
	"power": [0.05, 0.10, 0.20, 0.35, 0.50],
	"cast_speed": [0.05, 0.10, 0.15, 0.20, 0.25],
	"pyre_cap": [25, 50, 100, 175, 250],
	"soul_magnetism": [1, 2, 4, 6, 10],
}

const STRUCTURAL_COSTS: Dictionary = {
	"wand_choice": 3,
	"second_modifier_slot": 5,
	"pyre_expansion_1": 3,
	"pyre_expansion_2": 4,
	"pyre_expansion_3": 5,
	"pyre_expansion_4": 6,
	"pyre_expansion_5": 7,
	"replenish_on_descent": 4,
	"elder_sense": 2,
	"modifier_reroll": 6,
	"build_carry": 8,
	"hard_mode": 5,
	"daily_seed": 3,
	"frost_dragon": 7,
	"cinder_dragon": 7,
}

var _minor_souls: int = 0
var _elder_currency: int = 0
var _stat_ranks: Dictionary = {}  # stat_key -> rank (0..5)
var _structural_owned: Dictionary = {}  # unlock_id -> true
var _chosen_wand_color: String = "red"

func _ready() -> void:
	for k in STAT_KEYS:
		_stat_ranks[k] = 0

func reset_for_test() -> void:
	_minor_souls = 0
	_elder_currency = 0
	_stat_ranks.clear()
	for k in STAT_KEYS:
		_stat_ranks[k] = 0
	_structural_owned.clear()
	_chosen_wand_color = "red"

func minor_souls() -> int:
	return _minor_souls

func elder_currency() -> int:
	return _elder_currency

func credit_minor_souls(n: int) -> void:
	_minor_souls += n

func credit_elder_currency(n: int) -> void:
	_elder_currency += n

func stat_rank(key: String) -> int:
	return int(_stat_ranks.get(key, 0))

func stat_value(key: String) -> float:
	var rank: int = stat_rank(key)
	if rank == 0:
		return 0.0
	var values: Array = STAT_VALUES.get(key, [])
	if values.size() < rank:
		return 0.0
	return float(values[rank - 1])

func buy_stat_rank(key: String) -> bool:
	if not (key in STAT_KEYS):
		return false
	var rank: int = stat_rank(key)
	if rank >= STAT_MAX_RANK:
		return false
	var cost: int = STAT_RANK_COSTS[rank]
	if _minor_souls < cost:
		return false
	_minor_souls -= cost
	_stat_ranks[key] = rank + 1
	return true

func has_structural(unlock_id: String) -> bool:
	return _structural_owned.has(unlock_id)

func buy_structural(unlock_id: String) -> bool:
	if not STRUCTURAL_COSTS.has(unlock_id):
		return false
	if has_structural(unlock_id):
		return false
	var cost: int = int(STRUCTURAL_COSTS[unlock_id])
	if _elder_currency < cost:
		return false
	_elder_currency -= cost
	_structural_owned[unlock_id] = true
	return true

func set_chosen_wand_color(color: String) -> void:
	_chosen_wand_color = color

func starting_wand_color() -> String:
	if has_structural("wand_choice"):
		return _chosen_wand_color
	return "red"

func to_dict() -> Dictionary:
	return {
		"minor_souls": _minor_souls,
		"elder_currency": _elder_currency,
		"stat_ranks": _stat_ranks.duplicate(),
		"structural_owned": _structural_owned.duplicate(),
		"chosen_wand_color": _chosen_wand_color,
	}

func from_dict(d: Dictionary) -> void:
	_minor_souls = int(d.get("minor_souls", 0))
	_elder_currency = int(d.get("elder_currency", 0))
	var ranks: Dictionary = d.get("stat_ranks", {})
	for k in STAT_KEYS:
		_stat_ranks[k] = int(ranks.get(k, 0))
	_structural_owned.clear()
	for k in d.get("structural_owned", {}).keys():
		_structural_owned[k] = true
	_chosen_wand_color = String(d.get("chosen_wand_color", "red"))
