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
	var lines: Array[String] = []
	var any_carry: bool = false
	for color in SoulEconomy.COLORS:
		var minor: int = SoulEconomy.carry_count(color, "minor")
		var elder: int = SoulEconomy.carry_count(color, "elder")
		if minor == 0 and elder == 0:
			continue
		any_carry = true
		var fill_delta: int = minor * SoulEconomy.SOUL_VALUES["minor"] + elder * SoulEconomy.SOUL_VALUES["elder"]
		var current_fill: int = SoulEconomy.pyre_fill(color)
		var new_fill: int = min(current_fill + fill_delta, SoulEconomy.PYRE_CAP)
		var name: String = color.capitalize()
		var carry_desc: String = ""
		if minor > 0 and elder > 0:
			carry_desc = "%d minor + %d elder" % [minor, elder]
		elif elder > 0:
			carry_desc = "%d elder" % elder
		else:
			carry_desc = "%d minor" % minor
		lines.append("%s: %s → pyre %d → %d / %d" % [name, carry_desc, current_fill, new_fill, SoulEconomy.PYRE_CAP])
	if not any_carry:
		lines.append("(no souls to deposit)")
	# Detect boss trigger
	if _will_fill_all_primary_pyres():
		lines.append("")
		lines.append("⚠ BOSS TRIGGER — this deposit fills the final primary pyre.")
		lines.append("(Phase 4: skill retention + boss cutscene NOT YET IMPLEMENTED — Phase 5.)")
	lines.append("")
	lines.append("All current skills will be lost.")
	_summary_label.text = "\n".join(lines)
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

func _will_fill_all_primary_pyres() -> bool:
	for color in SoulEconomy.COLORS:
		var minor: int = SoulEconomy.carry_count(color, "minor")
		var elder: int = SoulEconomy.carry_count(color, "elder")
		var fill_delta: int = minor * SoulEconomy.SOUL_VALUES["minor"] + elder * SoulEconomy.SOUL_VALUES["elder"]
		var new_fill: int = min(SoulEconomy.pyre_fill(color) + fill_delta, SoulEconomy.PYRE_CAP)
		if new_fill < SoulEconomy.PYRE_CAP:
			return false
	return true
