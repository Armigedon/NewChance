extends Node3D

@export var color: String = "red"

var fill_ratio: float = 0.0
var is_fully_lit: bool = false

@onready var _flame_mesh: MeshInstance3D = $Flame if has_node("Flame") else null

func _ready() -> void:
	SoulEconomy.pyre_filled.connect(_on_pyre_filled)
	SoulEconomy.pyre_fill_changed.connect(_on_pyre_fill_changed)
	refresh_visual()

func refresh_visual() -> void:
	var fill: int = SoulEconomy.pyre_fill(color)
	fill_ratio = float(fill) / float(SoulEconomy.PYRE_CAP)
	is_fully_lit = fill >= SoulEconomy.PYRE_CAP
	_apply_visual()

func _on_pyre_filled(filled_color: String) -> void:
	if filled_color == color:
		refresh_visual()

func _on_pyre_fill_changed(changed_color: String, _new_fill: int) -> void:
	if changed_color == color:
		refresh_visual()

func _apply_visual() -> void:
	if _flame_mesh == null:
		return
	_flame_mesh.scale = Vector3(1.0, 0.1 + fill_ratio * 1.5, 1.0)
	var mat: StandardMaterial3D = _flame_mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 0.5 + fill_ratio * 4.0
