extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if BossFlow.state == BossFlow.State.PENDING:
		# Flip PENDING → ACTIVE here (don't depend on the courtyard's EntryGate
		# being crossed, since the player may walk straight at the boss).
		BossFlow.enter_arena()
		GameState.transition_to(GameState.Location.COURTYARD)
