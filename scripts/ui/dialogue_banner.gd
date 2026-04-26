extends CanvasLayer

@onready var _label: Label = $Margin/Panel/Label

const LINES: Dictionary = {
	"death_normal": [
		"Get up, fool. The dragons aren't going to slay themselves.",
		"You die so well, little corpse. Try harder.",
		"What a waste of bone. Again.",
		"Did you forget what I made you for?",
		"Crawl back to the pyres. The dragons grow restless.",
		"Pathetic. I expected more from you, even now.",
		"Was that meant to be effort? I am embarrassed for you.",
		"Death again. As if you have nothing better to do.",
		"How disappointing. And yet, somehow, predictable.",
		"Stand. The work isn't done because YOU are tired.",
		"You die so often I begin to forget which one you are.",
		"Try, this time, to last more than a moment.",
	],
	"death_boss": [
		"Did you really believe this would be enough?",
		"You knew what I was. You came anyway.",
		"Your bones will burn alongside the rest.",
		"Crawl back, little corpse. Try harder this time.",
		"You came so far only to die at my feet. Touching.",
		"All those flames you stole, and still — not enough.",
		"You should have stayed upstairs, little corpse.",
		"I made you. Do you really think I cannot unmake you?",
	],
	"flame_drain": [
		"At last. The flames are mine.",
		"You did all the hard work for me, little corpse.",
		"I will wear these flames as my crown.",
	],
	"victory": [
		"Impossible…",
	],
	"phase_2_taunt": [
		"You hurt me? Cute. Now I am paying attention.",
		"Ah. So the toy has teeth after all.",
		"Enough play. Bleed for me properly.",
		"Did that flicker of strength surprise you? It surprised me.",
		"Very well. No more games, little corpse.",
	],
	"phase_3_taunt": [
		"You will not survive what comes next.",
		"You should be dead. Why are you not dead?",
		"This is what you wanted? This is your reward.",
		"Burn out, then. Like all the others before you.",
		"Last chance to kneel. Refuse, and I will tear what's left.",
	],
	"boss_idle": [
		"Run faster, little corpse. I have appointments.",
		"You swing like a child with a stick.",
		"Is this all you brought me? After everything?",
		"I made you better than this. Behave like it.",
		"Slower. You are getting slower. I can see it.",
		"You think hiding will help? Adorable.",
		"Every breath you take here is a kindness from me.",
		"Closer, little corpse. Let me see your face when you fail.",
		"My patience is a flame. It is going out.",
		"Strike me, then. Or do you need a moment?",
		"Disappointing. As always. As ever.",
		"You move as though I might tire. I will not.",
		"Such effort. Such waste.",
		"Yes — keep trying. I find it amusing.",
		"There is still time to lie down quietly.",
	],
}

@export var line_duration: float = 4.0

var _timer: float = 0.0

func _ready() -> void:
	visible = false
	set_process(true)
	# Cross-scene line catch-up: death_handler stashes a category on BossFlow
	# before scene swap (which destroys the source-scene banner). Show it now.
	var pending: String = BossFlow.consume_pending_banner_line()
	if pending != "":
		show_line(pending)

func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false

func show_line(category: String) -> void:
	var pool: Array = LINES.get(category, [])
	if pool.is_empty():
		return
	var line: String = pool[randi() % pool.size()]
	_label.text = line
	visible = true
	_timer = line_duration

func show_specific(line: String, duration: float = 4.0) -> void:
	_label.text = line
	visible = true
	_timer = duration
