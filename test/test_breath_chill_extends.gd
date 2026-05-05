extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")

var boss: CharacterBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	breath._cooldown_remaining = 99.0
	await get_tree().process_frame

func test_chill_during_windup_extends_telegraph_per_stack() -> void:
	breath.trigger(1)
	boss.apply_chill(2)  # +0.30s total → windup ≈ 1.3s
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_bool(breath.is_in_windup()).is_true()

func test_chill_outside_windup_does_not_extend_later_telegraph() -> void:
	boss.apply_chill(2)  # while breath is IDLE; should not affect next windup
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_bool(breath.is_in_execution()).is_true()

func test_chill_at_cap_does_not_extend_windup() -> void:
	# Boss already at FREEZE_THRESHOLD - 1 = 4 stacks. Additional apply_chill
	# returns added=0; on_chill_applied guards against that.
	boss.apply_chill(4)  # saturate at cap before windup
	breath.trigger(1)
	boss.apply_chill(2)  # post-cap delta = 0
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	# No extension means windup ended at 1.0s; we should be in execution.
	assert_bool(breath.is_in_execution()).is_true()

func test_chilled_windup_completes_after_full_extension() -> void:
	# Upper-bound check: with +0.30s extension, windup should END by ~1.30s.
	# Tick to 1.35s and assert no longer in windup (state is EXECUTION).
	breath.trigger(1)
	boss.apply_chill(2)  # extends to 1.30s
	var ticked: float = 0.0
	while ticked < 1.35:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_bool(breath.is_in_windup()).is_false()

func test_chill_during_execution_does_not_extend() -> void:
	# Drive past windup into execution, THEN apply chill. The on_chill_applied
	# guard requires is_in_windup(); execution-phase chill must be a no-op.
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:  # past 1.0s windup, now in execution
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	assert_bool(breath.is_in_execution()).is_true()
	var time_in_execution_before: float = breath._telegraph._timer
	boss.apply_chill(2)
	var time_in_execution_after: float = breath._telegraph._timer
	assert_float(time_in_execution_after).is_equal_approx(time_in_execution_before, 0.001)
