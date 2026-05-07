extends Node

# MetaProgress is now mostly a save-format shim. Phase 9/10 redesigned the
# active state into MetaShop (stat ranks + structural unlocks). The fields
# below are read by migrate_to_meta_shop() for legacy save migration and
# otherwise unused. New code should reach into MetaShop, not this autoload.

const HUB_FEATURE_MAX: int = 4

var _cantrips: Dictionary = {}
var _hub_features_unlocked: int = 0
var _migrated: bool = false

func _ready() -> void:
	_init_defaults()

func reset_meta() -> void:
	_init_defaults()

func _init_defaults() -> void:
	_cantrips = {"max_hp": 0, "sword_damage": 0, "dash_cooldown": 0}
	_hub_features_unlocked = 0
	_migrated = false

func hub_features_unlocked() -> int:
	return _hub_features_unlocked

func to_dict() -> Dictionary:
	return {
		"cantrips": _cantrips.duplicate(),
		"hub_features_unlocked": _hub_features_unlocked,
	}

func from_dict(d: Dictionary) -> void:
	_init_defaults()
	if d.has("cantrips"):
		for k in ["max_hp", "sword_damage", "dash_cooldown"]:
			_cantrips[k] = int(d["cantrips"].get(k, 0))
	_hub_features_unlocked = int(d.get("hub_features_unlocked", 0))

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
	for color in Palette.ALL:
		fill_total += SoulEconomy.pyre_fill(color)
	if fill_total > 0:
		MetaShop.credit_minor_souls(fill_total)
		for color in Palette.ALL:
			SoulEconomy.set_pyre_fill(color, 0)
	_migrated = true
