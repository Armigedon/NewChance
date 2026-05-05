extends GdUnitTestSuite

const ConeScene: PackedScene = preload("res://scenes/effects/effect_breath_cone.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var cone: Node3D
var player: CharacterBody3D

func before_test() -> void:
	cone = auto_free(ConeScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(cone)
	add_child(player)
	await get_tree().process_frame

func test_cone_configures_with_origin_direction_length_angle() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.8, 10)
	assert_vector(cone.global_position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.01)
	assert_vector(cone.direction).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.001)
	assert_float(cone.length).is_equal(5.0)
	assert_float(cone.cone_angle_deg).is_equal(60.0)

func test_cone_does_not_damage_player_outside_arc() -> void:
	cone.configure(Vector3.ZERO, Vector3(1, 0, 0), 5.0, 60.0, 0.8, 10)
	player.global_position = Vector3(0, 0, 2)  # 90° off-axis from +X aim
	await get_tree().process_frame
	var initial_hp: int = player.hp
	for i in range(35):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)

func test_cone_does_not_damage_player_beyond_length() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.8, 10)
	player.global_position = Vector3(0, 0, -10)  # 10m forward, beyond 5m length
	await get_tree().process_frame
	var initial_hp: int = player.hp
	for i in range(35):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)

func test_cone_ticks_damage_to_player_in_cone() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.8, 10)
	player.global_position = Vector3(0, 0, -2)  # Vector3.FORWARD is (0,0,-1), so 2m forward is (0,0,-2)
	await get_tree().process_frame
	var initial_hp: int = player.hp
	# Advance for 0.5s in physics frames; expect 2-3 ticks of 10
	for i in range(35):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_cone_expires_after_lifetime() -> void:
	cone.configure(Vector3.ZERO, Vector3.FORWARD, 5.0, 60.0, 0.2, 10)  # 0.2s lifetime
	for i in range(20):
		await get_tree().physics_frame
	assert_bool(is_instance_valid(cone)).is_false()
