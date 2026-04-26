extends Node3D

@onready var _humanoid_mesh: MeshInstance3D = $HumanoidMesh
@onready var _dragon_mesh: MeshInstance3D = $DragonMesh

func _ready() -> void:
	visible = false
	_dragon_mesh.visible = false
	BossFlow.state_changed.connect(_on_boss_state_changed)

func _on_boss_state_changed(s: int) -> void:
	if s == BossFlow.State.PENDING:
		appear_humanoid()

func appear_humanoid() -> void:
	visible = true
	_humanoid_mesh.visible = true
	_dragon_mesh.visible = false

func transform_to_dragon() -> void:
	_humanoid_mesh.visible = false
	_dragon_mesh.visible = true

func dismiss() -> void:
	visible = false
