extends CanvasLayer

@onready var _label: Label = $Margin/Panel/Label

const LINES: Dictionary = {
	"death_normal": [
		"Get up, fool. The dragons aren't going to slay themselves.",
		"You die so well, little corpse. Try harder.",
		"What a waste of bone. Again.",
		"Did you forget what I made you for?",
		"Crawl back to the pyres. The dragons grow restless.",
	],
	"death_boss": [
		"Did you really believe this would be enough?",
		"You knew what I was. You came anyway.",
		"Your bones will burn alongside the rest.",
		"Crawl back, little corpse. Try harder this time.",
	],
	"flame_drain": [
		"At last. The flames are mine.",
		"You did all the hard work for me, little corpse.",
		"I will wear these flames as my crown.",
	],
	"victory": [
		"Impossible…",
	],
}

@export var line_duration: float = 4.0

var _timer: float = 0.0

func _ready() -> void:
	visible = false
	set_process(true)

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
