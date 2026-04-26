extends Area3D

@export var ui_path: NodePath

var _ui: CanvasLayer = null

func _ready() -> void:
	visible = MetaProgress.hub_features_unlocked() >= 2
	MetaProgress.hub_feature_unlocked.connect(_on_unlock)
	body_entered.connect(_on_body_entered)
	if ui_path != NodePath(""):
		_ui = get_node(ui_path)

func _on_unlock(_idx: int) -> void:
	visible = MetaProgress.hub_features_unlocked() >= 2

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if _ui == null:
		return
	_ui.show_prompt()
