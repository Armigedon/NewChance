extends Node

const COLORS: Array[String] = ["red", "blue", "green", "purple", "gold", "white"]
const CANTRIP_KEYS: Array[String] = ["max_hp", "sword_damage", "dash_cooldown"]
const CANTRIP_MAX_LEVEL: int = 5
const CANTRIP_BONUSES: Dictionary = {
	"max_hp": 20,
	"sword_damage": 3,
	"dash_cooldown": -0.2,
}
const HUB_FEATURE_MAX: int = 4

const PYRE_DAMAGE_BONUS_25: float = 0.05
const PYRE_DAMAGE_BONUS_75: float = 0.10

signal hub_feature_unlocked(index: int)
signal cantrip_purchased(key: String, new_level: int)

var _cantrips: Dictionary = {}
var _hub_features_unlocked: int = 0
var _filled_pyres: Dictionary = {}
var _pyre_milestones: Dictionary = {}
var _start_with_skill: String = ""
var _migrated: bool = false

func _ready() -> void:
	_init_defaults()
	# Phase 9: pyre_fill_changed → auto-unlock removed; MetaShop is now the canonical purchase state.

func _on_pyre_fill_changed(color: String, new_fill: int) -> void:
	# Compute pct, fire EVERY applicable milestone (handles big jumps).
	var pct: float = (float(new_fill) / float(SoulEconomy.get_pyre_cap())) * 100.0
	var prior_milestone: int = _pyre_milestones.get(color, 0)
	# Walk thresholds in order; fire each not-yet-reached one.
	for m in [25, 50, 75]:
		if pct >= float(m) and prior_milestone < m:
			on_pyre_milestone(color, m)
	if pct >= 100.0:
		on_pyre_full(color)  # also sets milestone to 100

func reset_meta() -> void:
	# Public alias for _init_defaults — full reset of all meta state.
	# Use this from outside the class (e.g., start_screen New Game).
	_init_defaults()

func _init_defaults() -> void:
	_cantrips.clear()
	for k in CANTRIP_KEYS:
		_cantrips[k] = 0
	_hub_features_unlocked = 0
	_filled_pyres.clear()
	for c in COLORS:
		_filled_pyres[c] = false
	_pyre_milestones.clear()
	for c in COLORS:
		_pyre_milestones[c] = 0
	_start_with_skill = ""
	_migrated = false

func cantrip_level(key: String) -> int:
	return _cantrips.get(key, 0)

func cantrip_bonus(key: String) -> int:
	var lvl: int = cantrip_level(key)
	var per_level = CANTRIP_BONUSES.get(key, 0)
	if per_level is int:
		return lvl * per_level
	return int(lvl * per_level)

func cantrip_bonus_float(key: String) -> float:
	var lvl: int = cantrip_level(key)
	var per_level = CANTRIP_BONUSES.get(key, 0)
	return float(lvl) * float(per_level)

func buy_cantrip(key: String) -> bool:
	if not (key in CANTRIP_KEYS):
		return false
	if _cantrips[key] >= CANTRIP_MAX_LEVEL:
		return false
	_cantrips[key] += 1
	cantrip_purchased.emit(key, _cantrips[key])
	return true

func hub_features_unlocked() -> int:
	return _hub_features_unlocked

func unlock_next_hub_feature() -> void:
	if _hub_features_unlocked >= HUB_FEATURE_MAX:
		return
	_hub_features_unlocked += 1
	hub_feature_unlocked.emit(_hub_features_unlocked)

func on_pyre_milestone(color: String, milestone: int) -> void:
	if not (color in COLORS):
		return
	var prior: int = _pyre_milestones.get(color, 0)
	if milestone <= prior:
		return
	_pyre_milestones[color] = milestone
	if milestone == 50:
		unlock_next_hub_feature()

func on_pyre_full(color: String) -> void:
	if not (color in COLORS):
		return
	if _filled_pyres.get(color, false):
		return
	_filled_pyres[color] = true
	_pyre_milestones[color] = 100

func active_skill_cap_bonus() -> int:
	var n: int = 0
	for c in COLORS:
		if _filled_pyres.get(c, false):
			n += 1
	return n

func color_damage_bonus(color: String) -> float:
	var milestone: int = _pyre_milestones.get(color, 0)
	if milestone >= 75:
		return PYRE_DAMAGE_BONUS_75
	if milestone >= 25:
		return PYRE_DAMAGE_BONUS_25
	return 0.0

func set_start_with_skill(color: String) -> void:
	_start_with_skill = color

func consume_start_with_skill() -> String:
	var c: String = _start_with_skill
	_start_with_skill = ""
	return c

func to_dict() -> Dictionary:
	return {
		"cantrips": _cantrips.duplicate(),
		"hub_features_unlocked": _hub_features_unlocked,
		"filled_pyres": _filled_pyres.duplicate(),
		"pyre_milestones": _pyre_milestones.duplicate(),
		"start_with_skill": _start_with_skill,
	}

func from_dict(d: Dictionary) -> void:
	_init_defaults()
	if d.has("cantrips"):
		for k in CANTRIP_KEYS:
			_cantrips[k] = int(d["cantrips"].get(k, 0))
	_hub_features_unlocked = int(d.get("hub_features_unlocked", 0))
	if d.has("filled_pyres"):
		for c in COLORS:
			_filled_pyres[c] = bool(d["filled_pyres"].get(c, false))
	if d.has("pyre_milestones"):
		for c in COLORS:
			_pyre_milestones[c] = int(d["pyre_milestones"].get(c, 0))
	_start_with_skill = String(d.get("start_with_skill", ""))

# --- Phase 9 migration ---

func migrate_to_meta_shop() -> void:
	if _migrated:
		return
	# Cantrips → stat ranks (1:1 by index).
	MetaShop._stat_ranks["vitality"] = int(_cantrips.get("max_hp", 0))
	MetaShop._stat_ranks["power"] = int(_cantrips.get("sword_damage", 0))
	MetaShop._stat_ranks["cast_speed"] = int(_cantrips.get("dash_cooldown", 0))
	# Hub features → mechanic-branch purchases (in fixed order).
	var hub_unlock_order: Array = [
		"wand_choice",
		"second_modifier_slot",
		"pyre_expansion_1",
		"replenish_on_descent",
	]
	for i in range(_hub_features_unlocked):
		if i < hub_unlock_order.size():
			MetaShop._structural_owned[hub_unlock_order[i]] = true
	# Pyre fills → minor souls (1:1).
	var fill_total: int = 0
	for color in SoulEconomy.COLORS:
		fill_total += SoulEconomy.pyre_fill(color)
	if fill_total > 0:
		MetaShop.credit_minor_souls(fill_total)
		# Reset fills so visual pyres start fresh against new accumulation.
		for color in SoulEconomy.COLORS:
			SoulEconomy.set_pyre_fill(color, 0)
	_migrated = true
