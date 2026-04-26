extends Area3D

# Detects player entry → calls BossFlow.enter_arena() and seals the gate.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	BossFlow.enter_arena()
	monitoring = false
	var gate_mesh: MeshInstance3D = get_node_or_null("GateMesh")
	if gate_mesh != null:
		gate_mesh.visible = true
	var gate_collider_root: StaticBody3D = get_node_or_null("GateCollider")
	if gate_collider_root != null:
		var col: CollisionShape3D = gate_collider_root.get_node_or_null("GateColliderShape")
		if col != null:
			col.disabled = false
