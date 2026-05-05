extends GdUnitTestSuite

const SweepScript = preload("res://scripts/entities/boss_mechanics/mechanic_sweeping_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var sweep: Node

func before_test() -> void:
	# Clean up stale state from prior tests
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	for c in get_tree().get_nodes_in_group("damage_cloud"):
		c.queue_free()
	await get_tree().process_frame
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 3)
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	sweep = SweepScript.new()
	boss._register_mechanic(sweep)
	sweep._cooldown_remaining = 99.0
	boss._player = player
	await get_tree().process_frame
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(0, 0, 3)

func test_timings() -> void:
	assert_float(sweep.windup_duration).is_equal_approx(0.8, 0.001)
	assert_float(sweep.execution_duration).is_equal_approx(2.0, 0.001)

func test_unlocked_phase_2() -> void:
	assert_int(sweep.unlock_phase).is_equal(2)
	assert_bool(sweep.is_ready(1)).is_false()

func test_sweep_damages_player_in_path() -> void:
	# Force phase 2 in boss for ready check
	boss._phase = 2
	var initial_hp: int = player.hp
	sweep.trigger(2)
	var ticked: float = 0.0
	while ticked < 0.85:  # past 0.8s windup
		sweep.tick(1.0 / 60.0, 2)
		ticked += 1.0 / 60.0
	for i in range(150):  # ~2.5s, longer than 2.0s execution
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)
