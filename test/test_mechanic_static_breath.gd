extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 3)
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	breath._cooldown_remaining = 99.0
	await get_tree().process_frame
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(0, 0, 3)

func test_timings() -> void:
	assert_float(breath.windup_duration).is_equal_approx(1.0, 0.001)
	assert_float(breath.execution_duration).is_equal_approx(0.8, 0.001)

func test_unlocked_phase_1() -> void:
	assert_int(breath.unlock_phase).is_equal(1)

func test_breath_damages_player_in_cone() -> void:
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(0, 0, 3)
	await get_tree().physics_frame
	var initial_hp: int = player.hp
	breath.trigger(1)
	# Tick the mechanic past windup (1.0s) — cone spawns at execution_start
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	# Let cone Node3D tick damage during execution lifetime
	for i in range(60):  # ~1s, longer than 0.8s lifetime
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)
