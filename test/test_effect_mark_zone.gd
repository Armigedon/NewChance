extends GdUnitTestSuite

const MarkScene: PackedScene = preload("res://scenes/effects/effect_mark_zone.tscn")
const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var mark: Node3D
var player: CharacterBody3D

func before_test() -> void:
	mark = auto_free(MarkScene.instantiate())
	player = auto_free(PlayerScene.instantiate())
	add_child(mark); mark.global_position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame

func test_mark_strikes_after_delay() -> void:
	mark.configure(2.0, 0.1, 30)  # 2m radius, 0.1s delay, 30 dmg
	player.global_position = Vector3.ZERO  # in zone
	var initial_hp: int = player.hp
	for i in range(15):
		await get_tree().physics_frame
	assert_int(player.hp).is_less(initial_hp)

func test_mark_does_not_damage_player_outside_zone() -> void:
	mark.configure(2.0, 0.1, 30)
	player.global_position = Vector3(5, 0, 0)
	var initial_hp: int = player.hp
	for i in range(15):
		await get_tree().physics_frame
	assert_int(player.hp).is_equal(initial_hp)

func test_mark_freed_after_strike() -> void:
	mark.configure(2.0, 0.1, 30)
	for i in range(15):
		await get_tree().physics_frame
	assert_bool(is_instance_valid(mark)).is_false()
