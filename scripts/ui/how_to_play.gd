extends CanvasLayer

signal closed

@onready var _back_btn: Button = $Backdrop/Center/Panel/VBox/BackRow/BackBtn

func _ready() -> void:
	visible = false
	_back_btn.pressed.connect(_on_back)
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func show_overlay() -> void:
	visible = true

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back()
		get_viewport().set_input_as_handled()

func _on_back() -> void:
	visible = false
	closed.emit()
