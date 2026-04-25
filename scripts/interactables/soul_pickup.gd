extends Area3D

@export var color: String = "red"
@export var tier: String = "minor"

const TINTS: Dictionary = {
	"red": Color(1, 0.4, 0.2, 1),
	"blue": Color(0.4, 0.7, 1, 1),
}

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	var mesh: MeshInstance3D = $Mesh if has_node("Mesh") else null
	if mesh != null:
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if mat != null:
			# Duplicate so per-instance tint doesn't bleed to other pickups sharing the resource.
			mat = mat.duplicate() as StandardMaterial3D
			mesh.material_override = mat
			var tint: Color = TINTS.get(color, TINTS["red"])
			mat.albedo_color = tint
			mat.emission = tint

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	SoulEconomy.add_to_carry(color, tier, 1)
	# Wire into player's SkillSystem so pickups actually unlock/modify skills.
	if body.has_node("SkillSystem"):
		var ss: SkillSystem = body.get_node("SkillSystem")
		if tier == "elder":
			ss.add_elder(color)
		else:
			ss.add_minor(color)
	queue_free()
