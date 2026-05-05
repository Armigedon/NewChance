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
