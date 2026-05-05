extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
const CloudScene: PackedScene = preload("res://scenes/effects/effect_cloud.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var cloud: Node3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	cloud = auto_free(CloudScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 4)
	add_child(cloud); cloud.global_position = Vector3(0, 0, 2)
	cloud.configure(10.0, 2.0, 6, [], "green")
	await get_tree().process_frame
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	breath = BreathScript.new()
	boss._register_mechanic(breath)
	breath._cooldown_remaining = 99.0
	await get_tree().process_frame
	boss.global_position = Vector3.ZERO
	player.global_position = Vector3(0, 0, 4)
	cloud.global_position = Vector3(0, 0, 2)

func test_cloud_between_boss_and_player_blocks_breath() -> void:
	var initial_hp: int = player.hp
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(60):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)

func test_cloud_off_to_side_does_not_block() -> void:
	cloud.global_position = Vector3(10, 0, 2)
	await get_tree().physics_frame
	var initial_hp: int = player.hp
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(60):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_non_green_cloud_does_not_block() -> void:
	# Spec §4: only green clouds block breath. A red cloud in the same path
	# should let breath through.
	cloud.configure(10.0, 2.0, 6, [], "red")
	await get_tree().physics_frame
	var initial_hp: int = player.hp
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(60):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_multiple_clouds_one_blocking() -> void:
	# Off-path cloud + on-path cloud: blocking still detected via second cloud.
	cloud.global_position = Vector3(10, 0, 2)  # cloud (off-path)
	var blocking_cloud: Node3D = auto_free(CloudScene.instantiate())
	add_child(blocking_cloud)
	blocking_cloud.global_position = Vector3(0, 0, 2)
	blocking_cloud.configure(10.0, 2.0, 6, [], "green")
	await get_tree().physics_frame
	var initial_hp: int = player.hp
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(60):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)
