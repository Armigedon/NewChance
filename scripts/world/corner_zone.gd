extends Area3D

@export var zone_color: String = ""

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		Escalation.set_player_in_corner(zone_color)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		# Only clear if the player was in THIS zone (avoids clobber on zone-to-zone movement)
		if Escalation.current_corner() == zone_color:
			Escalation.set_player_in_corner("")
