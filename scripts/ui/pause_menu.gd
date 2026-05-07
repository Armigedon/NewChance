extends CanvasLayer

const HOW_TO_PLAY_SCENE: PackedScene = preload("res://scenes/ui/how_to_play.tscn")

@onready var _backdrop: ColorRect = $Backdrop
@onready var _btn_resume: Button = $Backdrop/Center/Panel/VBox/Resume
@onready var _btn_help: Button = $Backdrop/Center/Panel/VBox/HowToPlay
@onready var _btn_restart: Button = $Backdrop/Center/Panel/VBox/RestartRun
@onready var _btn_quit: Button = $Backdrop/Center/Panel/VBox/QuitToMenu
@onready var _confirm: ColorRect = $ConfirmRestart

var _help_overlay: CanvasLayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_btn_resume.pressed.connect(_close)
	_btn_help.pressed.connect(_on_help)
	_btn_restart.pressed.connect(_on_restart)
	_btn_quit.pressed.connect(_on_quit_to_menu)
	$ConfirmRestart/Center/Panel/VBox/Buttons/Yes.pressed.connect(_on_confirm_restart_yes)
	$ConfirmRestart/Center/Panel/VBox/Buttons/No.pressed.connect(_on_confirm_restart_no)
	_confirm.visible = false

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if not visible and get_tree().paused:
		return
	if _help_overlay != null and is_instance_valid(_help_overlay) and _help_overlay.visible:
		return
	if _confirm.visible:
		_confirm.visible = false
		get_viewport().set_input_as_handled()
		return
	if visible:
		_close()
	else:
		_open()
	get_viewport().set_input_as_handled()

func _open() -> void:
	if get_tree().current_scene != null and get_tree().current_scene.name == "StartScreen":
		return
	visible = true
	get_tree().paused = true

func _close() -> void:
	visible = false
	get_tree().paused = false

func _on_help() -> void:
	if _help_overlay != null and is_instance_valid(_help_overlay):
		return
	_help_overlay = HOW_TO_PLAY_SCENE.instantiate()
	add_child(_help_overlay)
	_help_overlay.show_overlay()
	_help_overlay.closed.connect(_on_help_closed)

func _on_help_closed() -> void:
	if _help_overlay != null and is_instance_valid(_help_overlay):
		_help_overlay.queue_free()
	_help_overlay = null

func _on_restart() -> void:
	_confirm.visible = true

func _on_confirm_restart_yes() -> void:
	_confirm.visible = false
	SoulEconomy.clear_carry()
	get_tree().paused = false
	visible = false
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_confirm_restart_no() -> void:
	_confirm.visible = false

func _on_quit_to_menu() -> void:
	var save_data: Dictionary = {
		"meta": MetaProgress.to_dict(),
		"pyres": _pyre_fills_dict(),
	}
	SaveSystem.save(save_data)
	get_tree().paused = false
	visible = false
	get_tree().change_scene_to_file("res://scenes/world/start_screen.tscn")

func _pyre_fills_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in Palette.ALL:
		d[c] = SoulEconomy.pyre_fill(c)
	return d
