extends GdUnitTestSuite

const BossScene: PackedScene = preload("res://scenes/entities/boss_dragon.tscn")
const WallScene: PackedScene = preload("res://scenes/effects/effect_bone_wall.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var boss: CharacterBody3D
var wall: StaticBody3D
var player: CharacterBody3D

func before_test() -> void:
	# Clear stale group nodes BEFORE any await so their _process callbacks don't
	# corrupt the test setup.
	for z in get_tree().get_nodes_in_group("mark_zone"):
		z.queue_free()
	for w in get_tree().get_nodes_in_group("bone_wall"):
		w.queue_free()
	await get_tree().process_frame
	boss = auto_free(BossScene.instantiate())
	wall = auto_free(WallScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(boss); boss.global_position = Vector3.ZERO
	add_child(wall); wall.global_position = Vector3(0, 0, 1.5)
	wall.configure(30, 10.0, 4.0)
	add_child(player); player.global_position = Vector3(0, 0, 5)
	await get_tree().process_frame
	# Clear boss's auto-registered mechanics so they don't auto-fire and corrupt
	# test state during the 60-frame await.
	for m in boss._mechanics.duplicate():
		m.queue_free()
	boss._mechanics.clear()
	boss._player = player

func test_walking_boss_damages_overlapping_wall() -> void:
	# Position boss INTO the wall and player at the same position, so the boss
	# stays in melee range (distance < 2.5m) and doesn't move away from the wall
	# during the 60-frame await.
	boss.global_position = Vector3(0, 0, 1.5)
	player.global_position = Vector3(0, 0, 1.5)
	var initial_wall_hp: int = wall.hp
	for i in range(60):
		await get_tree().physics_frame
	if is_instance_valid(wall):
		assert_int(wall.hp).is_less(initial_wall_hp)

func test_distant_boss_does_not_damage_wall() -> void:
	boss.global_position = Vector3(20, 0, 0)  # far from wall at (0,0,1.5)
	var initial_wall_hp: int = wall.hp
	for i in range(60):
		await get_tree().physics_frame
	if is_instance_valid(wall):
		assert_int(wall.hp).is_equal(initial_wall_hp)
