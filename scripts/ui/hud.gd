extends CanvasLayer

@onready var _hp_label: Label = $Margin/VBox/HP
@onready var _souls_label: Label = $Margin/VBox/Souls
@onready var _damage_flash: ColorRect = $DamageFlash

var _player: Node = null
var _last_red_minor: int = -1

func _ready() -> void:
	_bind_to_player()
	SoulEconomy.carry_changed.connect(_on_carry_changed)
	_refresh_souls()

func _bind_to_player() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		if not _player.hp_changed.is_connected(_on_hp_changed):
			_player.hp_changed.connect(_on_hp_changed)
		_on_hp_changed(_player.hp)

func _process(_delta: float) -> void:
	# Fallback for cross-scene rebind only — no per-frame polling for souls.
	if _player == null or not is_instance_valid(_player):
		_bind_to_player()

func _on_carry_changed(_color: String, _tier: String, _new_count: int) -> void:
	_refresh_souls()

func _refresh_souls() -> void:
	var red_minor: int = SoulEconomy.carry_count("red", "minor")
	if red_minor == _last_red_minor:
		return
	_last_red_minor = red_minor
	_souls_label.text = "Souls (red): %d" % red_minor

func _on_hp_changed(new_hp: int) -> void:
	_hp_label.text = "HP: %d / 100" % new_hp

func play_damage_flash() -> void:
	if _damage_flash == null:
		return
	_damage_flash.color.a = 0.45
	var tw: Tween = create_tween()
	tw.tween_property(_damage_flash, "color:a", 0.0, 0.35)
