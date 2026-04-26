extends Node

# Listens to BossFlow.PENDING transitions, runs the cutscene sequence,
# then opens the courtyard door. Pauses player input during sequence.

@export var necromancer_path: NodePath
@export var dialogue_banner_path: NodePath
@export var courtyard_door_path: NodePath  # body that gets removed/visible toggled

var _necromancer: Node3D = null
var _banner: CanvasLayer = null
var _door: Node3D = null

func _ready() -> void:
	if necromancer_path != NodePath(""):
		_necromancer = get_node_or_null(necromancer_path)
	if dialogue_banner_path != NodePath(""):
		_banner = get_node_or_null(dialogue_banner_path)
	if courtyard_door_path != NodePath(""):
		_door = get_node_or_null(courtyard_door_path)
	BossFlow.state_changed.connect(_on_boss_state_changed)
	# Cross-scene catch-up: if BossFlow already PENDING when this scene loads
	# (e.g., descent_prompt fired trigger_boss before scene swap completed),
	# run the cutscene now since we missed the original signal.
	if BossFlow.state == BossFlow.State.PENDING:
		_run_cutscene()

func _on_boss_state_changed(s: int) -> void:
	if s == BossFlow.State.PENDING:
		_run_cutscene()
	elif s == BossFlow.State.WON:
		_run_victory()

func _run_cutscene() -> void:
	# Belt-and-suspenders: explicitly raise the necromancer here in case the
	# cross-scene catch-up in Necromancer._ready raced the cutscene start.
	if _necromancer != null and _necromancer.has_method("appear_humanoid"):
		_necromancer.appear_humanoid()
	if _banner != null:
		_banner.show_line("flame_drain")
	await get_tree().create_timer(2.5).timeout
	_visually_extinguish_pyres()
	await get_tree().create_timer(1.5).timeout
	if _necromancer != null and _necromancer.has_method("transform_to_dragon"):
		_necromancer.transform_to_dragon()
	await get_tree().create_timer(2.0).timeout
	if _door != null:
		_door.visible = false
		var col: CollisionShape3D = _door.get_node_or_null("CollisionShape3D")
		if col != null:
			col.disabled = true

func _run_victory() -> void:
	var hall: Node = get_tree().root.find_child("MainHall", true, false)
	if hall == null:
		return
	for c in hall.get_children():
		if c.has_node("Flame"):
			var flame: MeshInstance3D = c.get_node("Flame")
			flame.scale.y = 1.6
			var mat: StandardMaterial3D = flame.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 4.5
	if _banner != null:
		_banner.show_line("victory")
	var stair: Node3D = hall.get_node_or_null("BasementStair")
	if stair != null:
		stair.visible = true
	if _necromancer != null and _necromancer.has_method("dismiss"):
		_necromancer.dismiss()

func _visually_extinguish_pyres() -> void:
	var hall: Node = get_tree().root.find_child("MainHall", true, false)
	if hall == null:
		return
	for c in hall.get_children():
		if c.has_node("Flame"):
			var flame: MeshInstance3D = c.get_node("Flame")
			var mat: StandardMaterial3D = flame.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = 0.0
				flame.scale.y = 0.05
