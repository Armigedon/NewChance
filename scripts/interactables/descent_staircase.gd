extends Area3D

@export var prompt_path: NodePath  # Path to a DescentPrompt instance in the scene tree

var _prompt: CanvasLayer = null
var _player_in_zone: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if prompt_path != NodePath(""):
		_prompt = get_node(prompt_path)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_zone = true
	if _prompt == null:
		return
	_prompt.show_prompt()
	if not _prompt.confirmed.is_connected(_on_confirmed):
		_prompt.confirmed.connect(_on_confirmed)
	if not _prompt.canceled.is_connected(_on_canceled):
		_prompt.canceled.connect(_on_canceled)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_zone = false

func _on_confirmed() -> void:
	SoulEconomy.deposit_to_pyres()
	GameState.transition_to(GameState.Location.MAIN_HALL)

func _on_canceled() -> void:
	pass  # player stays upstairs; nothing to do
