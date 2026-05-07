extends RefCounted
class_name ElderModifier

# Definition of one elder modifier. The registry holds one instance per
# modifier_id; live skill state lives on Skill.elder_modifier_stacks.
#
# Hooks: subclasses or instances assign Callables to these to wire into
# damage_pipeline.gd at the appropriate event. All hooks are optional —
# unset (Callable()) means no behavior at that event.
#
# stack_count is passed to every hook so effect strength can scale with
# repeat draws (per spec: repeats compound).

var modifier_id: String
var color: String
var name: String
var description: String

# Hook signatures (all optional):
# on_hit(target: Node, damage: int, source_pos: Vector3, stack_count: int) -> void
# on_kill(target: Node, source_pos: Vector3, stack_count: int, caster: Node) -> void
# on_cast(caster: Node, modifier_stack: Array, base_color: String, stack_count: int) -> void
# on_player_damaged(player: Node, amount: int, stack_count: int) -> void
# damage_multiplier(target: Node, base_damage: int, stack_count: int) -> float
#   (returns the multiplier; 1.0 = no change)
var on_hit: Callable = Callable()
var on_kill: Callable = Callable()
var on_cast: Callable = Callable()
var on_player_damaged: Callable = Callable()
var damage_multiplier: Callable = Callable()

func _init(p_id: String, p_color: String, p_name: String, p_description: String) -> void:
	modifier_id = p_id
	color = p_color
	name = p_name
	description = p_description
