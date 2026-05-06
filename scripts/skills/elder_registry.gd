extends Node
# Autoload — registry of all ElderModifier definitions, indexed by id.
# Loaded once at boot. The ElderDraft scene queries this via draft_for_color.

const ElderModifierScript = preload("res://scripts/skills/elder_modifier.gd")

var _modifiers: Dictionary = {}  # modifier_id -> ElderModifier
var _by_color: Dictionary = {}    # color -> Array[ElderModifier]

func _ready() -> void:
	_register_all()

func _register_all() -> void:
	# First batch (Phase 2 of plan): 2 modifiers per color = 12 total.
	# Follow-up plan adds the remaining 36 to reach the spec's 48.
	# Each modifier is registered with hooks wired to its behavior; behavior
	# scripts live alongside this file (e.g., elder_mod_red_ignite.gd).
	_register(ElderModRedIgniteAllHits.new())
	_register(ElderModRedCinderTrail.new())
	_register(ElderModBlueChillAllHits.new())
	_register(ElderModBlueBrittle.new())
	_register(ElderModGreenToxinAllHits.new())
	_register(ElderModGreenSporeBloom.new())
	_register(ElderModPurplePullOnHit.new())
	_register(ElderModPurpleCrushingMass.new())
	_register(ElderModGoldChainOnHit.new())
	_register(ElderModGoldOvercharge.new())
	_register(ElderModWhiteBoneShield.new())
	_register(ElderModWhiteMarrowPierce.new())

func _register(m: ElderModifier) -> void:
	_modifiers[m.modifier_id] = m
	if not _by_color.has(m.color):
		_by_color[m.color] = []
	(_by_color[m.color] as Array).append(m)

func get_modifier(modifier_id: String) -> ElderModifier:
	return _modifiers.get(modifier_id, null)

func pool_for_color(color: String) -> Array:
	return (_by_color.get(color, []) as Array).duplicate()

func draft_for_color(color: String) -> Array:
	# Return up to 3 distinct modifiers from the color's pool.
	var pool: Array = pool_for_color(color)
	pool.shuffle()
	return pool.slice(0, min(3, pool.size()))
