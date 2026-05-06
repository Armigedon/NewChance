extends Node
# Autoload — maps color -> ElderAbility instance. Loaded once at boot.
# Welp queries this on _ready when tier == "elder" to find the appropriate
# color-themed ability.

const ElderAbilityScript = preload("res://scripts/entities/elder_abilities/elder_ability.gd")

var _by_color: Dictionary = {}  # color -> ElderAbility

func _ready() -> void:
	_register_all()

func _register_all() -> void:
	# Subclasses are registered in Task B2; for now, the registry is empty.
	# Welp.gd queries get_for_color(); empty result means "no ability" and the
	# elder behaves as a stat-buffed welp (the pre-Phase-B behavior).
	pass

func _register(ability: ElderAbility) -> void:
	_by_color[ability.color] = ability

func get_for_color(color: String) -> ElderAbility:
	return _by_color.get(color, null)
