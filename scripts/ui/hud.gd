extends CanvasLayer

@onready var _hp_label: Label = $Margin/VBox/HP
@onready var _souls_label: Label = $Margin/VBox/Souls

var _player: Node = null

func _ready() -> void:
	set_process(true)
	_bind_to_player()

func _bind_to_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		if not _player.hp_changed.is_connected(_on_hp_changed):
			_player.hp_changed.connect(_on_hp_changed)
		_on_hp_changed(_player.hp)

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind_to_player()
	var red_minor: int = SoulEconomy.carry_count("red", "minor")
	_souls_label.text = "Souls (red): %d" % red_minor

func _on_hp_changed(new_hp: int) -> void:
	_hp_label.text = "HP: %d / 100" % new_hp
