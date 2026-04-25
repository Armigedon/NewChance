extends CanvasLayer

signal replace_chosen(index: int)
signal declined

@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _btn_replace_0: Button = $Center/Panel/VBox/Buttons/Replace0
@onready var _btn_replace_1: Button = $Center/Panel/VBox/Buttons/Replace1
@onready var _btn_replace_2: Button = $Center/Panel/VBox/Buttons/Replace2
@onready var _btn_decline: Button = $Center/Panel/VBox/Buttons/Decline

var _incoming_color: String = ""

func _ready() -> void:
	visible = false
	_btn_replace_0.pressed.connect(func(): _on_replace(0))
	_btn_replace_1.pressed.connect(func(): _on_replace(1))
	_btn_replace_2.pressed.connect(func(): _on_replace(2))
	_btn_decline.pressed.connect(_on_decline)

func show_prompt(skill_system: SkillSystem, incoming_color: String) -> void:
	_incoming_color = incoming_color
	_summary.text = (
		"You picked up an Elder %s soul, but you're at the skill cap.\n" % incoming_color
		+ "Replace which skill, or decline (converts to 3 minor souls)?"
	)
	for i in range(3):
		var skill: Skill = skill_system.skill_at(i)
		var btn: Button = [_btn_replace_0, _btn_replace_1, _btn_replace_2][i]
		if skill != null:
			btn.text = "Replace [%d] %s" % [i + 1, skill.base_color.capitalize()]
			btn.disabled = false
		else:
			btn.disabled = true
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _on_replace(index: int) -> void:
	hide_prompt()
	replace_chosen.emit(index)

func _on_decline() -> void:
	hide_prompt()
	declined.emit()
