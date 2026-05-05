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
	# Drive the wall-contact damage method directly with the boss positioned at
	# the wall. Doing it via physics_frame is unreliable because the boss has
	# collision_mask | 8 (collides with bone walls) and gets pushed out by
	# move_and_slide, plus gravity drops it through the floorless test scene.
	boss.global_position = Vector3(0, 0, 1.5)
	wall.global_position = Vector3(0, 0, 1.5)
	var initial_wall_hp: int = wall.hp
	# Simulate 1 second of wall contact (10 frames of 0.1s each).
	for i in range(10):
		boss._apply_wall_contact_damage(0.1)
	assert_int(wall.hp).is_less(initial_wall_hp)

func test_distant_boss_does_not_damage_wall() -> void:
	boss.global_position = Vector3(20, 0, 0)  # far from wall at (0,0,1.5)
	wall.global_position = Vector3(0, 0, 1.5)
	var initial_wall_hp: int = wall.hp
	for i in range(10):
		boss._apply_wall_contact_damage(0.1)
	assert_int(wall.hp).is_equal(initial_wall_hp)
