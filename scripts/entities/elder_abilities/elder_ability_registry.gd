extends Node
# Autoload — maps color -> ElderAbility instance. Loaded once at boot.
# Welp queries this on _ready when tier == "elder" to find the appropriate
# color-themed ability.

const ElderAbilityScript = preload("res://scripts/entities/elder_abilities/elder_ability.gd")

var _by_color: Dictionary = {}  # color -> ElderAbility

func _ready() -> void:
	_register_all()

func _register_all() -> void:
	_register(ElderAbilityRedFirePool.new())
	_register(ElderAbilityBlueChillAura.new())
	_register(ElderAbilityGreenPoisonTrail.new())
	_register(ElderAbilityPurplePullOnHit.new())
	_register(ElderAbilityGoldChainOnHit.new())
	_register(ElderAbilityWhiteBoneWall.new())

func _register(ability: ElderAbility) -> void:
	_by_color[ability.color] = ability

func get_for_color(color: String) -> ElderAbility:
	return _by_color.get(color, null)
