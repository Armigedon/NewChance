extends Area3D

@export var color: String = "red"
@export var tier: String = "minor"

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		SoulEconomy.add_to_carry(color, tier, 1)
		queue_free()
