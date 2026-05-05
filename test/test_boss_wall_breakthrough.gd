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

func test_wall_contact_distance_matches_collision_geometry() -> void:
	# Boss is a 3x3x5 box (half-Z = 2.5m). Wall thickness is 0.4m (half 0.2m).
	# In real physics move_and_slide pushes the boss out so the minimum
	# center-to-center XZ distance is ~2.7m. The contact threshold must be
	# ≥ that or the wall-bleed never fires from real physics — only from
	# direct method calls / charge teleport. Pin the threshold so a future
	# tuning pass that drops it below the geometry minimum gets caught here.
	assert_float(boss.WALL_CONTACT_DISTANCE).is_greater_equal(2.7)

func test_boss_takes_no_damage_when_wall_just_outside_threshold() -> void:
	# Boundary case: position the boss just past the contact distance and
	# verify no damage applies. Catches regressions where the threshold
	# constant is changed without the comparison being updated.
	wall.global_position = Vector3.ZERO
	boss.global_position = Vector3(0, 0, boss.WALL_CONTACT_DISTANCE + 0.5)
	var initial_wall_hp: int = wall.hp
	for i in range(10):
		boss._apply_wall_contact_damage(0.1)
	assert_int(wall.hp).is_equal(initial_wall_hp)

func test_boss_pressed_into_wall_by_chase_damages_wall_in_real_physics() -> void:
	# End-to-end: boss in real physics chasing the player crosses paths with a
	# bone wall, gets blocked by collision (collision_mask | 8), and the contact
	# bleed reduces wall HP. Without a working contact distance, this would
	# silently pass while wall HP stayed unchanged.
	var floor_body: StaticBody3D = auto_free(StaticBody3D.new())
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(50, 0.5, 50)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.25, 0)

	# Reposition boss above the floor and put a wall + player in front so the
	# boss's normal chase logic walks it into the wall.
	boss.global_position = Vector3(0, 1.5, 0)
	wall.global_position = Vector3(0, 0.5, 4)
	wall.configure(60, 30.0, 4.0)  # extra HP and lifetime for the test window
	# Player on the far side — boss chases, hits the wall.
	player.global_position = Vector3(0, 0, 10)
	boss._player = player

	# Let physics settle then drive ~1.5s of physics frames.
	for i in range(5):
		await get_tree().physics_frame
	var initial_wall_hp: int = wall.hp
	for i in range(90):
		await get_tree().physics_frame
	assert_int(wall.hp).is_less(initial_wall_hp)
