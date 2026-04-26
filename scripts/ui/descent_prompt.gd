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
	# Detect boss trigger (suppressed once boss is already defeated)
	var boss_path: bool = (not BossFlow.has_won()) and (_will_fill_all_primary_pyres() or _can_retry_boss())
	if boss_path:
		if _will_fill_all_primary_pyres():
			lines.append("")
			lines.append("⚠ BOSS TRIGGER — this deposit fills the final primary pyre.")
			lines.append("Skills will be RETAINED for the boss fight.")
		else:
			lines.append("")
			lines.append("⚠ BOSS RETRY — consumes 1 elder soul to re-trigger boss.")
			lines.append("Skills will be RETAINED for the boss fight.")
	else:
		lines.append("")
		lines.append("All current skills will be lost.")
	_summary_label.text = "\n".join(lines)
	if boss_path:
		_confirm_button.text = "Descend & Fight"
	else:
		_confirm_button.text = "Descend & deposit"
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _on_confirm() -> void:
	hide_prompt()
	# After victory, never re-trigger the boss; always run the normal extraction
	# path (deposit + skill strip).
	if BossFlow.has_won():
		confirmed.emit()
		return
	if _will_fill_all_primary_pyres() or _can_retry_boss():
		_descend_and_fight()
	else:
		confirmed.emit()

func _can_retry_boss() -> bool:
	var all_lit: bool = true
	for c in SoulEconomy.COLORS:
		if SoulEconomy.pyre_fill(c) < SoulEconomy.PYRE_CAP:
			all_lit = false
			break
	if not all_lit:
		return false
	if BossFlow.has_won():
		return false
	var has_elder: bool = false
	for c in SoulEconomy.COLORS:
		if SoulEconomy.carry_count(c, "elder") > 0:
			has_elder = true
			break
	return has_elder

func _descend_and_fight() -> void:
	# Retry path: consume 1 elder soul if pyres are already at 100%
	if _can_retry_boss():
		for c in SoulEconomy.COLORS:
			if SoulEconomy.carry_count(c, "elder") > 0:
				SoulEconomy._carry[c]["elder"] -= 1
				break
	# Snapshot the FULL SkillSystem state so all unlocked skills (with modifiers
	# and locks) survive the scene swaps to main_hall and courtyard. Player's
	# _ready restores from BossFlow.retained_skills.
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p: Node = players[0]
		if p.has_node("SkillSystem"):
			var ss: SkillSystem = p.get_node("SkillSystem") as SkillSystem
			if ss != null:
				BossFlow.set_retained_skills(ss.to_dict())
	# Deposit any remaining souls (fills the 6th on first trigger)
	SoulEconomy.deposit_to_pyres()
	Escalation.reset()
	BossFlow.trigger_boss()
	GameState.transition_to(GameState.Location.MAIN_HALL)

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
