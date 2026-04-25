extends Node

func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		push_warning("DeathHandler: no player found")
		return
	var player: Node = players[0]
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

func _on_player_died() -> void:
	SoulEconomy.clear_carry()
	GameState.transition_to(GameState.Location.MAIN_HALL)
