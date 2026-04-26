extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if BossFlow.is_active():
		var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false)
		if banner != null:
			banner.show_specific("The flames have already chosen.", 3.0)
		return
	GameState.transition_to(GameState.Location.UPSTAIRS)
