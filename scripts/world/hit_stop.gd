extends Node

var _active_until: float = 0.0  # real-time deadline in seconds

func freeze(duration: float = 0.05) -> void:
	if duration <= 0.0:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var deadline: float = now + duration
	var was_active: bool = _active_until > now
	_active_until = max(_active_until, deadline)
	if was_active:
		# Already frozen — the in-flight timer's _on_freeze_done will see the
		# extended deadline and reschedule. No new work needed here.
		return
	Engine.time_scale = 0.0
	_schedule_unfreeze()

func _schedule_unfreeze() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var remaining: float = _active_until - now
	if remaining <= 0.0:
		Engine.time_scale = 1.0
		return
	# ignore_time_scale=true so the timer fires even at time_scale=0
	var t: SceneTreeTimer = get_tree().create_timer(remaining, true, false, true)
	t.timeout.connect(_on_freeze_done)

func _on_freeze_done() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _active_until:
		_schedule_unfreeze()
		return
	Engine.time_scale = 1.0
