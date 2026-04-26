extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if BossFlow.state == BossFlow.State.PENDING:
		GameState.transition_to(GameState.Location.COURTYARD)
