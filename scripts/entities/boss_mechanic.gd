extends Node
class_name BossMechanic

const TelegraphScript = preload("res://scripts/entities/boss_telegraph.gd")

# Base class for boss mechanics. Subclasses set windup/execution durations,
# cooldowns_by_phase, unlock_phase, and override the lifecycle hooks.

var unlock_phase: int = 1
var cooldowns_by_phase: Dictionary = {1: 5.0, 2: 4.0, 3: 3.0}
var windup_duration: float = 0.6
var execution_duration: float = 0.0
var is_big: bool = true  # read by boss_dragon scheduler to enforce one-big-mechanic-at-a-time

# Telegraph is typed RefCounted (not BossTelegraph) because Godot 4.6 hard-fails
# parsing `var x: BossTelegraph` when global_script_class_cache.cfg lacks the
# entry. Opening the editor regenerates the cache; we keep RefCounted as the
# resilient declaration. Enum access goes via TelegraphScript.State.IDLE.
# TODO: tighten to `BossTelegraph` once the class cache is reliably regenerated
# in CI / on fresh checkouts. Subclasses currently reach into `_telegraph._timer`
# directly (e.g. tests) and lose IDE goto-definition because of this scar.
var _telegraph: RefCounted
# Cooldown ticks down only while the telegraph is IDLE — i.e., it runs concurrently
# with windup+execution, then continues counting once we're back to IDLE. So a 5s
# cooldown with 0.6s windup + 0.5s execution gives ~3.9s between executions.
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

# Called by boss_dragon on death so mechanics with persistent effect scenes
# (cones, mark zones) can free them — _on_execution_end won't fire if the boss
# dies mid-execution, so without this hook the cone keeps ticking damage from
# beyond the grave and the mark still strikes after the death tween.
func cleanup() -> void: pass

# Shared breath helpers — both static and sweeping breath check whether the
# segment from boss-mouth to a candidate target is blocked by a bone wall or
# green damage cloud. Lifted to the base class so a future third breath
# mechanic can't fall out of sync.
func _segment_blocked_by_wall(from: Vector3, to: Vector3) -> bool:
	var walls: Array = get_tree().get_nodes_in_group("bone_wall")
	for w in walls:
		if not is_instance_valid(w):
			continue
		if w.has_method("blocks_segment") and w.blocks_segment(from, to):
			if w.has_method("take_damage"):
				w.take_damage(1)
			return true
	return false

func _segment_blocked_by_cloud(from: Vector3, to: Vector3) -> bool:
	var clouds: Array = get_tree().get_nodes_in_group("damage_cloud")
	for c in clouds:
		if not is_instance_valid(c):
			continue
		# Spec §4: only green clouds block breath; other colors pass through.
		if c.get("base_color") != "green":
			continue
		if c.has_method("blocks_segment") and c.blocks_segment(from, to):
			return true
	return false
