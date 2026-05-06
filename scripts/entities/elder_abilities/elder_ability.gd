extends RefCounted
class_name ElderAbility

# Base class for color-themed elder enemy abilities. Subclasses fill in any
# of the three optional Callable hooks. Each instance is one ability for
# one color; the registry maps color -> ElderAbility instance.
#
# Hooks (all optional):
# on_alive_tick(elder: Node, delta: float) -> void
#   Called from welp._physics_process each frame while elder is alive.
# on_attack(elder: Node, target: Node) -> void
#   Called from welp._attack_player after the player hit lands.
# on_death(elder: Node) -> void
#   Called from welp.take_damage just before queue_free.

var color: String

var on_alive_tick: Callable = Callable()
var on_attack: Callable = Callable()
var on_death: Callable = Callable()

func _init(p_color: String) -> void:
	color = p_color
