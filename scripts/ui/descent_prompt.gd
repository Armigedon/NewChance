extends CanvasLayer

signal confirmed
signal canceled

@onready var _summary_label: Label = $Center/Panel/VBox/Summary
@onready var _confirm_button: Button = $Center/Panel/VBox/Buttons/Confirm
@onready var _cancel_button: Button = $Center/Panel/VBox/Buttons/Cancel

func _ready() -> void:
	visible = false
	_confirm_button.pressed.connect(_on_confirm)
	_cancel_button.pressed.connect(_on_cancel)

func show_prompt() -> void:
	var red_minor: int = SoulEconomy.carry_count("red", "minor")
	var fill_delta: int = red_minor  # 1/1 in Phase 1
	var current_fill: int = SoulEconomy.pyre_fill("red")
	var new_fill: int = min(current_fill + fill_delta, SoulEconomy.PYRE_CAP)
	_summary_label.text = (
		"Deposit %d red minor souls.\n" % red_minor
		+ "Red pyre: %d → %d / %d\n" % [current_fill, new_fill, SoulEconomy.PYRE_CAP]
		+ "All current skills will be lost."
	)
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _on_confirm() -> void:
	hide_prompt()
	confirmed.emit()

func _on_cancel() -> void:
	hide_prompt()
	canceled.emit()

func _process(_delta: float) -> void:
	if visible and Input.is_action_just_pressed("ui_cancel"):
		_on_cancel()
