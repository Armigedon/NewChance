extends GdUnitTestSuite

const PlayerScript = preload("res://scripts/entities/player.gd")

var player: CharacterBody3D

func before_test() -> void:
	player = auto_free(CharacterBody3D.new())
	player.set_script(PlayerScript)
	add_child(player)
	# let _ready run
	await get_tree().process_frame

func test_player_starts_with_full_hp() -> void:
	assert_that(player.hp).is_equal(100)

func test_take_damage_reduces_hp() -> void:
	player.take_damage(30)
	assert_that(player.hp).is_equal(70)

func test_take_damage_clamped_at_zero() -> void:
	player.take_damage(150)
	assert_that(player.hp).is_equal(0)

func test_died_signal_emits_at_zero_hp() -> void:
	var monitor := monitor_signals(player)
	player.take_damage(150)
	await assert_signal(player).is_emitted("died")

func test_died_signal_emits_only_once() -> void:
	player.take_damage(150)
	var monitor := monitor_signals(player)
	player.take_damage(10)
	await assert_signal(player).is_not_emitted("died")

func test_reset_restores_hp() -> void:
	player.take_damage(50)
	player.reset_run_state()
	assert_that(player.hp).is_equal(100)
