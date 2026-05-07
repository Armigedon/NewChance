extends Area3D

func _ready() -> void:
	visible = MetaProgress.hub_features_unlocked() >= 3
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		print("[Sigil Forge] coming soon — currently unlocked but no content.")
