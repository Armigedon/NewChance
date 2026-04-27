extends CanvasLayer

@onready var _title: Label = $Backdrop/Center/Panel/VBox/Title
@onready var _quote: Label = $Backdrop/Center/Panel/VBox/Quote
@onready var _stat_time: Label = $Backdrop/Center/Panel/VBox/Stats/TimeValue
@onready var _stat_kills: Label = $Backdrop/Center/Panel/VBox/Stats/KillsValue
@onready var _stat_killer: Label = $Backdrop/Center/Panel/VBox/Stats/KillerValue
@onready var _souls_lost_box: VBoxContainer = $Backdrop/Center/Panel/VBox/SoulsLost
@onready var _souls_row: HBoxContainer = $Backdrop/Center/Panel/VBox/SoulsLost/Row
@onready var _btn_continue: Button = $Backdrop/Center/Panel/VBox/Buttons/Continue
@onready var _btn_quit: Button = $Backdrop/Center/Panel/VBox/Buttons/QuitToMenu

const SOUL_WISP_SCENE: PackedScene = preload("res://scenes/ui/soul_wisp.tscn")
const COLOR_TINT: Dictionary = {
	"red": Color(0.82, 0.25, 0.19, 1),
	"blue": Color(0.25, 0.56, 0.82, 1),
	"green": Color(0.22, 0.54, 0.22, 1),
	"purple": Color(0.42, 0.22, 0.54, 1),
	"gold": Color(0.82, 0.65, 0.18, 1),
	"white": Color(0.94, 0.94, 0.88, 1),
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_btn_continue.pressed.connect(_on_continue)
	_btn_quit.pressed.connect(_on_quit_to_menu)

func show_summary(boss_death: bool) -> void:
	if boss_death:
		_title.text = "— Defeated —"
		_quote.text = _pick_line("death_boss")
	else:
		_title.text = "— You Died —"
		_quote.text = _pick_line("death_normal")
	_stat_time.text = _format_time(RunStats.elapsed_seconds())
	_stat_kills.text = str(RunStats.enemies_slain)
	if RunStats.last_damage_source_name == "":
		_stat_killer.text = "—"
	else:
		_stat_killer.text = RunStats.last_damage_source_name
	_populate_souls_lost()
	visible = true
	get_tree().paused = true

func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [total / 60, total % 60]

func _pick_line(category: String) -> String:
	# Single source of truth for taunt copy: DialogueBanner.LINES.
	var banner: CanvasLayer = get_tree().root.find_child("DialogueBanner", true, false) as CanvasLayer
	if banner == null:
		return ""
	var pool = banner.LINES.get(category, [])
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

func _populate_souls_lost() -> void:
	for child in _souls_row.get_children():
		child.queue_free()
	var any_carry: bool = false
	for c in SoulEconomy.COLORS:
		if SoulEconomy.carry_count(c, "minor") > 0 or SoulEconomy.carry_count(c, "elder") > 0:
			any_carry = true
			break
	if not any_carry:
		_souls_lost_box.visible = false
		return
	_souls_lost_box.visible = true
	for c in SoulEconomy.COLORS:
		var wisp: Control = SOUL_WISP_SCENE.instantiate()
		_souls_row.add_child(wisp)
		wisp.color = COLOR_TINT.get(c, Color.WHITE)
		wisp.set_count(SoulEconomy.carry_count(c, "minor"))
		wisp.set_process(false)
	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(1, 36)
	divider.color = Color(0.29, 0.23, 0.16, 1)
	_souls_row.add_child(divider)
	var elder_total: int = 0
	for c in SoulEconomy.COLORS:
		elder_total += SoulEconomy.carry_count(c, "elder")
	var elder_wisp: Control = SOUL_WISP_SCENE.instantiate()
	_souls_row.add_child(elder_wisp)
	elder_wisp.color = Color(0.96, 0.85, 0.44, 1)
	elder_wisp.is_elder = true
	elder_wisp.set_count(elder_total)
	elder_wisp.set_process(false)

func _on_continue() -> void:
	visible = false
	get_tree().paused = false
	GameState.end_run(GameState.Outcome.DIED)

func _on_quit_to_menu() -> void:
	visible = false
	get_tree().paused = false
	var save_data: Dictionary = {
		"meta": MetaProgress.to_dict(),
		"pyres": _pyre_fills_dict(),
	}
	SaveSystem.save(save_data)
	get_tree().change_scene_to_file("res://scenes/world/start_screen.tscn")

func _pyre_fills_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in SoulEconomy.COLORS:
		d[c] = SoulEconomy.pyre_fill(c)
	return d
