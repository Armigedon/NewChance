extends CanvasLayer

@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _color_buttons: Array = [
	$Center/Panel/VBox/Buttons/Red,
	$Center/Panel/VBox/Buttons/Blue,
	$Center/Panel/VBox/Buttons/Green,
	$Center/Panel/VBox/Buttons/Purple,
	$Center/Panel/VBox/Buttons/Gold,
	$Center/Panel/VBox/Buttons/White,
]
@onready var _close_btn: Button = $Center/Panel/VBox/Close

const ALTAR_COST_TEST: int = 3
const ALTAR_COST_SHIP: int = 10
static var ALTAR_COST: int = ALTAR_COST_TEST if Debug.FAST_TEST else ALTAR_COST_SHIP

func _ready() -> void:
	visible = false
	for i in range(_color_buttons.size()):
		var color: String = Palette.ALL[i]
		_color_buttons[i].pressed.connect(func(): _on_pick(color))
	_close_btn.pressed.connect(hide_prompt)

func show_prompt() -> void:
	var queued: String = MetaProgress._start_with_skill
	_summary.text = (
		"Drain %d fill from a pyre to start your next run with that color's skill already unlocked.\n" % ALTAR_COST
		+ "(Currently queued: %s)" % (queued if queued != "" else "none")
	)
	for i in range(_color_buttons.size()):
		var color: String = Palette.ALL[i]
		var fill: int = SoulEconomy.pyre_fill(color)
		var btn: Button = _color_buttons[i]
		btn.text = "%s (pyre: %d)" % [color.capitalize(), fill]
		btn.disabled = fill < ALTAR_COST
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _on_pick(color: String) -> void:
	if SoulEconomy.pyre_fill(color) < ALTAR_COST:
		return
	SoulEconomy.set_pyre_fill(color, SoulEconomy.pyre_fill(color) - ALTAR_COST)
	MetaProgress.set_start_with_skill(color)
	hide_prompt()
