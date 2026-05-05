extends GdUnitTestSuite

const BreathScript = preload("res://scripts/entities/boss_mechanics/mechanic_static_breath.gd")
const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")
const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")

var boss: CharacterBody3D
var player: CharacterBody3D
var wall: StaticBody3D
var breath: Node

func before_test() -> void:
	boss = auto_free(BossScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	wall = auto_free(WallScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(player); player.global_position = Vector3(0, 0, 4)
	add_child(wall); wall.global_position = Vector3(0, 0, 2)
	wall.configure(30, 4.0, 4.0)  # hp, lifetime (long enough to outlive the cone), length
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
	wall.global_position = Vector3(0, 0, 2)

func test_wall_between_boss_and_player_blocks_breath() -> void:
	var initial_hp: int = player.hp
	breath.trigger(1)
	# Drive past windup
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	# Let cone tick during execution lifetime
	for i in range(60):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)

func test_wall_takes_damage_from_blocked_breath() -> void:
	var initial_wall_hp: int = wall.hp
	breath.trigger(1)
	var ticked: float = 0.0
	while ticked < 1.05:
		breath.tick(1.0 / 60.0, 1)
		ticked += 1.0 / 60.0
	for i in range(60):
		await get_tree().physics_frame
	if is_instance_valid(wall):
		assert_int(wall.hp).is_less(initial_wall_hp)

func test_wall_off_to_side_does_not_block() -> void:
	wall.global_position = Vector3(10, 0, 2)  # off the boss→player segment
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

func test_wall_behind_player_does_not_block() -> void:
	wall.global_position = Vector3(0, 0, 6)  # past player at z=4
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

func test_wall_parallel_to_segment_does_not_block() -> void:
	# Rotate wall 90° around Y so its normal aligns with the X axis instead of Z.
	# Segment from (0,0,0) → (0,0,4) is along Z; both endpoints have x=0, same side
	# of the rotated wall plane.
	wall.rotate_y(PI / 2.0)
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
