extends CanvasLayer

# Modal scene shown on elder pickup. Pauses physics, displays up to 3 cards
# from the elder's color pool, applies the chosen modifier to the active wand,
# resumes.
#
# Process mode: ALWAYS (so the scene can run while tree is paused).

signal picked(modifier_id: String)

var _draft: Array = []
var _skill_system: Node = null
var _color: String = ""

@onready var _card_container: HBoxContainer = $Center/Panel/VBox/Cards
@onready var _title: Label = $Center/Panel/VBox/Title

const CARD_TEMPLATE: PackedScene = preload("res://scenes/ui/elder_draft_card.tscn")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_draft(color: String, skill_system: Node) -> void:
	_color = color
	_skill_system = skill_system
	_draft = ElderRegistry.draft_for_color(color)
	_render_cards()
	_title.text = "%s Elder — pick a modifier" % color.capitalize()
	visible = true
	get_tree().paused = true

func _render_cards() -> void:
	for c in _card_container.get_children():
		c.queue_free()
	for i in range(_draft.size()):
		var card: Button = CARD_TEMPLATE.instantiate()
		var m: ElderModifier = _draft[i]
		var stack_note: String = ""
		if _skill_system != null and _skill_system.active_skill() != null:
			var existing: int = _skill_system.active_skill().elder_modifier_stack_count(m.modifier_id)
			if existing > 0:
				stack_note = "\n(already on wand: stack will become %d)" % (existing + 1)
		card.text = "%s\n\n%s%s" % [m.name, m.description, stack_note]
		var idx: int = i  # capture by value for callable
		card.pressed.connect(func(): pick_card(idx))
		_card_container.add_child(card)

func pick_card(index: int) -> void:
	if index < 0 or index >= _draft.size():
		return
	if _skill_system == null:
		return
	var m: ElderModifier = _draft[index]
	_skill_system.apply_elder_modifier(m.modifier_id)
	visible = false
	get_tree().paused = false
	picked.emit(m.modifier_id)

func get_visible_card_count() -> int:
	return _draft.size()
