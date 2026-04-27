extends Control

const HOW_TO_PLAY_SCENE: PackedScene = preload("res://scenes/ui/how_to_play.tscn")

@onready var _btn_new: Button = $Center/HBox/Buttons/NewGame
@onready var _btn_continue: Button = $Center/HBox/Buttons/Continue
@onready var _btn_help: Button = $Center/HBox/Buttons/HowToPlay
@onready var _btn_quit: Button = $Center/HBox/Buttons/Quit
@onready var _confirm: ColorRect = $ConfirmOverwrite

func _ready() -> void:
	_btn_new.pressed.connect(_on_new_pressed)
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_help.pressed.connect(_on_help_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)
	$ConfirmOverwrite/Center/Panel/VBox/Buttons/Yes.pressed.connect(_on_confirm_yes)
	$ConfirmOverwrite/Center/Panel/VBox/Buttons/No.pressed.connect(_on_confirm_no)
	_btn_continue.disabled = not _save_exists()
	_confirm.visible = false

func _save_exists() -> bool:
	return FileAccess.file_exists("user://save.tres")

func _on_new_pressed() -> void:
	if _save_exists():
		_confirm.visible = true
	else:
		_start_new_game()

func _on_confirm_yes() -> void:
	_confirm.visible = false
	if FileAccess.file_exists("user://save.tres"):
		DirAccess.remove_absolute("user://save.tres")
	MetaProgress._init_defaults()
	SoulEconomy.reset_meta()
	BossFlow.reset()
	BossFlow.clear_retained_skills()
	_start_new_game()

func _on_confirm_no() -> void:
	_confirm.visible = false

func _start_new_game() -> void:
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_continue_pressed() -> void:
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_help_pressed() -> void:
	var help: CanvasLayer = HOW_TO_PLAY_SCENE.instantiate()
	add_child(help)
	help.show_overlay()
	help.closed.connect(help.queue_free)

func _on_quit_pressed() -> void:
	get_tree().quit()
