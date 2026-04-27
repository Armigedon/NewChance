class_name SoulWisp
extends Control

# Reusable wispy-soul widget. Custom-draws a flame polygon and pulses it
# with a sine wave on _process. Count label is added below in the .tscn.

@export var color: Color = Color(0.8, 0.8, 0.78, 1)
@export var is_elder: bool = false
@export var stagger_seconds: float = 0.0

const FLAME_POINTS: PackedVector2Array = [
	Vector2(11, 2),
	Vector2(5, 8),
	Vector2(8, 16),
	Vector2(3, 20),
	Vector2(7, 26),
	Vector2(11, 28),
	Vector2(15, 26),
	Vector2(19, 20),
	Vector2(14, 16),
	Vector2(17, 8),
]
const FLAME_PIVOT_Y: float = 28.0
const MINOR_PERIOD: float = 1.6
const ELDER_PERIOD: float = 2.0

var count: int = 0
var _t: float = 0.0
var _label: Label = null

func _ready() -> void:
	_t = stagger_seconds
	custom_minimum_size = Vector2(28, 36)
	_label = get_node_or_null("Count") as Label
	_refresh_label()
	set_process(count > 0)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var period: float = ELDER_PERIOD if is_elder else MINOR_PERIOD
	var pulse: float = sin(_t * TAU / period) * 0.5 + 0.5  # 0..1
	var scale_y: float
	var alpha: float
	if is_dimmed():
		scale_y = 1.0
		alpha = 0.4
	else:
		var min_scale: float = 0.92 if is_elder else 0.95
		var max_scale: float = 1.12 if is_elder else 1.08
		var min_alpha: float = 0.9 if is_elder else 0.85
		var max_alpha: float = 1.0
		scale_y = lerp(min_scale, max_scale, pulse)
		alpha = lerp(min_alpha, max_alpha, pulse)
	var pts: PackedVector2Array = PackedVector2Array()
	for p in FLAME_POINTS:
		pts.append(Vector2(p.x, FLAME_PIVOT_Y - (FLAME_PIVOT_Y - p.y) * scale_y))
	var c: Color = color
	c.a *= alpha
	draw_colored_polygon(pts, c)

func set_count(n: int) -> void:
	count = max(0, n)
	# Suspend per-frame work when dimmed; resume when count returns positive.
	set_process(count > 0)
	# Force one final redraw so the dim/un-dim visual updates immediately
	# even after process is disabled.
	queue_redraw()
	_refresh_label()

func is_dimmed() -> bool:
	return count == 0

func _refresh_label() -> void:
	if _label != null:
		_label.text = str(count)
