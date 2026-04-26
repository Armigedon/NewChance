extends CanvasLayer

@onready var _summary: Label = $Center/Panel/VBox/Summary
@onready var _btn_max_hp: Button = $Center/Panel/VBox/Buttons/MaxHP
@onready var _btn_sword: Button = $Center/Panel/VBox/Buttons/Sword
@onready var _btn_dash: Button = $Center/Panel/VBox/Buttons/Dash
@onready var _close_btn: Button = $Center/Panel/VBox/Close

const STONE_COST: int = 30

func _ready() -> void:
	visible = false
	_btn_max_hp.pressed.connect(func(): _buy("max_hp"))
	_btn_sword.pressed.connect(func(): _buy("sword_damage"))
	_btn_dash.pressed.connect(func(): _buy("dash_cooldown"))
	_close_btn.pressed.connect(hide_prompt)

func show_prompt() -> void:
	var total_fill: int = 0
	for c in SoulEconomy.COLORS:
		total_fill += SoulEconomy.pyre_fill(c)
	_summary.text = (
		"Spend %d total banked pyre fill (across all colors) per upgrade.\n" % STONE_COST
		+ "Total pyre fill available: %d\n" % total_fill
		+ "(Each level: +20 HP / +3 sword damage / -0.2s dash CD; max 5 levels)"
	)
	_btn_max_hp.text = "Max HP (%d/5)" % MetaProgress.cantrip_level("max_hp")
	_btn_sword.text = "Sword Damage (%d/5)" % MetaProgress.cantrip_level("sword_damage")
	_btn_dash.text = "Dash Cooldown (%d/5)" % MetaProgress.cantrip_level("dash_cooldown")
	_btn_max_hp.disabled = total_fill < STONE_COST or MetaProgress.cantrip_level("max_hp") >= MetaProgress.CANTRIP_MAX_LEVEL
	_btn_sword.disabled = total_fill < STONE_COST or MetaProgress.cantrip_level("sword_damage") >= MetaProgress.CANTRIP_MAX_LEVEL
	_btn_dash.disabled = total_fill < STONE_COST or MetaProgress.cantrip_level("dash_cooldown") >= MetaProgress.CANTRIP_MAX_LEVEL
	visible = true
	get_tree().paused = true

func hide_prompt() -> void:
	visible = false
	get_tree().paused = false

func _buy(key: String) -> void:
	var remaining: int = STONE_COST
	for c in SoulEconomy.COLORS:
		if remaining == 0:
			break
		var fill: int = SoulEconomy.pyre_fill(c)
		if fill <= 0:
			continue
		var take: int = min(fill, remaining)
		SoulEconomy.set_pyre_fill(c, fill - take)
		remaining -= take
	if remaining > 0:
		return
	MetaProgress.buy_cantrip(key)
	show_prompt()
