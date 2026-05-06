extends Area3D

@export var color: String = "red"
@export var tier: String = "minor"

const ElderDraftScene: PackedScene = preload("res://scenes/ui/elder_draft.tscn")

const TINTS: Dictionary = {
	"red": Color(1, 0.4, 0.2, 1),
	"blue": Color(0.4, 0.7, 1, 1),
	"green": Color(0.4, 0.9, 0.4, 1),
	"purple": Color(0.6, 0.3, 0.85, 1),
	"gold": Color(1, 0.9, 0.4, 1),
	"white": Color(0.95, 0.95, 0.9, 1),
}

# Vacuum: pickups slide toward the player when within VACUUM_RANGE,
# accelerating with proximity. Reduces time spent standing still in
# welp territory waiting to walk onto a soul.
const VACUUM_RANGE: float = 4.0
const VACUUM_BASE_SPEED: float = 6.0

var _player: Node = null

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	add_to_group("soul_pickup")
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

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		var players: Array = get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		_player = players[0]
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	var distance: float = to_player.length()
	if distance >= VACUUM_RANGE or distance < 0.001:
		return
	# Speed ramps up as the pickup gets closer (1x at edge, 3x at zero).
	var closeness: float = 1.0 - distance / VACUUM_RANGE
	var speed: float = VACUUM_BASE_SPEED * (1.0 + closeness * 2.0)
	global_position += to_player.normalized() * speed * delta

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# Phase 9 redesign: pickups bank to SoulEconomy carry only. The direct
	# SkillSystem mutation is gone — minors are pure meta currency, elders
	# trigger an ElderDraft flow.
	SoulEconomy.add_to_carry(color, tier, 1)
	# Phase 9: elder pickups also trigger an in-run modifier draft.
	if tier == "elder" and body.has_node("SkillSystem"):
		var draft: CanvasLayer = ElderDraftScene.instantiate()
		# Add at root so the modal layer is above all gameplay UI.
		body.get_tree().root.add_child(draft)
		draft.show_draft(color, body.get_node("SkillSystem"))
	queue_free()
