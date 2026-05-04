extends Node
class_name BossMechanic

const TelegraphScript = preload("res://scripts/entities/boss_telegraph.gd")

# Base class for boss mechanics. Subclasses set windup/execution durations,
# cooldowns_by_phase, unlock_phase, and override the lifecycle hooks.

var unlock_phase: int = 1
var cooldowns_by_phase: Dictionary = {1: 5.0, 2: 4.0, 3: 3.0}
var windup_duration: float = 0.6
var execution_duration: float = 0.0
var is_big: bool = true  # mutual-exclusivity flag

var _telegraph: RefCounted
var _cooldown_remaining: float = 0.0
var _boss: Node = null

func _ready() -> void:
	_telegraph = TelegraphScript.new()
	_telegraph.windup_started.connect(_on_windup_start)
	_telegraph.execution_started.connect(_on_execution_start)
	_telegraph.execution_ended.connect(_on_execution_end)
	_boss = get_parent()

@warning_ignore("unused_parameter")
func tick(delta: float, current_phase: int) -> void:
	_telegraph.windup_duration = windup_duration
	_telegraph.execution_duration = execution_duration
	_telegraph.tick(delta)
	if _telegraph.state == TelegraphScript.State.IDLE:
		_cooldown_remaining = max(0.0, _cooldown_remaining - delta)

func is_busy() -> bool:
	return _telegraph.is_busy()

func is_ready(phase: int) -> bool:
	if phase < unlock_phase:
		return false
	if _telegraph.is_busy():
		return false
	return _cooldown_remaining <= 0.0

func trigger(phase: int) -> void:
	_telegraph.windup_duration = windup_duration
	_telegraph.execution_duration = execution_duration
	_telegraph.start_windup()
	_cooldown_remaining = cooldowns_by_phase.get(phase, 5.0)

func extend_windup(extra: float) -> void:
	_telegraph.extend_windup(extra)

func is_in_windup() -> bool:
	return _telegraph.state == TelegraphScript.State.WINDUP

func is_in_execution() -> bool:
	return _telegraph.state == TelegraphScript.State.EXECUTION

# Subclasses override these:
func _on_windup_start() -> void: pass
func _on_execution_start() -> void: pass
func _on_execution_end() -> void: pass
