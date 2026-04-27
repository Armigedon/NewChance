extends CanvasLayer

@onready var _hp_bar: ProgressBar = $HpBox/HpVBox/HpRow/HpBar
@onready var _hp_numeric: Label = $HpBox/HpVBox/HpRow/HpNumeric
@onready var _wisp_red: Control = $SoulsBox/SoulsVBox/SoulsRow/WispRed
@onready var _wisp_blue: Control = $SoulsBox/SoulsVBox/SoulsRow/WispBlue
@onready var _wisp_green: Control = $SoulsBox/SoulsVBox/SoulsRow/WispGreen
@onready var _wisp_purple: Control = $SoulsBox/SoulsVBox/SoulsRow/WispPurple
@onready var _wisp_gold: Control = $SoulsBox/SoulsVBox/SoulsRow/WispGold
@onready var _wisp_white: Control = $SoulsBox/SoulsVBox/SoulsRow/WispWhite
@onready var _wisp_elder: Control = $SoulsBox/SoulsVBox/SoulsRow/WispElder
@onready var _slot1: Label = $SkillBox/SkillVBox/SkillRow/Slot1
@onready var _slot2: Label = $SkillBox/SkillVBox/SkillRow/Slot2
@onready var _slot3: Label = $SkillBox/SkillVBox/SkillRow/Slot3
@onready var _damage_flash: ColorRect = $DamageFlash

var _player: Node = null
var _skill_system: SkillSystem = null
var _flash_tween: Tween = null

const COLOR_TINT_BORDER: Dictionary = {
	"red": Color(0.82, 0.25, 0.19, 1),
	"blue": Color(0.25, 0.56, 0.82, 1),
	"green": Color(0.22, 0.54, 0.22, 1),
	"purple": Color(0.42, 0.22, 0.54, 1),
	"gold": Color(0.82, 0.65, 0.18, 1),
	"white": Color(0.94, 0.94, 0.88, 1),
}

const COLOR_NAME: Dictionary = {
	"red": "FIRE",
	"blue": "ICE",
	"green": "PLAG",
	"purple": "VOID",
	"gold": "BOLT",
	"white": "BONE",
}

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
		if _player.has_node("SkillSystem"):
			_skill_system = _player.get_node("SkillSystem") as SkillSystem
			if not _skill_system.active_skill_changed.is_connected(_on_active_skill_changed):
				_skill_system.active_skill_changed.connect(_on_active_skill_changed)
			_refresh_skill_slots()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind_to_player()

func _on_carry_changed(_color: String, _tier: String, _new_count: int) -> void:
	_refresh_souls()

func _refresh_souls() -> void:
	_wisp_red.set_count(SoulEconomy.carry_count("red", "minor"))
	_wisp_blue.set_count(SoulEconomy.carry_count("blue", "minor"))
	_wisp_green.set_count(SoulEconomy.carry_count("green", "minor"))
	_wisp_purple.set_count(SoulEconomy.carry_count("purple", "minor"))
	_wisp_gold.set_count(SoulEconomy.carry_count("gold", "minor"))
	_wisp_white.set_count(SoulEconomy.carry_count("white", "minor"))
	var total_elder: int = 0
	for c in SoulEconomy.COLORS:
		total_elder += SoulEconomy.carry_count(c, "elder")
	_wisp_elder.set_count(total_elder)

func _on_hp_changed(new_hp: int) -> void:
	_hp_bar.value = float(new_hp)
	if _player != null:
		_hp_bar.max_value = float(_player.max_hp)
		_hp_numeric.text = "%d/%d" % [new_hp, _player.max_hp]
	else:
		_hp_numeric.text = "%d" % new_hp

func _on_active_skill_changed(_index: int) -> void:
	_refresh_skill_slots()

func _refresh_skill_slots() -> void:
	var slots: Array = [_slot1, _slot2, _slot3]
	var active_idx: int = _skill_system.active_index() if _skill_system != null else -1
	for i in range(3):
		var slot: Label = slots[i]
		var skill: Skill = _skill_system.skill_at(i) if _skill_system != null else null
		var is_active: bool = (i == active_idx)
		# Resize: active slot is 36×36, others stay at 32×32.
		slot.custom_minimum_size = Vector2(36, 36) if is_active else Vector2(32, 32)
		if skill == null:
			slot.text = str(i + 1)
			slot.modulate = Color(0.35, 0.29, 0.22, 1)
			continue
		slot.text = COLOR_NAME.get(skill.base_color, "?")
		var tint: Color = COLOR_TINT_BORDER.get(skill.base_color, Color.WHITE)
		slot.modulate = tint if is_active else Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 1)

func play_damage_flash() -> void:
	if _damage_flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_damage_flash.color.a = 0.45
	_flash_tween = create_tween()
	_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.35)
