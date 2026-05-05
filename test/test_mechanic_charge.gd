extends GdUnitTestSuite

const ChargeScript = preload("res://scripts/entities/boss_mechanics/mechanic_charge.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var charge: Node

func before_test() -> void:
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 5)
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	charge = ChargeScript.new()
	boss._register_mechanic(charge)
	charge._cooldown_remaining = 99.0
	boss._player = player
	await get_tree().process_frame
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(0, 0, 5)

func test_timings() -> void:
	assert_float(charge.windup_duration).is_equal_approx(1.4, 0.001)
	assert_float(charge.execution_duration).is_equal_approx(1.5, 0.001)

func test_unlocked_phase_3() -> void:
	assert_int(charge.unlock_phase).is_equal(3)

func test_charge_damages_player_in_path() -> void:
	boss._phase = 3
	var initial_hp: int = player.hp
	charge.trigger(3)
	var ticked: float = 0.0
	while ticked < 3.0:  # past 1.4s windup + 1.5s execution
		charge.tick(1.0 / 60.0, 3)
		ticked += 1.0 / 60.0
	assert_int(player.hp).is_less(initial_hp)

func test_charge_locks_direction_at_telegraph_start() -> void:
	boss._phase = 3
	charge.trigger(3)
	charge.tick(1.0 / 60.0, 3)  # fire _on_windup_start
	var initial_dir: Vector3 = charge._charge_dir
	player.global_position = Vector3(10, 0, 0)
	charge.tick(1.0 / 60.0, 3)
	assert_vector(charge._charge_dir).is_equal_approx(initial_dir, Vector3.ONE * 0.001)
