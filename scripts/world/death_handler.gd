extends Node

const RUN_END_SCENE: PackedScene = preload("res://scenes/ui/run_end_summary.tscn")

func _ready() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		push_warning("DeathHandler: no player found")
		return
	var player: Node = players[0]
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)

func _on_player_died() -> void:
	var boss_death: bool = (GameState.current_location == GameState.Location.COURTYARD)
	if boss_death:
		BossFlow.player_died_in_boss()
	# Spawn the summary overlay as a child of root so it survives any scene
	# operations the Continue button triggers.
	var summary: CanvasLayer = RUN_END_SCENE.instantiate()
	get_tree().root.add_child(summary)
	summary.show_summary(boss_death)
