extends GdUnitTestSuite

const PlayerScene: PackedScene = preload("res://scenes/entities/player.tscn")

var player: CharacterBody3D

func before_test() -> void:
	player = auto_free(PlayerScene.instantiate())
	add_child(player)
	await get_tree().process_frame
	player.hp = 100  # reset to known state

func test_apply_armor_adds_stacks() -> void:
	player.apply_armor(3, 5.0)
	assert_that(player._armor_stacks).is_equal(3)
	assert_that(player._armor_remaining).is_greater(0.0)

func test_armor_absorbs_damage_before_hp() -> void:
	player.apply_armor(2, 5.0)  # 2 stacks x 5 = 10 absorb
	var initial_hp: int = player.hp
	player.take_damage(8)  # all absorbed by 2 stacks (10 capacity)
	assert_that(player.hp).is_equal(initial_hp)
	# Two hits consumed both stacks (one per hit)
	assert_that(player._armor_stacks).is_less_equal(1)

func test_armor_partially_absorbs_overflow_to_hp() -> void:
	player.apply_armor(1, 5.0)  # 1 stack x 5 = 5 absorb
	var initial_hp: int = player.hp
	player.take_damage(12)  # 5 absorbed, 7 to hp
	assert_that(player.hp).is_equal(initial_hp - 7)
	assert_that(player._armor_stacks).is_equal(0)

func test_armor_expires_after_duration() -> void:
	player.apply_armor(3, 0.1)
	for i in range(20):
		player._process(1.0 / 60.0)
	assert_that(player._armor_stacks).is_equal(0)

func test_apply_armor_extends_duration_via_max() -> void:
	player.apply_armor(2, 1.0)
	player.apply_armor(1, 5.0)  # higher duration
	assert_that(player._armor_stacks).is_equal(3)  # cumulative
	assert_that(player._armor_remaining).is_equal(5.0)
